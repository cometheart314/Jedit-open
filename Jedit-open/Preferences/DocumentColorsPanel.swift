//
//  DocumentColorsPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/31.
//

import Cocoa

/// ドキュメントカラー設定パネル
class DocumentColorsPanel: NSPanel {

    // MARK: - IBOutlets

    @IBOutlet var characterColorWell: NSColorWell!
    @IBOutlet var backgroundColorWell: NSColorWell!
    @IBOutlet var invisiblesColorWell: NSColorWell!
    @IBOutlet var caretColorWell: NSColorWell!
    @IBOutlet var highlightColorWell: NSColorWell!
    @IBOutlet var lineNumberColorWell: NSColorWell!
    @IBOutlet var headerColorWell: NSColorWell!
    @IBOutlet var footerColorWell: NSColorWell!
    @IBOutlet var lineNumberBackgroundColorWell: NSColorWell!

    @IBOutlet var themePopup: NSPopUpButton!
    @IBOutlet var cancelButton: NSButton!
    @IBOutlet var setButton: NSButton!

    // MARK: - Properties

    private var completionHandler: ((Bool) -> Void)?
    private weak var sheetParentWindow: NSWindow?
    private var currentColors: NewDocData.FontAndColorsData.Colors?

    // MARK: - Initialization

    /// XIBからパネルをロードして返す
    static func loadFromNib() -> DocumentColorsPanel? {
        var topLevelObjects: NSArray?
        let bundle = Bundle.main
        let nibName = "DocumentColorsPanel"

        guard bundle.loadNibNamed(nibName, owner: nil, topLevelObjects: &topLevelObjects) else {
            print("Failed to load \(nibName).xib")
            return nil
        }

        // NSPanelを探す
        for object in topLevelObjects ?? [] {
            if let panel = object as? DocumentColorsPanel {
                panel.setupThemePopup()
                return panel
            }
        }

        return nil
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.isReleasedWhenClosed = false
    }

    // MARK: - Theme Popup Setup

    private func setupThemePopup() {
        themePopup.removeAllItems()

        let manager = ThemeColorManager.shared

        // デフォルトテーマを追加
        for theme in manager.defaultThemes {
            themePopup.addItem(withTitle: theme.themeName)
        }

        // ユーザーテーマを追加
        for theme in manager.userThemes {
            themePopup.addItem(withTitle: theme.themeName)
        }

        themePopup.selectItem(at: 0)
    }

    // MARK: - Public Methods

    /// シートとして表示
    func beginSheet(
        for window: NSWindow,
        currentColors: NewDocData.FontAndColorsData.Colors,
        completionHandler: @escaping (Bool) -> Void
    ) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler
        self.currentColors = currentColors

        // テーマポップアップを更新
        setupThemePopup()

        // 現在の色をカラーウェルに設定
        characterColorWell.color = currentColors.character.nsColor
        backgroundColorWell.color = currentColors.background.nsColor
        invisiblesColorWell.color = currentColors.invisible.nsColor
        caretColorWell.color = currentColors.caret.nsColor
        highlightColorWell.color = currentColors.highlight.nsColor
        lineNumberColorWell.color = currentColors.lineNumber.nsColor
        headerColorWell.color = currentColors.header.nsColor
        footerColorWell.color = currentColors.footer.nsColor
        lineNumberBackgroundColorWell.color = currentColors.lineNumberBackground.nsColor

        // パネルを親ウィンドウの中央に配置
        let windowFrame = window.frame
        let panelFrame = self.frame
        let x = windowFrame.origin.x + (windowFrame.width - panelFrame.width) / 2
        let y = windowFrame.origin.y + (windowFrame.height - panelFrame.height) / 2
        self.setFrameOrigin(NSPoint(x: x, y: y))

        window.beginSheet(self) { _ in }
    }

    /// 選択されたテーマを取得
    func selectedTheme() -> ThemeColorData? {
        let index = themePopup.indexOfSelectedItem
        return ThemeColorManager.shared.theme(at: index)
    }

    /// 各カラーウェルの色を取得
    func colorWellColors() -> (character: NSColor, background: NSColor, invisibles: NSColor, caret: NSColor, highlight: NSColor, lineNumber: NSColor, header: NSColor, footer: NSColor, lineNumberBackground: NSColor) {
        return (
            character: characterColorWell.color,
            background: backgroundColorWell.color,
            invisibles: invisiblesColorWell.color,
            caret: caretColorWell.color,
            highlight: highlightColorWell.color,
            lineNumber: lineNumberColorWell.color,
            header: headerColorWell.color,
            footer: footerColorWell.color,
            lineNumberBackground: lineNumberBackgroundColorWell.color
        )
    }

    // MARK: - Actions

    @IBAction func cancelClicked(_ sender: Any) {
        endSheet(accepted: false)
    }

    @IBAction func setClicked(_ sender: Any) {
        endSheet(accepted: true)
    }

    private func endSheet(accepted: Bool) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(accepted)
    }
}
