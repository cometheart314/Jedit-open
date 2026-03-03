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

    private var completionHandler: ((NewDocData.FontAndColorsData.Colors?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

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

        // 最初に"Theme"タイトルを追加（未選択状態を示す）
        themePopup.addItem(withTitle: "Theme".localized)

        let manager = ThemeColorManager.shared

        // デフォルトテーマを追加
        for theme in manager.defaultThemes {
            themePopup.addItem(withTitle: theme.themeName)
        }

        // ユーザーテーマを追加
        for theme in manager.userThemes {
            themePopup.addItem(withTitle: theme.themeName)
        }

        // "Theme"を選択状態にする
        themePopup.selectItem(at: 0)

        // ポップアップのアクションを設定
        themePopup.target = self
        themePopup.action = #selector(themePopupChanged(_:))
    }

    // MARK: - Public Methods

    /// シートとして表示
    /// - Parameters:
    ///   - window: 親ウィンドウ
    ///   - currentColors: 現在の色設定
    ///   - completionHandler: 完了時のコールバック（Setの場合は新しい色、Cancelの場合はnil）
    func beginSheet(
        for window: NSWindow,
        currentColors: NewDocData.FontAndColorsData.Colors,
        completionHandler: @escaping (NewDocData.FontAndColorsData.Colors?) -> Void
    ) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler

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

    /// 選択されたテーマを取得（インデックス0は"Theme"タイトルなので除外）
    func selectedTheme() -> ThemeColorData? {
        let index = themePopup.indexOfSelectedItem
        // インデックス0は"Theme"タイトルなので、実際のテーマはindex-1
        guard index > 0 else { return nil }
        return ThemeColorManager.shared.theme(at: index - 1)
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
        endSheet(colors: nil)
    }

    @IBAction func setClicked(_ sender: Any) {
        // 現在のカラーウェルの状態からColorsを作成
        let colors = NewDocData.FontAndColorsData.Colors(
            character: CodableColor(characterColorWell.color),
            background: CodableColor(backgroundColorWell.color),
            invisible: CodableColor(invisiblesColorWell.color),
            caret: CodableColor(caretColorWell.color),
            highlight: CodableColor(highlightColorWell.color),
            lineNumber: CodableColor(lineNumberColorWell.color),
            lineNumberBackground: CodableColor(lineNumberBackgroundColorWell.color),
            header: CodableColor(headerColorWell.color),
            footer: CodableColor(footerColorWell.color)
        )
        endSheet(colors: colors)
    }

    @IBAction func themePopupChanged(_ sender: Any) {
        // テーマが選択されたら、その色をカラーウェルに設定
        guard let theme = selectedTheme() else { return }

        characterColorWell.color = theme.characterColor.nsColor
        backgroundColorWell.color = theme.backgroundColor.nsColor
        invisiblesColorWell.color = theme.invisibleColor.nsColor
        caretColorWell.color = theme.caretColor.nsColor
        highlightColorWell.color = theme.highlightColor.nsColor
        lineNumberColorWell.color = theme.lineNumberColor.nsColor
        headerColorWell.color = theme.headerColor.nsColor
        footerColorWell.color = theme.footerColor.nsColor
        lineNumberBackgroundColorWell.color = theme.lineNumberBackColor.nsColor
    }

    private func endSheet(colors: NewDocData.FontAndColorsData.Colors?) {
        // カラーパネルを閉じる
        if NSColorPanel.shared.isVisible {
            NSColorPanel.shared.orderOut(nil)
        }

        // シートを閉じる
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(colors)
    }
}
