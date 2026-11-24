import AppKit

final class ExportProgressPanel: NSPanel {
    var onCancel: (() -> Void)?

    private let statusLabel = NSTextField(labelWithString: "Preparing export")
    private let detailLabel = NSTextField(labelWithString: "")
    private let progressBar = NSProgressIndicator()
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    init(format: ExportFormat, conversationName: String) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 150),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        title = format == .docx ? "Export Word Document" : "Export PDF"
        isReleasedWhenClosed = false
        level = .modalPanel
        setupViews(conversationName: conversationName)
    }

    private func setupViews(conversationName: String) {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 150))

        let conversationLabel = NSTextField(labelWithString: conversationName)
        conversationLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        conversationLabel.lineBreakMode = .byTruncatingTail

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor

        progressBar.style = .bar
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 100
        progressBar.doubleValue = 0

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        let stack = NSStackView(views: [
            conversationLabel,
            statusLabel,
            progressBar,
            detailLabel,
            cancelButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            progressBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        contentView = content
    }

    func update(_ progress: ExportProgress) {
        progressBar.doubleValue = progress.fraction * 100
        statusLabel.stringValue = statusText(for: progress.phase)

        var detail = "\(progress.processedMessages) of \(progress.totalMessages) messages"
        if progress.totalImages > 0 {
            detail += " · \(progress.processedImages) of \(progress.totalImages) images"
        }
        if let remaining = progress.estimatedRemaining, remaining > 0 {
            if remaining < 60 {
                detail += " · about \(Int(remaining.rounded()))s left"
            } else {
                detail += " · about \(Int((remaining / 60).rounded()))m left"
            }
        }
        detailLabel.stringValue = detail
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    func finish() {
        progressBar.doubleValue = 100
        statusLabel.stringValue = "Finished"
        cancelButton.isEnabled = false
        // stopModal() alone leaves the panel on screen; the panel has no close
        // button, so it would sit there disabled until the app quits.
        close()
    }

    @objc private func cancelTapped() {
        cancelButton.isEnabled = false
        statusLabel.stringValue = "Cancelling…"
        onCancel?()
    }

    private func statusText(for phase: ExportProgress.Phase) -> String {
        switch phase {
        case .preparing: return "Preparing messages"
        case .rendering: return "Rendering document"
        case .images: return "Preparing images"
        case .compressing: return "Packaging document"
        case .finishing: return "Finishing"
        }
    }
}
