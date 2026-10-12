import AppKit
import Foundation
import PDFKit
import SextantApplication
import SextantDomain
import SnapshotTesting
import SwiftUI
import Testing

@testable import SextantUI

/// File ▸ Export and Print Layout… (ADR 0044). The print sheet can't run offscreen, so the PDF it prints is tested.
@MainActor
struct LayoutExportTests {
    @Test func thePNGIsTheShownLayerAt2x() throws {
        let layout = try example("my-layout-KlgM7-40xJ7M.json")
        let png = try #require(BoardImage.png(layout, layer: 1, mode: .symbols))
        let rep = try #require(NSBitmapImageRep(data: png))
        let size = BoardImage.size(of: layout)
        #expect(rep.pixelsWide == Int(2 * size.width) && rep.pixelsHigh == Int(2 * size.height))
        #expect(rep.size == size, "144 dpi, so it opens at its point size")
    }

    @Test(arguments: [("my-layout-KlgM7-40xJ7M.json", 3)] + (referenceExamples == nil ? [] : [("voyager-JRGQm.json", 12)]))
    func thePDFHasAPagePerLayer(file: String, pages: Int) throws {
        let layout = try example(file)
        let pdf = try #require(BoardImage.pdf(layout, mode: .symbols).flatMap(PDFDocument.init(data:)))
        #expect(pdf.pageCount == pages)
        // Vector: the title, layer names and legends are text, not pixels.
        let last = try #require(pdf.page(at: pages - 1)?.string)
        #expect(last.contains(layout.title) && last.contains(layout.layers[pages - 1].title))
    }

    /// The caps' shadows embed as soft-masked images, and printing drops the masks: they printed as grey boxes.
    /// The user's layout has color swatches, whose glow is a shadow too.
    @Test func thePDFsCapsCastNoShadows() throws {
        let pdf = try #require(BoardImage.pdf(try example("my-layout-KlgM7-40xJ7M.json"), mode: .symbols))
        #expect(pdf.range(of: Data("/Subtype /Image".utf8)) == nil)
    }

    @Test func layoutJSONRoundTrips() throws {
        let layout = try example("my-layout-KlgM7-full.json")
        #expect(try KeyboardLayout(oryxJSON: LayoutExport.json(layout)) == layout)
    }

    @Test func theZipHoldsTheGeneratedFiles() throws {
        let files = [
            "keymap.c": "const uint16_t keymaps[] = {};\n", "config.h": "#define SERIAL_NUMBER \"x\"\n", "rules.mk": "ORYX_ENABLE = yes\n",
        ]
        let zip = try LayoutExport.zip(files, folder: "My Layout QMK Source")
        #expect(try unzipped(zip) == Dictionary(uniqueKeysWithValues: files.map { ("My Layout QMK Source/\($0.key)", $0.value) }))
        // The system's zip doesn't mark names as UTF-8, so the folder's name is made ASCII.
        let unicode = try LayoutExport.zip(["keymap.c": ""], folder: "Café ⌨️ Straße QMK Source")
        #expect(try unzipped(unicode).keys.sorted() == ["Cafe Strasse QMK Source/keymap.c"])
        // A title can't climb out of the temporary folder, even with slashes that transliterate to "/".
        let hostile = try LayoutExport.zip(["keymap.c": ""], folder: "／..／..⁄x∕y QMK Source")
        #expect(try unzipped(hostile).keys.sorted() == ["-..-..-x-y QMK Source/keymap.c"])
        #expect(try unzipped(LayoutExport.zip(["keymap.c": ""], folder: "..")).keys.sorted() == ["QMK Source/keymap.c"])
    }

    /// The zip is what a build compiles: the open layout through the generator, under the identity it would flash with.
    @Test func qmkSourceGoesThroughTheGenerator() async throws {
        let model = try await window()
        await model.export(.qmkSource)
        let file = try #require(model.pendingExport?.file)
        #expect(file.contentType == .zip && file.filename == "My MacOS Layout QMK Source")
        let files = try unzipped(file.data)
        #expect(files.keys.sorted() == ["My MacOS Layout QMK Source/keymap.c"])
        #expect(files["My MacOS Layout QMK Source/keymap.c"] == "// My MacOS Layout as KlgM7/40xJ7M\n", "unedited: Oryx's serial")
    }

    /// A generator error shows in the alert before any panel opens.
    @Test func aGeneratorErrorShowsInsteadOfAPanel() async throws {
        let model = try await window(TitleGenerator { () throws(GeneratorError) in throw .unsupportedBoard("Planck") })
        await model.export(.qmkSource)
        #expect(model.pendingExport?.file == nil)
        #expect(model.pendingExport?.failure == GeneratorError.unsupportedBoard("Planck").localizedDescription)
    }

    /// Another export's panel that opened while the source was made keeps its file.
    @Test func aPanelThatOpenedMeanwhileKeepsItsFile() async throws {
        let other = ExportFile(data: Data(), contentType: .png, filename: "Other")
        let box = ModelBox()
        box.model = try await window(TitleGenerator { MainActor.assumeIsolated { box.model?.pendingExport = .saving(other) } })
        await box.model?.export(.qmkSource)
        #expect(box.model?.pendingExport?.file?.filename == "Other")
    }

    @Test func firmwareIsTheLastBuild() async throws {
        let model = try await window()
        #expect(model.canExport(.firmware) == false)
        await model.export(.firmware)
        #expect(model.pendingExport == nil)
        model.build(.build)
        for _ in 0..<200 where model.buildFlash?.artifact == nil { try await Task.sleep(for: .milliseconds(10)) }
        await model.export(.firmware)
        let file = try #require(model.pendingExport?.file)
        #expect(file.data == OneImage.image && file.contentType.preferredFilenameExtension == "bin" && file.filename == "My MacOS Layout")
        // After an edit the build no longer has every key: QMK Source would disagree with it.
        model.pendingExport = nil
        model.session?.setCode("KC_Z", layer: 0, index: 1)
        #expect(model.canExport(.firmware) == false)
        let plain = try await openUserLayout()
        #expect(plain.canExport(.qmkSource) == false, "no Build & Flash (tests, snapshots)")
        #expect(plain.canExport(.layoutJSON) && plain.canExport(.image) && plain.canExport(.pdf))
    }

    @Test func filesAreNamedForTheLayoutAndLayer() async throws {
        let model = try await openUserLayout()
        let session = try #require(model.session)
        session.select(layer: 1)
        session.setTitle("Work/Home: v2")
        await model.export(.image)
        #expect(model.pendingExport?.file?.filename == "Work-Home- v2 – Sym+Num")
        #expect(model.pendingExport?.file?.contentType == .png)
        // While its panel is open, another export waits: the panel would write the new file under the PNG's name.
        #expect(model.canExport(.layoutJSON) == false)
        await model.export(.layoutJSON)
        #expect(model.pendingExport?.file?.contentType == .png)
        model.pendingExport = nil
        await model.export(.layoutJSON)
        #expect(model.pendingExport?.file?.filename == "Work-Home- v2")
        model.pendingExport = nil
        await model.export(.pdf)
        #expect(model.pendingExport?.file?.contentType == .pdf)
    }

    @Test(.disabled(if: skipsPixelSnapshots, "the reference is rendered on the developer's macOS"))
    func boardImage() throws {
        let layout = try example("my-layout-KlgM7-40xJ7M.json")
        let renderer = ImageRenderer(content: BoardImage(layout: layout, layer: 1))
        renderer.scale = 1
        let image = try #require(renderer.nsImage)
        assertSnapshot(of: image, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "light")
    }

    // MARK: Support

    private func example(_ file: String) throws -> KeyboardLayout {
        try KeyboardLayout(oryxJSON: Data(contentsOf: exampleURL(file)))
    }

    /// The user's layout open, with Build & Flash over a generator that writes the layout's title and serial.
    private func window(_ generator: TitleGenerator = TitleGenerator()) async throws -> LayoutWindowModel {
        let store = MemoryLibrary()
        let library = Library(store: store)
        _ = try await library.importOryxJSON(try #require(userLayoutData))
        let model = LayoutWindowModel(
            library: library,
            makeBuildFlash: { session in
                BuildFlashSession(
                    session: session, library: store, generator: generator, toolchain: OneImage(), watcher: NoDevices(),
                    flasher: NoFlasher(), md5: { _ in "" })
            })
        await model.open(nil)
        return model
    }

    /// Unzips with the system's ditto: relative path → contents.
    private func unzipped(_ zip: Data) throws -> [String: String] {
        let dir = FileManager.default.temporaryDirectory.appending(path: "sextant-unzip-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let archive = dir.appending(path: "export.zip")
        try zip.write(to: archive)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, dir.appending(path: "out").path]
        try ditto.run()
        ditto.waitUntilExit()
        let out = dir.appending(path: "out")
        // Folders don't read as text, so only files remain.
        return try FileManager.default.subpathsOfDirectory(atPath: out.path).reduce(into: [:]) { files, path in
            files[path] = try? String(contentsOf: out.appending(path: path), encoding: .utf8)
        }
    }
}

private struct TitleGenerator: FirmwareGenerator {
    /// Runs as the source is made: a failure, or another export's panel opening.
    var meanwhile: @Sendable () throws(GeneratorError) -> Void = {}

    func generate(_ layout: KeyboardLayout, identity: FirmwareIdentity) throws(GeneratorError) -> GeneratedSource {
        try meanwhile()
        return GeneratedSource(files: ["keymap.c": "// \(layout.title) as \(identity.serial)\n"], sourceMap: [:])
    }
}

@MainActor private final class ModelBox {
    var model: LayoutWindowModel?
}

/// A build that finishes at once with a few bytes.
private struct OneImage: Toolchain {
    static let image = Data([0x53, 0x58, 0x01])
    func status() async -> ToolchainStatus { .ready("test") }
    func build(_ source: GeneratedSource, board: BoardDefinition) -> AsyncStream<BuildEvent> {
        AsyncStream {
            $0.yield(.finished(BuildArtifact(image: Self.image, usedBytes: 3, log: [])))
            $0.finish()
        }
    }
    func setUp() -> AsyncStream<SetupEvent> { AsyncStream { $0.finish() } }
}

private struct NoDevices: DeviceWatcher {
    func events(for board: BoardDefinition) -> AsyncStream<DeviceEvent> { AsyncStream { $0.finish() } }
}

private struct NoFlasher: Flasher {
    func flash(
        _ image: FirmwareImage, md5: String, to device: BootloaderDevice, board: BoardDefinition,
        progress: @escaping @Sendable (FlashProgress) -> Void
    ) async throws(FlashError) { throw .hardwareAccessOff }
}
