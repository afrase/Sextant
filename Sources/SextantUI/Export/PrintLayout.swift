import AppKit
import PDFKit

extension LayoutWindowModel {
    /// Print Layout… (⌘P): every layer, one page each, from the same PDF as File ▸ Export. PDFKit's print operation brings
    /// the system's print sheet: preview, page setup and Save as PDF.
    func printLayout() {
        guard let layout = session?.layout else { return }
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        // Every page is wider than tall; portrait paper would turn the boards sideways.
        info.orientation = .landscape
        guard let pdf = BoardImage.pdf(layout, mode: legendMode), let document = PDFDocument(data: pdf),
            let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit, autoRotate: true)
        else { return NSSound.beep() }
        operation.jobTitle = layout.title
        // The layout window, even while a panel of the app is key.
        if let window = NSApp.mainWindow {
            operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            operation.run()
        }
    }
}
