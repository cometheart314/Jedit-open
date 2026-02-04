//
//  PropertyPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/04.
//

import Cocoa

/// ドキュメントプロパティ設定パネル
class PropertyPanel: NSWindow {

    // MARK: - IBOutlets

    @IBOutlet var authorField: NSTextField!
    @IBOutlet var companyField: NSTextField!
    @IBOutlet var copyrightField: NSTextField!
    @IBOutlet var titleField: NSTextField!
    @IBOutlet var subjectField: NSTextField!
    @IBOutlet var keywordsTokenField: NSTokenField!
    @IBOutlet var commentTextView: NSTextView!
    @IBOutlet var cancelButton: NSButton!
    @IBOutlet var setButton: NSButton!

    // MARK: - Properties

    private weak var targetDocument: NSDocument?

    // MARK: - Initialization

    /// XIBからパネルをロードして返す
    static func loadFromNib() -> PropertyPanel? {
        var topLevelObjects: NSArray?
        let bundle = Bundle.main
        let nibName = "PropertyPanel"

        guard bundle.loadNibNamed(nibName, owner: nil, topLevelObjects: &topLevelObjects) else {
            print("Failed to load \(nibName).xib")
            return nil
        }

        // NSWindowを探す
        for object in topLevelObjects ?? [] {
            if let panel = object as? PropertyPanel {
                return panel
            }
        }

        return nil
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.isReleasedWhenClosed = false

        // Cancelボタンのアクションを設定
        cancelButton?.target = self
        cancelButton?.action = #selector(cancelClicked(_:))

        // Setボタンのアクションを設定
        setButton?.target = self
        setButton?.action = #selector(setClicked(_:))
    }

    // MARK: - Public Methods

    /// ドキュメントに対してパネルを表示
    func showPanel(for document: NSDocument) {
        self.targetDocument = document

        // 現在の設定を読み込んでUIに反映
        loadCurrentSettings()

        // 書類ウィンドウの中央にパネルを配置
        centerOnDocumentWindow()

        // パネルを表示
        self.makeKeyAndOrderFront(nil)
    }

    /// パネルを書類ウィンドウの中央に配置
    private func centerOnDocumentWindow() {
        guard let documentWindow = targetDocument?.windowControllers.first?.window else {
            // 書類ウィンドウがない場合は画面中央に配置
            self.center()
            return
        }

        let docFrame = documentWindow.frame
        let panelSize = self.frame.size

        // 書類ウィンドウの中央座標を計算
        let centerX = docFrame.origin.x + (docFrame.width - panelSize.width) / 2
        let centerY = docFrame.origin.y + (docFrame.height - panelSize.height) / 2

        self.setFrameOrigin(NSPoint(x: centerX, y: centerY))
    }

    // MARK: - Private Methods

    /// ターゲットドキュメントをDocumentとして取得
    private var document: Document? {
        return targetDocument as? Document
    }

    private func loadCurrentSettings() {
        guard let document = document,
              let properties = document.presetData?.properties else { return }

        authorField?.stringValue = properties.author
        companyField?.stringValue = properties.company
        copyrightField?.stringValue = properties.copyright
        titleField?.stringValue = properties.title
        subjectField?.stringValue = properties.subject
        // キーワードをカンマ区切りからトークン配列に変換
        if !properties.keywords.isEmpty {
            let keywordsArray = properties.keywords.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            keywordsTokenField?.objectValue = keywordsArray
        } else {
            keywordsTokenField?.objectValue = []
        }
        commentTextView?.string = properties.comment
    }

    // MARK: - Actions

    @objc private func cancelClicked(_ sender: Any) {
        self.orderOut(nil)
    }

    @objc private func setClicked(_ sender: Any) {
        guard let document = document else { return }

        // プロパティをDocumentに反映
        document.presetData?.properties.author = authorField?.stringValue ?? ""
        document.presetData?.properties.company = companyField?.stringValue ?? ""
        document.presetData?.properties.copyright = copyrightField?.stringValue ?? ""
        document.presetData?.properties.title = titleField?.stringValue ?? ""
        document.presetData?.properties.subject = subjectField?.stringValue ?? ""
        // トークン配列をカンマ区切り文字列に変換
        if let tokens = keywordsTokenField?.objectValue as? [String] {
            document.presetData?.properties.keywords = tokens.joined(separator: ", ")
        } else {
            document.presetData?.properties.keywords = ""
        }
        document.presetData?.properties.comment = commentTextView?.string ?? ""

        // ドキュメントを更新済みとしてマーク
        document.updateChangeCount(.changeDone)

        // パネルを閉じる
        self.orderOut(nil)
    }
}
