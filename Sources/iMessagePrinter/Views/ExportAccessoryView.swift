import AppKit

final class ExportAccessoryView: NSView {
    private let popup = NSPopUpButton()
    var selectedMode: PDFExportService.AttachmentMode {
        PDFExportService.AttachmentMode(rawValue: popup.indexOfSelectedItem) ?? .thumbnail
    }

    convenience init() {
        self.init(frame: NSRect(x: 0, y: 0, width: 320, height: 42))
        setupView()
    }

    private func setupView() {
        let label = NSTextField(labelWithString: "Images:")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false

        popup.translatesAutoresizingMaskIntoConstraints = false
        for mode in PDFExportService.AttachmentMode.allCases {
            popup.addItem(withTitle: mode.label)
        }
        popup.selectItem(at: 1) // Default to thumbnails

        addSubview(label)
        addSubview(popup)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            popup.centerYAnchor.constraint(equalTo: centerYAnchor),
            popup.widthAnchor.constraint(greaterThanOrEqualToConstant: 180),
        ])
    }
}
