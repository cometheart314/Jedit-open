//
//  Document.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa

class Document: NSDocument {

    // MARK: - Notifications

    static let documentTypeDidChangeNotification = Notification.Name("DocumentTypeDidChange")

    // MARK: - Properties

    var textStorage: NSTextStorage = NSTextStorage()
    var documentType: NSAttributedString.DocumentType = .plain
    var containerInset = NSSize(width: 10, height: 10)
    


    // MARK: - Initialization

    override init() {
        super.init()
    }

    override nonisolated class var autosavesInPlace: Bool {
        return true
    }

    // MARK: - Window Controllers

    override func makeWindowControllers() {
        // Document.xibからEditorWindowControllerを読み込む
        let windowController = EditorWindowController(windowNibName: NSNib.Name("Document"))
        self.addWindowController(windowController)
    }

    override func windowControllerDidLoadNib(_ windowController: NSWindowController) {
        super.windowControllerDidLoadNib(windowController)

        // TextStorageを設定
        // ウィンドウコントローラーのcontentViewからNSTextViewを探して、textStorageを設定する
        if let window = windowController.window,
           let contentView = window.contentView {
            if let textView = findTextView(in: contentView) {
                textView.layoutManager?.replaceTextStorage(textStorage)
            }
        }
    }

    // MARK: - Helper Methods

    private func findTextView(in view: NSView) -> NSTextView? {
        if let textView = view as? NSTextView {
            return textView
        }

        for subview in view.subviews {
            if let textView = findTextView(in: subview) {
                return textView
            }
        }

        return nil
    }

    // MARK: - Reading and Writing

    // RTFDファイルパッケージの読み込みをサポート
    override nonisolated func read(from fileWrapper: FileWrapper, ofType typeName: String) throws {
        if typeName == "com.apple.rtfd" {
            // RTFDはFileWrapperから直接読み込む
            guard let attributedString = NSAttributedString(rtfdFileWrapper: fileWrapper, documentAttributes: nil) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read RTFD document"
                ])
            }

            MainActor.assumeIsolated {
                self.documentType = .rtfd
                self.textStorage.setAttributedString(attributedString)
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
        } else {
            // その他のファイルタイプは通常のread(from:ofType:)に委譲
            if let data = fileWrapper.regularFileContents {
                try read(from: data, ofType: typeName)
            } else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read file contents"
                ])
            }
        }
    }

    // RTFDファイルパッケージの書き込みをサポート
    override func fileWrapper(ofType typeName: String) throws -> FileWrapper {
        if typeName == "com.apple.rtfd" {
            // RTFDはFileWrapperとして書き出す
            let range = NSRange(location: 0, length: textStorage.length)
            guard let fileWrapper = textStorage.rtfdFileWrapper(from: range, documentAttributes: [:]) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not create RTFD file wrapper"
                ])
            }
            return fileWrapper
        } else {
            // その他のファイルタイプは通常のdata(ofType:)を使用
            let data = try data(ofType: typeName)
            return FileWrapper(regularFileWithContents: data)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        // ドキュメントタイプを判定
        let docType: NSAttributedString.DocumentType
        switch typeName {
        case "public.rtf":
            docType = .rtf
        case "com.apple.rtfd":
            docType = .rtfd
        default:
            docType = .plain
        }

        // ドキュメントタイプを保存
        self.documentType = docType

        // ドキュメントタイプに応じて保存
        if docType == .plain {
            // プレーンテキストの場合はUTF-8でエンコード
            let string = textStorage.string
            guard let data = string.data(using: .utf8) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not encode text as UTF-8"
                ])
            }
            return data
        } else {
            // RTFまたはRTFDの場合はNSAttributedStringを使用
            let range = NSRange(location: 0, length: textStorage.length)
            let options: [NSAttributedString.DocumentAttributeKey: Any] = [
                .documentType: docType
            ]

            do {
                let data = try textStorage.data(from: range, documentAttributes: options)
                return data
            } catch {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not write \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }

    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        // ドキュメントタイプを判定
        let docType: NSAttributedString.DocumentType
        switch typeName {
        case "public.rtf":
            docType = .rtf
        case "com.apple.rtfd":
            docType = .rtfd
        default:
            docType = .plain
        }

        // ドキュメントタイプに応じて読み込み
        if docType == .plain {
            // プレーンテキストの場合はUTF-8でデコード
            guard let string = String(data: data, encoding: .utf8) else {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not decode text as UTF-8"
                ])
            }

            // メインアクターで実行
            MainActor.assumeIsolated {
                self.documentType = .plain
                self.textStorage.replaceCharacters(in: NSRange(location: 0, length: self.textStorage.length), with: string)
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
            }
        } else {
            // RTFまたはRTFDの場合はNSAttributedStringを使用
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: docType
            ]

            do {
                let attributedString = try NSAttributedString(data: data, options: options, documentAttributes: nil)

                // メインアクターで実行
                MainActor.assumeIsolated {
                    self.documentType = docType
                    self.textStorage.setAttributedString(attributedString)
                    NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: self)
                }
            } catch {
                throw NSError(domain: NSOSStatusErrorDomain, code: unimpErr, userInfo: [
                    NSLocalizedDescriptionKey: "Could not read \(docType == .rtf ? "RTF" : "RTFD") document: \(error.localizedDescription)"
                ])
            }
        }
    }
}
