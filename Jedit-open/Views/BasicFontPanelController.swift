//
//  BasicFontPanelController.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/25.
//

import Cocoa

/// Basic Font の表示と編集を管理するコントローラ
/// Format > Font > Basic Font... メニューから呼び出される
class BasicFontPanelController: NSObject {

    // MARK: - Singleton

    static let shared = BasicFontPanelController()

    // MARK: - Notifications

    /// Basic Font が変更された時に送信される通知
    /// userInfo には "font" キーで新しい NSFont が含まれる
    static let basicFontDidChangeNotification = Notification.Name("BasicFontDidChangeNotification")

    // MARK: - Properties

    /// 現在のターゲットウィンドウコントローラ
    private weak var targetWindowController: EditorWindowController?

    /// フォントパネルがアクティブかどうか
    private var isFontPanelActive: Bool = false

    // MARK: - Initialization

    private override init() {
        super.init()
    }

    // MARK: - Public Methods

    /// Basic Font パネルを表示
    /// - Parameter windowController: 対象のウィンドウコントローラ
    func showBasicFontPanel(for windowController: EditorWindowController) {
        targetWindowController = windowController

        let fontManager = NSFontManager.shared

        // 現在の Basic Font を取得
        let currentFont = getCurrentBasicFont(from: windowController)

        // フォントパネルにターゲットを設定
        fontManager.target = self
        fontManager.action = #selector(changeFont(_:))

        // 現在のフォントをセット
        fontManager.setSelectedFont(currentFont, isMultiple: false)

        // フォントパネルを表示
        isFontPanelActive = true
        fontManager.orderFrontFontPanel(self)
    }

    /// 現在の Basic Font と Basic Character Width を表示するアラートを表示
    /// - Parameter windowController: 対象のウィンドウコントローラ
    /// - Parameter font: 表示するフォント（nilの場合はプリセットデータから取得）
    func showBasicFontInfo(for windowController: EditorWindowController, font: NSFont? = nil) {
        let displayFont = font ?? getCurrentBasicFont(from: windowController)
        let charWidth = basicCharWidth(from: displayFont)

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Basic Font", comment: "")

        let fontName = displayFont.displayName ?? displayFont.fontName
        let fontSize = displayFont.pointSize

        // フォント情報
        let infoText = String(format: NSLocalizedString(
            "Font: %@\nSize: %.1f pt\nBasic Character Width: %.2f pt",
            comment: "Basic font info format"
        ), fontName, fontSize, charWidth)

        alert.informativeText = infoText

        // 説明文を小さいフォントで表示するアクセサリビュー
        let descriptionLabel = NSTextField(labelWithString: NSLocalizedString(
            "The Basic Character Width is used for the character ruler scale and fixed-width document layout.",
            comment: "Basic font description"
        ))
        descriptionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        descriptionLabel.textColor = .secondaryLabelColor
        descriptionLabel.alignment = .left
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.preferredMaxLayoutWidth = 300
        descriptionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        // サイズを計算してフレームを設定
        let size = descriptionLabel.sizeThatFits(NSSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
        descriptionLabel.frame = NSRect(x: 0, y: 0, width: 300, height: size.height)

        alert.accessoryView = descriptionLabel
        alert.addButton(withTitle: NSLocalizedString("Change Font...", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))

        if let window = windowController.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    // Change Font... ボタンが押された
                    self?.showBasicFontPanel(for: windowController)
                }
            }
        }
    }

    // MARK: - Private Methods

    /// ウィンドウコントローラから現在の Basic Font を取得
    private func getCurrentBasicFont(from windowController: EditorWindowController) -> NSFont {
        if let document = windowController.document as? Document,
           let presetData = document.presetData {
            let fontData = presetData.fontAndColors
            if let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                return font
            }
        }
        // デフォルトフォント
        return NSFont.systemFont(ofSize: 14)
    }

    // MARK: - Font Panel Delegate

    /// フォントパネルからフォントが変更された時
    @objc func changeFont(_ sender: Any?) {
        guard isFontPanelActive else { return }
        guard let fontManager = sender as? NSFontManager else { return }
        guard let windowController = targetWindowController else { return }

        // 現在のフォントを取得
        let currentFont = getCurrentBasicFont(from: windowController)

        // 新しいフォントに変換
        let newFont = fontManager.convert(currentFont)

        // ドキュメントのプリセットデータを更新
        updateBasicFont(newFont, for: windowController)

        // 通知を送信
        NotificationCenter.default.post(
            name: BasicFontPanelController.basicFontDidChangeNotification,
            object: windowController,
            userInfo: ["font": newFont]
        )

        // フォントパネルを閉じて、更新されたBasic Font情報パネルを再表示
        NSFontPanel.shared.orderOut(nil)
        isFontPanelActive = false

        // 少し遅延させてパネルを再表示（フォントパネルが閉じるのを待つ）
        // 新しいフォントを直接渡して表示
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showBasicFontInfo(for: windowController, font: newFont)
        }
    }

    /// Basic Font を更新
    private func updateBasicFont(_ font: NSFont, for windowController: EditorWindowController) {
        guard let document = windowController.document as? Document else { return }

        // プリセットデータを更新
        if document.presetData != nil {
            document.presetData?.fontAndColors.baseFontName = font.fontName
            document.presetData?.fontAndColors.baseFontSize = font.pointSize
        }

        // ウィンドウコントローラにレイアウト更新を依頼
        windowController.basicFontDidChange(font)
    }
}
