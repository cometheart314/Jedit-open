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

    /// フォントパネルがアクティブかどうか（Basic Font パネル用）
    private(set) var isFontPanelActive: Bool = false

    /// フォントパネルで選択中のフォント（パネルが閉じられた時に適用される）
    private var pendingFont: NSFont?

    /// フォントパネル閉鎖の監視用
    private var fontPanelObserver: Any?

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

        // pending font をクリア
        pendingFont = nil

        // フォントパネルを表示
        isFontPanelActive = true
        fontManager.orderFrontFontPanel(self)

        // フォントパネル表示後にフォントを設定（表示後でないと反映されない場合がある）
        let fontPanel = NSFontPanel.shared
        fontPanel.setPanelFont(currentFont, isMultiple: false)

        // フォントパネルが閉じられた時の監視を開始
        startObservingFontPanel()
    }

    /// フォントパネルの閉鎖を監視開始
    private func startObservingFontPanel() {
        // 既存の監視を解除
        stopObservingFontPanel()

        // NSWindow の willClose 通知を監視
        fontPanelObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: NSFontPanel.shared,
            queue: .main
        ) { [weak self] _ in
            self?.fontPanelWillClose()
        }
    }

    /// フォントパネルの監視を停止
    private func stopObservingFontPanel() {
        if let observer = fontPanelObserver {
            NotificationCenter.default.removeObserver(observer)
            fontPanelObserver = nil
        }
    }

    /// フォントパネルが閉じられた時の処理
    private func fontPanelWillClose() {
        guard isFontPanelActive else { return }
        guard let windowController = targetWindowController else { return }

        isFontPanelActive = false
        stopObservingFontPanel()

        // NSFontManager のターゲットをリセットして通常のフォント変更が機能するようにする
        let fontManager = NSFontManager.shared
        fontManager.target = nil
        
        // pending font があれば適用
        if let font = pendingFont {
            // ドキュメントのプリセットデータを更新
            updateBasicFont(font, for: windowController)

            // 通知を送信
            NotificationCenter.default.post(
                name: BasicFontPanelController.basicFontDidChangeNotification,
                object: windowController,
                userInfo: ["font": font]
            )

            // 更新されたBasic Font情報パネルを表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showBasicFontInfo(for: windowController, font: font)
            }
        }

        pendingFont = nil
    }

    /// 現在の Basic Font と Basic Character Width を表示するアラートを表示
    /// - Parameter windowController: 対象のウィンドウコントローラ
    /// - Parameter font: 表示するフォント（nilの場合はプリセットデータから取得）
    func showBasicFontInfo(for windowController: EditorWindowController, font: NSFont? = nil) {
        let displayFont = font ?? getCurrentBasicFont(from: windowController)
        let charWidth = basicCharWidth(from: displayFont)

        let alert = NSAlert()
        alert.messageText = "Basic Font".localized

        let fontName = displayFont.displayName ?? displayFont.fontName
        let fontSize = displayFont.pointSize

        // フォント情報
        let infoText = String(format: "Font: %@\nSize: %.1f pt\nBasic Character Width: %.2f pt".localized, fontName, fontSize, charWidth)

        alert.informativeText = infoText

        // 説明文を小さいフォントで表示するアクセサリビュー
        let descriptionLabel = NSTextField(labelWithString: "The Basic Character Width is used for the character ruler scale and fixed-width document layout.".localized)
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
        alert.addButton(withTitle: "Change Font...".localized)
        alert.addButton(withTitle: "OK".localized)

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
    /// フォントパネルが開いている間は pending font として保持し、
    /// パネルが閉じられた時に適用する
    @objc func changeFont(_ sender: Any?) {
        guard isFontPanelActive else { return }
        guard let fontManager = sender as? NSFontManager else { return }

        // 現在のフォントを基準に新しいフォントを取得
        // pending font があればそれを基準にする（連続変更に対応）
        let baseFont = pendingFont ?? getCurrentBasicFont(from: targetWindowController)

        // 新しいフォントに変換
        let newFont = fontManager.convert(baseFont)

        // pending font として保持（パネルが閉じられた時に適用される）
        pendingFont = newFont
    }

    /// ウィンドウコントローラから現在のフォントを取得（nil許容版）
    private func getCurrentBasicFont(from windowController: EditorWindowController?) -> NSFont {
        guard let windowController = windowController else {
            return NSFont.systemFont(ofSize: 14)
        }
        return getCurrentBasicFont(from: windowController)
    }

    /// Basic Font を更新
    private func updateBasicFont(_ font: NSFont, for windowController: EditorWindowController) {
        guard let document = windowController.document as? Document else { return }

        // プリセットデータを更新
        if document.presetData != nil {
            document.presetData?.fontAndColors.baseFontName = font.fontName
            document.presetData?.fontAndColors.baseFontSize = font.pointSize
        }

        // presetDataEdited フラグを立てる（ウィンドウタイトルに「Edited」は表示されない）
        document.presetDataEdited = true

        // ウィンドウコントローラにレイアウト更新を依頼
        windowController.basicFontDidChange(font)
    }
}
