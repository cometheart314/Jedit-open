//
//  StyleMenuManager.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/26.
//

//
//  This file is part of Jedit-open.
//  Copyright (C) 2025 Satoshi Matsumoto
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
//

import Cocoa

class StyleMenuManager: NSObject {
    static let shared = StyleMenuManager()

    /// メインメニューの Styles サブメニューへの参照（ショートカットキー用に常に項目を保持）
    private weak var mainStylesMenu: NSMenu?

    private override init() {
        super.init()
        // スタイル変更の通知を監視してメニューを再構築
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stylesDidChange(_:)),
            name: .textStylesDidChange,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func stylesDidChange(_ notification: Notification) {
        // メインメニューのスタイル項目を即時再構築（ショートカットキーを常に有効にするため）
        if let menu = mainStylesMenu {
            buildStyleMenuItems(in: menu)
        }
    }

    // MARK: - Setup

    /// Format メニューの Text サブメニューの後に Styles サブメニューを挿入
    func setupStylesMenu() {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = (mainMenu.item(withTitle: "Format") ?? mainMenu.item(withTitle: "フォーマット"))?.submenu else {
            return
        }

        // "Text" サブメニューの位置を見つける
        var insertIndex = -1
        for (index, item) in formatMenu.items.enumerated() {
            if item.title == "Text" || item.title == "テキスト" {
                insertIndex = index + 1
                break
            }
        }

        // "Text" が見つからない場合は "Font" の後に挿入
        if insertIndex < 0 {
            for (index, item) in formatMenu.items.enumerated() {
                if item.title == "Font" || item.title == "フォント" {
                    insertIndex = index + 1
                    break
                }
            }
        }

        guard insertIndex >= 0 else { return }

        // Styles サブメニューを作成
        let stylesItem = NSMenuItem(title: "Styles".localized, action: nil, keyEquivalent: "")
        stylesItem.image = NSImage(systemSymbolName: "jacket", accessibilityDescription: nil)
        let stylesMenu = NSMenu(title: "Styles".localized)
        stylesMenu.delegate = self
        stylesItem.submenu = stylesMenu

        // ショートカットキーが常に機能するよう、即時にメニュー項目を構築
        buildStyleMenuItems(in: stylesMenu)
        mainStylesMenu = stylesMenu

        formatMenu.insertItem(stylesItem, at: insertIndex)

        // Styles の直後に Style Info… メニュー項目を挿入
        let styleInfoItem = NSMenuItem(
            title: "Style Info…".localized,
            action: #selector(AppDelegate.showStyleInfoPanel(_:)),
            keyEquivalent: ""
        )
        styleInfoItem.image = NSImage(systemSymbolName: "info.circle.text.page", accessibilityDescription: nil)
        formatMenu.insertItem(styleInfoItem, at: insertIndex + 1)
    }

    // MARK: - Menu Building

    /// スタイルメニューを構築（メイン・コンテキスト兼用）
    func buildStyleMenuItems(in menu: NSMenu) {
        menu.removeAllItems()

        let styles = StyleManager.shared.styles
        for style in styles {
            let item = NSMenuItem(
                title: style.displayName,
                action: #selector(JeditTextView.applyTextStyle(_:)),
                keyEquivalent: style.keyEquivalent ?? ""
            )
            if let key = style.keyEquivalent, !key.isEmpty {
                item.keyEquivalentModifierMask = style.keyEquivalentModifierMask
            }
            item.representedObject = style
            menu.addItem(item)
        }

        menu.addItem(.separator())

        // Edit Styles... 項目
        let editItem = NSMenuItem(
            title: "Edit Styles…".localized,
            action: #selector(AppDelegate.showStylesPreferences(_:)),
            keyEquivalent: ""
        )
        menu.addItem(editItem)
    }

    /// コンテキストメニュー用の Styles サブメニューを作成して返す
    func createContextStylesMenuItem() -> NSMenuItem {
        let stylesItem = NSMenuItem(title: "Styles".localized, action: nil, keyEquivalent: "")
        stylesItem.image = NSImage(systemSymbolName: "jacket", accessibilityDescription: nil)
        let stylesMenu = NSMenu(title: "Styles".localized)
        buildStyleMenuItems(in: stylesMenu)
        stylesItem.submenu = stylesMenu
        return stylesItem
    }
}

// MARK: - NSMenuDelegate

extension StyleMenuManager: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        buildStyleMenuItems(in: menu)
    }
}
