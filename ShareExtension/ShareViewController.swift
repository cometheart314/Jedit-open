import Cocoa
import UniformTypeIdentifiers

class ShareViewController: NSViewController {

    override func loadView() {
        self.view = NSView(frame: .zero)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedItems()
    }

    private func handleSharedItems() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            completeRequest()
            return
        }

        let group = DispatchGroup()
        var fileURLs: [URL] = []
        var sharedTexts: [String] = []

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        fileURLs.append(url)
                    } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                        fileURLs.append(url)
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier(UTType.rtf.identifier) {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.rtf.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let data = item as? Data {
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("JeditShare-\(UUID().uuidString)")
                            .appendingPathExtension("rtf")
                        try? data.write(to: tempURL)
                        fileURLs.append(tempURL)
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let text = item as? String {
                        sharedTexts.append(text)
                    }
                }
            } else if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
                    defer { group.leave() }
                    if let url = item as? URL {
                        sharedTexts.append(url.absoluteString)
                    }
                }
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.openInJedit(fileURLs: fileURLs, texts: sharedTexts)
        }
    }

    private func openInJedit(fileURLs: [URL], texts: [String]) {
        var allURLs = fileURLs

        for text in texts {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("JeditShare-\(UUID().uuidString)")
                .appendingPathExtension("txt")
            do {
                try text.write(to: tempURL, atomically: true, encoding: .utf8)
                allURLs.append(tempURL)
            } catch {
                NSLog("ShareExtension: Failed to write temp file: \(error)")
            }
        }

        guard !allURLs.isEmpty,
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "jp.co.artman21.Jedit-open") else {
            completeRequest()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(allURLs, withApplicationAt: appURL, configuration: configuration) { [weak self] _, _ in
            self?.completeRequest()
        }
    }

    private func completeRequest() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
