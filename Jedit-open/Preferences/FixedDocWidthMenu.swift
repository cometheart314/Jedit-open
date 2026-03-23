//
//  FixedDocWidthMenu.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/16.
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

/// Document Width メニュー選択を通知するプロトコル
protocol FixedDocWidthMenuDelegate: AnyObject {
    func fixedDocWidthMenuDidSelectType(_ type: NewDocData.ViewData.DocWidthType)
    func fixedDocWidthMenuDidChangeFixedWidth(_ width: Int)
    func fixedDocWidthMenuGetCurrentFixedWidth() -> Int
}

/// 動的に Document Width メニュー項目を生成するNSMenuサブクラス
class FixedDocWidthMenu: NSMenu, NSMenuDelegate {

    // MARK: - Properties

    weak var fixedDocWidthMenuDelegate: FixedDocWidthMenuDelegate?
    private weak var parentView: NSView?
    private var fixedDocWidthPanel: FixedDocWidthPanel?

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()
        self.delegate = self
    }

    /// 親ビューを設定（シートパネル表示用）
    func setParentView(_ view: NSView) {
        self.parentView = view
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Follows Paper Width (tag=0)
        let paperWidthItem = menu.addItem(
            withTitle: "Follows Paper Width".localized,
            action: #selector(docWidthSelected(_:)),
            keyEquivalent: ""
        )
        paperWidthItem.target = self
        paperWidthItem.tag = NewDocData.ViewData.DocWidthType.paperWidth.rawValue

        // Follows Window Width (tag=1)
        let windowWidthItem = menu.addItem(
            withTitle: "Follows Window Width".localized,
            action: #selector(docWidthSelected(_:)),
            keyEquivalent: ""
        )
        windowWidthItem.target = self
        windowWidthItem.tag = NewDocData.ViewData.DocWidthType.windowWidth.rawValue

        // Don't Wrap Line (tag=2)
        let noWrapItem = menu.addItem(
            withTitle: "Don't Wrap Line".localized,
            action: #selector(docWidthSelected(_:)),
            keyEquivalent: ""
        )
        noWrapItem.target = self
        noWrapItem.tag = NewDocData.ViewData.DocWidthType.noWrap.rawValue

        // Fixed Width ( xx chars.) (tag=3)
        let currentWidth = fixedDocWidthMenuDelegate?.fixedDocWidthMenuGetCurrentFixedWidth() ?? 80
        let fixedWidthTitle = String(format: "Fixed Width ( %d chars.)".localized, currentWidth)
        let fixedWidthItem = menu.addItem(
            withTitle: fixedWidthTitle,
            action: #selector(docWidthSelected(_:)),
            keyEquivalent: ""
        )
        fixedWidthItem.target = self
        fixedWidthItem.tag = NewDocData.ViewData.DocWidthType.fixedWidth.rawValue

        // セパレータ
        menu.addItem(NSMenuItem.separator())

        // Fixed Width Panel... (tag=9)
        let panelItem = menu.addItem(
            withTitle: "Fixed Width Panel...".localized,
            action: #selector(showFixedDocWidthPanel(_:)),
            keyEquivalent: ""
        )
        panelItem.target = self
        panelItem.tag = 9
    }

    // MARK: - Actions

    @objc private func docWidthSelected(_ sender: NSMenuItem) {
        guard let type = NewDocData.ViewData.DocWidthType(rawValue: sender.tag) else { return }
        fixedDocWidthMenuDelegate?.fixedDocWidthMenuDidSelectType(type)
    }

    @objc private func showFixedDocWidthPanel(_ sender: Any) {
        guard let parentView = parentView,
              let window = parentView.window else {
            NSSound.beep()
            return
        }

        if fixedDocWidthPanel == nil {
            fixedDocWidthPanel = FixedDocWidthPanel()
        }

        let currentWidth = fixedDocWidthMenuDelegate?.fixedDocWidthMenuGetCurrentFixedWidth() ?? 80

        fixedDocWidthPanel?.beginSheet(for: window, currentWidth: currentWidth) { [weak self] newWidth in
            if let newWidth = newWidth {
                self?.fixedDocWidthMenuDelegate?.fixedDocWidthMenuDidChangeFixedWidth(newWidth)
                // Fixed Widthタイプも選択
                self?.fixedDocWidthMenuDelegate?.fixedDocWidthMenuDidSelectType(.fixedWidth)
            }
        }
    }
}
