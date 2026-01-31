//
//  JOThemeColorPopupButton.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/19.
//

import Cocoa

/// テーマカラーを表すディクショナリのキー
struct ThemeColorKeys {
    static let themeName = "themeName"
    static let removable = "removable"
    static let characterColor = "characterColor"
    static let backgroundColor = "backgroundColor"
    static let invisibleColor = "invisibleColor"
    static let caretColor = "caretColor"
    static let highlightColor = "highlightColor"
    static let lineNumberColor = "lineNumberColor"
    static let lineNumberBackColor = "lineNumberBackColor"
    static let headerColor = "headerColor"
    static let footerColor = "footerColor"
}

/// テーマカラーデータ
struct ThemeColorData: Codable {
    var themeName: String
    var removable: Bool
    var characterColor: CodableColor
    var backgroundColor: CodableColor
    var invisibleColor: CodableColor
    var caretColor: CodableColor
    var highlightColor: CodableColor
    var lineNumberColor: CodableColor
    var lineNumberBackColor: CodableColor
    var headerColor: CodableColor
    var footerColor: CodableColor

    /// Dynamicテーマ（システムカラーを使用、ライト/ダークモードに自動対応）
    static var dynamic: ThemeColorData {
        ThemeColorData(
            themeName: NSLocalizedString("Dynamic", comment: ""),
            removable: false,
            characterColor: CodableColor(NSColor.textColor),
            backgroundColor: CodableColor(NSColor.textBackgroundColor),
            invisibleColor: CodableColor(NSColor.tertiaryLabelColor),
            caretColor: CodableColor(NSColor.textColor),
            highlightColor: CodableColor(NSColor.selectedTextBackgroundColor),
            lineNumberColor: CodableColor(NSColor.secondaryLabelColor),
            lineNumberBackColor: CodableColor(NSColor.controlBackgroundColor),
            headerColor: CodableColor(NSColor.labelColor),
            footerColor: CodableColor(NSColor.labelColor)
        )
    }

    /// Lightテーマ（固定の明るい色）
    static var light: ThemeColorData {
        ThemeColorData(
            themeName: NSLocalizedString("Light", comment: ""),
            removable: false,
            characterColor: CodableColor(NSColor.black),
            backgroundColor: CodableColor(NSColor.white),
            invisibleColor: CodableColor(NSColor(white: 0.7, alpha: 1.0)),
            caretColor: CodableColor(NSColor.black),
            highlightColor: CodableColor(NSColor(red: 0.7, green: 0.85, blue: 1.0, alpha: 1.0)),
            lineNumberColor: CodableColor(NSColor(white: 0.5, alpha: 1.0)),
            lineNumberBackColor: CodableColor(NSColor(white: 0.95, alpha: 1.0)),
            headerColor: CodableColor(NSColor.black),
            footerColor: CodableColor(NSColor.black)
        )
    }

    /// Darkテーマ（固定の暗い色）
    static var dark: ThemeColorData {
        ThemeColorData(
            themeName: NSLocalizedString("Dark", comment: ""),
            removable: false,
            characterColor: CodableColor(NSColor.white),
            backgroundColor: CodableColor(NSColor(white: 0.15, alpha: 1.0)),
            invisibleColor: CodableColor(NSColor(white: 0.5, alpha: 1.0)),
            caretColor: CodableColor(NSColor.white),
            highlightColor: CodableColor(NSColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1.0)),
            lineNumberColor: CodableColor(NSColor(white: 0.6, alpha: 1.0)),
            lineNumberBackColor: CodableColor(NSColor(white: 0.12, alpha: 1.0)),
            headerColor: CodableColor(NSColor(white: 0.9, alpha: 1.0)),
            footerColor: CodableColor(NSColor(white: 0.9, alpha: 1.0))
        )
    }
}

/// テーマカラーマネージャー
class ThemeColorManager {
    static let shared = ThemeColorManager()

    private let userThemeKey = "userThemeArray"

    /// デフォルトテーマの配列
    private(set) var defaultThemes: [ThemeColorData] = []

    /// ユーザー定義テーマの配列
    private(set) var userThemes: [ThemeColorData] = []

    private init() {
        setupDefaultThemes()
        loadUserThemes()
    }

    /// デフォルトテーマを設定
    private func setupDefaultThemes() {
        defaultThemes = [
            .dynamic,
            .light,
            .dark
        ]
    }

    /// ユーザーテーマを読み込み
    private func loadUserThemes() {
        guard let data = UserDefaults.standard.data(forKey: userThemeKey) else { return }
        do {
            userThemes = try JSONDecoder().decode([ThemeColorData].self, from: data)
        } catch {
            print("Failed to load user themes: \(error)")
        }
    }

    /// ユーザーテーマを保存
    private func saveUserThemes() {
        do {
            let data = try JSONEncoder().encode(userThemes)
            UserDefaults.standard.set(data, forKey: userThemeKey)
        } catch {
            print("Failed to save user themes: \(error)")
        }
    }

    /// すべてのテーマを取得
    var allThemes: [ThemeColorData] {
        return defaultThemes + userThemes
    }

    /// テーマを追加
    func addTheme(_ theme: ThemeColorData) {
        var newTheme = theme
        newTheme.removable = true
        userThemes.append(newTheme)
        saveUserThemes()
    }

    /// テーマを削除
    func removeTheme(at index: Int) {
        let defaultCount = defaultThemes.count
        guard index >= defaultCount else { return } // デフォルトテーマは削除不可
        let userIndex = index - defaultCount
        guard userIndex < userThemes.count else { return }
        userThemes.remove(at: userIndex)
        saveUserThemes()
    }

    /// インデックスでテーマを取得
    func theme(at index: Int) -> ThemeColorData? {
        let allThemes = self.allThemes
        guard index >= 0, index < allThemes.count else { return nil }
        return allThemes[index]
    }
}

/// テーマカラー選択用のポップアップボタン
class JOThemeColorPopupButton: NSPopUpButton, NSMenuDelegate {

    override func awakeFromNib() {
        super.awakeFromNib()
        menu?.delegate = self
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        // 最初のアイテム（タイトル）以外を削除
        while menu.numberOfItems > 1 {
            menu.removeItem(at: 1)
        }

        let manager = ThemeColorManager.shared

        // デフォルトテーマを追加
        for theme in manager.defaultThemes {
            let item = NSMenuItem(title: theme.themeName, action: #selector(themeSelected(_:)), keyEquivalent: "")
            item.representedObject = theme
            item.target = self.target
            menu.addItem(item)
        }

        // ユーザーテーマを追加
        for theme in manager.userThemes {
            let item = NSMenuItem(title: theme.themeName, action: #selector(themeSelected(_:)), keyEquivalent: "")
            item.representedObject = theme
            item.target = self.target
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        // テーマ追加メニュー
        let addItem = NSMenuItem(title: NSLocalizedString("Add Theme...", comment: ""), action: #selector(addTheme(_:)), keyEquivalent: "")
        addItem.target = self.target
        menu.addItem(addItem)

        // テーマ削除サブメニュー
        if !manager.userThemes.isEmpty {
            let removeItem = NSMenuItem(title: NSLocalizedString("Remove Theme", comment: ""), action: nil, keyEquivalent: "")
            let removeSubmenu = NSMenu()

            for (index, theme) in manager.userThemes.enumerated() {
                let subItem = NSMenuItem(title: theme.themeName, action: #selector(removeThemeSelected(_:)), keyEquivalent: "")
                subItem.tag = index
                subItem.target = self
                removeSubmenu.addItem(subItem)
            }

            removeItem.submenu = removeSubmenu
            menu.addItem(removeItem)
        }
    }

    @objc func themeSelected(_ sender: NSMenuItem) {
        // ViewControllerで処理
    }

    @objc func addTheme(_ sender: NSMenuItem) {
        // ViewControllerで処理
    }

    /// ユーザーテーマを削除
    @objc func removeThemeSelected(_ sender: NSMenuItem) {
        let index = sender.tag
        let manager = ThemeColorManager.shared

        guard index >= 0, index < manager.userThemes.count else { return }

        let themeName = manager.userThemes[index].themeName

        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Remove Theme", comment: "")
        alert.informativeText = String(format: NSLocalizedString("Are you sure you want to remove \"%@\"?", comment: ""), themeName)
        alert.addButton(withTitle: NSLocalizedString("Remove", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
        alert.alertStyle = .warning

        if let window = self.window {
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    // デフォルトテーマ数 + ユーザーテーマのインデックス
                    let actualIndex = manager.defaultThemes.count + index
                    manager.removeTheme(at: actualIndex)
                }
            }
        } else {
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let actualIndex = manager.defaultThemes.count + index
                manager.removeTheme(at: actualIndex)
            }
        }
    }
}
