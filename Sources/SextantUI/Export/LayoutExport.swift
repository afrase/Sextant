import AppKit
import Foundation
import SextantApplication
import SextantDomain
import SwiftUI
import UniformTypeIdentifiers

/// What File ▸ Export can write (spec §9.1).
enum ExportKind {
    /// The layout in Sextant's format, which is Oryx's revision shape (architecture §2.1).
    case layoutJSON
    /// The QMK source a build compiles, zipped.
    case qmkSource
    /// The last build's image, DFU suffix included.
    case firmware
    /// The shown layer as a PNG.
    case image
    /// Every layer as a vector PDF, one page each.
    case pdf
}

/// A file waiting for File ▸ Export's save panel. It is made before the panel opens, so writing it can't fail halfway.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = []
    var data: Data
    var contentType: UTType
    /// The suggested name, without its extension: the save panel adds the content type's.
    var filename: String

    init(data: Data, contentType: UTType, filename: String) {
        self.data = data
        self.contentType = contentType
        self.filename = filename
    }

    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }

    func fileWrapper(configuration: WriteConfiguration) -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

/// File ▸ Export's state: a file waiting for its save panel, or why it couldn't be made or saved.
enum PendingExport {
    case saving(ExportFile)
    case failed(String)

    var file: ExportFile? { if case let .saving(file) = self { file } else { nil } }
    var failure: String? { if case let .failed(message) = self { message } else { nil } }
}

/// Why File ▸ Export couldn't make its file, in Sextant's words.
enum ExportError: LocalizedError {
    /// The board couldn't be drawn into the PNG or the PDF.
    case drawing
    case encoding
    /// The system's reason follows Sextant's words.
    case zipping(String)

    var errorDescription: String? {
        switch self {
        case .drawing: String(localized: "The board couldn’t be drawn.")
        case .encoding: String(localized: "The layout couldn’t be written as JSON.")
        case let .zipping(reason): String(localized: "The QMK source couldn’t be zipped. \(reason)")
        }
    }
}

enum LayoutExport {
    /// The layout as its package's `layout.json` holds it, so it opens in Sextant and other tools alike.
    static func json(_ layout: KeyboardLayout) throws(ExportError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        do { return try encoder.encode(layout) } catch { throw .encoding }
    }

    /// `files` in a folder named `folder`, zipped by the system (a coordinated read `.forUploading` zips a folder), so
    /// no zip library is needed. The folder's name is made ASCII: the system doesn't mark names as UTF-8, so zip tools
    /// outside Apple's would garble any other.
    static func zip(_ files: [String: String], folder: String) throws(ExportError) -> Data {
        let root = FileManager.default.temporaryDirectory.appending(path: "sextant-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let latin = folder.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? folder
        let ascii = String(String.UnicodeScalarView(latin.unicodeScalars.filter(\.isASCII)))
        // Cleaned after transliterating, which turns look-alike slashes (／ ⁄ ∕) into "/": a title never names a path.
        let words = filename(ascii).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let directory = root.appending(path: words.allSatisfy { $0 == "." } ? "QMK Source" : words, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, contents) in files { try Data(contents.utf8).write(to: directory.appending(path: name)) }
            var coordination: NSError?
            var zipped: Result<Data, any Error> = .failure(CocoaError(.fileReadUnknown))
            NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordination) { zip in
                zipped = Result { try Data(contentsOf: zip) }
            }
            if let coordination { throw coordination }
            return try zipped.get()
        } catch {
            throw .zipping(error.localizedDescription)
        }
    }

    /// A file name from a layout title: `/` and `:` can't be in one.
    static func filename(_ title: String) -> String {
        String(title.map { "/:".contains($0) ? "-" : $0 })
    }
}

extension LayoutWindowModel {
    func canExport(_ kind: ExportKind) -> Bool {
        // The open panel writes whatever file is pending, so a second export would land under the first one's name.
        guard session != nil, pendingExport?.file == nil else { return false }
        switch kind {
        case .qmkSource: return buildFlash != nil
        case .firmware: return buildFlash?.currentArtifact != nil
        case .layoutJSON, .image, .pdf: return true
        }
    }

    /// Makes the file, then opens the save panel for it; a failure shows in an alert.
    func export(_ kind: ExportKind) async {
        guard canExport(kind), let layout = session?.layout else { return }
        // SwiftUI never shows the panel over another sheet or alert, even after it closes, so the export would wait for good.
        guard NSApp?.mainWindow?.attachedSheet == nil else { return NSSound.beep() }
        let name = LayoutExport.filename(layout.title)
        do {
            switch kind {
            case .layoutJSON:
                pendingExport = .saving(ExportFile(data: try LayoutExport.json(layout), contentType: .json, filename: name))
            case .qmkSource:
                // Another export's panel may have opened while the source was made; it keeps its file.
                guard let source = try await buildFlash?.source(), pendingExport?.file == nil else { return }
                let folder = String(localized: "\(name) QMK Source")
                pendingExport = .saving(
                    ExportFile(data: try LayoutExport.zip(source.files, folder: folder), contentType: .zip, filename: folder))
            case .firmware:
                guard let image = buildFlash?.currentArtifact?.image else { return }
                // The system's .bin type is MacBinary's; only its extension matters here.
                pendingExport = .saving(ExportFile(data: image, contentType: UTType(filenameExtension: "bin") ?? .data, filename: name))
            case .image:
                let layer = session?.selection.layer ?? 0
                guard let png = BoardImage.png(layout, layer: layer, mode: legendMode) else { throw ExportError.drawing }
                let title = layout.layers[safe: layer].map { LayoutExport.filename("\(name) – \($0.title)") } ?? name
                pendingExport = .saving(ExportFile(data: png, contentType: .png, filename: title))
            case .pdf:
                guard let pdf = BoardImage.pdf(layout, mode: legendMode) else { throw ExportError.drawing }
                pendingExport = .saving(ExportFile(data: pdf, contentType: .pdf, filename: name))
            }
        } catch {
            pendingExport = .failed(error.localizedDescription)
        }
    }
}

/// File ▸ Export's one save panel, and its alert when the file couldn't be made or saved.
struct ExportPresenter: ViewModifier {
    var model: LayoutWindowModel

    func body(content: Content) -> some View {
        let file = model.pendingExport?.file
        content
            .fileExporter(
                isPresented: Binding(
                    get: { file != nil },
                    // Only a panel's own state: a write failure reported meanwhile stays for the alert.
                    set: { if !$0, model.pendingExport?.file != nil { model.pendingExport = nil } }),
                document: file, contentType: file?.contentType ?? .data, defaultFilename: file?.filename
            ) { result in
                if case let .failure(error) = result, (error as? CocoaError)?.code != .userCancelled {
                    model.pendingExport = .failed(error.localizedDescription)
                }
            }
            .alert(
                Text("Sextant couldn’t export the layout"),
                isPresented: Binding(get: { model.pendingExport?.failure != nil }, set: { if !$0 { model.pendingExport = nil } }),
                presenting: model.pendingExport?.failure
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(verbatim: message)
            }
    }
}
