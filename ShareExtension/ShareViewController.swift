import Cocoa
import UniformTypeIdentifiers
import os.log

class ShareViewController: NSViewController {

    private static let jeditBundleID = "jp.co.artman21.Jedit-open"
    private static let logger = Logger(subsystem: "jp.co.artman21.Jedit-open.ShareExtension", category: "share")

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()

    private static func timestamp() -> String {
        timestampFormatter.string(from: Date())
    }

    override func loadView() {
        self.view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }

    // MARK: - Shared Items Handling

    private func handleSharedItems() {
        guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem],
              !inputItems.isEmpty else {
            Self.logger.warning("No input items received")
            completeRequest()
            return
        }

        let group = DispatchGroup()
        var fileURLs: [URL] = []
        var sharedTexts: [String] = []

        for extensionItem in inputItems {
            // macOS text sharing provides text via attributedContentText (not attachments)
            if let attrText = extensionItem.attributedContentText, attrText.length > 0 {
                let range = NSRange(location: 0, length: attrText.length)
                if let rtfData = try? attrText.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                ) {
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent("JeditShare-\(Self.timestamp())")
                        .appendingPathExtension("rtf")
                    do {
                        try rtfData.write(to: tempURL)
                        fileURLs.append(tempURL)
                    } catch {
                        Self.logger.error("RTF write error: \(error.localizedDescription, privacy: .public)")
                        sharedTexts.append(attrText.string)
                    }
                } else {
                    sharedTexts.append(attrText.string)
                }
            }

            for attachment in extensionItem.attachments ?? [] {
                if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
                        defer { group.leave() }
                        if let url = item as? URL {
                            fileURLs.append(url)
                        } else if let data = item as? Data,
                                  let url = URL(dataRepresentation: data, relativeTo: nil) {
                            fileURLs.append(url)
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.rtf.identifier, options: nil) { item, error in
                        defer { group.leave() }
                        if let data = item as? Data {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("JeditShare-\(Self.timestamp())")
                                .appendingPathExtension("rtf")
                            try? data.write(to: tempURL)
                            fileURLs.append(tempURL)
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, error in
                        defer { group.leave() }
                        if let text = item as? String {
                            sharedTexts.append(text)
                        } else if let data = item as? Data,
                                  let text = String(data: data, encoding: .utf8) {
                            sharedTexts.append(text)
                        }
                    }
                } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    group.enter()
                    attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, error in
                        defer { group.leave() }
                        if let url = item as? URL {
                            sharedTexts.append(url.absoluteString)
                        }
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.openInJedit(fileURLs: fileURLs, texts: sharedTexts)
        }
    }

    // MARK: - Open in Jedit

    private func openInJedit(fileURLs: [URL], texts: [String]) {
        var allURLs = fileURLs

        for text in texts {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("JeditShare-\(Self.timestamp())")
                .appendingPathExtension("txt")
            do {
                try text.write(to: tempURL, atomically: true, encoding: .utf8)
                allURLs.append(tempURL)
            } catch {
                Self.logger.error("Failed to write temp file: \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !allURLs.isEmpty else {
            completeRequest()
            return
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.jeditBundleID) else {
            Self.logger.error("Jedit not found")
            completeRequest()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(allURLs, withApplicationAt: appURL, configuration: configuration) { [weak self] _, error in
            if let error = error {
                Self.logger.error("Failed to open in Jedit: \(error.localizedDescription, privacy: .public)")
            }
            self?.completeRequest()
        }
    }

    // MARK: - Completion

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
