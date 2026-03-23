//
//  PrintPanelAccessoryController.swift
//  Jedit-open
//
//  印刷パネルのアクセサリビューコントローラ
//  行番号、カラー、ヘッダー/フッター、不可視文字の印刷オプションを提供する
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

/// 印刷パネルのアクセサリビューコントローラ
class PrintPanelAccessoryController: NSViewController, NSPrintPanelAccessorizing {

    // MARK: - IBOutlets

    @IBOutlet weak var lineNumberPopup: NSPopUpButton!
    @IBOutlet weak var colorPopup: NSPopUpButton!
    @IBOutlet weak var printHeaderCheckbox: NSButton!
    @IBOutlet weak var printFooterCheckbox: NSButton!
    @IBOutlet weak var printInvisiblesCheckbox: NSButton!

    // MARK: - KVO-observable Properties（プレビュー更新用）

    /// 行番号オプション（0: Same as Editing Window, 1: Print Line Numbers, 2: Don't Print Line Numbers）
    @objc dynamic var lineNumberOption: Int = 0 {
        didSet { notifyPrintPageViewNeedsDisplay() }
    }

    /// カラーオプション（0: Same as Editing Window, 1: Don't Print Background Color, 2: Black Chars and White Back）
    @objc dynamic var colorOption: Int = 0 {
        didSet { notifyPrintPageViewNeedsDisplay() }
    }

    /// ヘッダーを印刷する
    @objc dynamic var printHeader: Bool = true {
        didSet { notifyPrintPageViewNeedsDisplay() }
    }

    /// フッターを印刷する
    @objc dynamic var printFooter: Bool = true {
        didSet { notifyPrintPageViewNeedsDisplay() }
    }

    /// 不可視文字を印刷する
    @objc dynamic var printInvisibles: Bool = false {
        didSet {
            printPageView?.updateInvisibleCharacterDisplay()
            notifyPrintPageViewNeedsDisplay()
        }
    }

    // MARK: - PrintPageView Reference

    /// 印刷ビューへの弱参照（プレビュー更新用）
    weak var printPageView: PrintPageView?

    // MARK: - NSPrintPanelAccessorizing

    func localizedSummaryItems() -> [[NSPrintPanel.AccessorySummaryKey: String]] {
        var items: [[NSPrintPanel.AccessorySummaryKey: String]] = []

        let lineNumberDesc: String
        switch lineNumberOption {
        case 1: lineNumberDesc = "Print Line Numbers"
        case 2: lineNumberDesc = "Don't Print Line Numbers"
        default: lineNumberDesc = "Same as Editing Window"
        }
        items.append([.itemName: "Line Numbers", .itemDescription: lineNumberDesc])

        let colorDesc: String
        switch colorOption {
        case 1: colorDesc = "Don't Print Background Color"
        case 2: colorDesc = "Black Chars and White Back"
        default: colorDesc = "Same as Editing Window"
        }
        items.append([.itemName: "Colors", .itemDescription: colorDesc])

        items.append([.itemName: "Header", .itemDescription: printHeader ? "On" : "Off"])
        items.append([.itemName: "Footer", .itemDescription: printFooter ? "On" : "Off"])
        items.append([.itemName: "Invisibles", .itemDescription: printInvisibles ? "On" : "Off"])

        return items
    }

    func keyPathsForValuesAffectingPreview() -> Set<String> {
        return ["lineNumberOption", "colorOption", "printHeader", "printFooter", "printInvisibles"]
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        syncUIWithProperties()
    }

    // MARK: - IBActions

    @IBAction func lineNumberPopupChanged(_ sender: NSPopUpButton) {
        lineNumberOption = sender.indexOfSelectedItem
    }

    @IBAction func colorPopupChanged(_ sender: NSPopUpButton) {
        colorOption = sender.indexOfSelectedItem
    }

    @IBAction func printHeaderChanged(_ sender: NSButton) {
        printHeader = (sender.state == .on)
    }

    @IBAction func printFooterChanged(_ sender: NSButton) {
        printFooter = (sender.state == .on)
    }

    @IBAction func printInvisiblesChanged(_ sender: NSButton) {
        printInvisibles = (sender.state == .on)
    }

    // MARK: - Configuration

    /// 保存された印刷オプションとウィンドウ状態から初期値を設定
    /// - Parameters:
    ///   - printOptions: 保存された印刷オプション（nilの場合はデフォルト）
    ///   - hasHeader: エディタウィンドウにヘッダーがあるか
    ///   - hasFooter: エディタウィンドウにフッターがあるか
    ///   - hasInvisibles: エディタウィンドウで不可視文字が表示されているか
    func configureDefaults(from printOptions: NewDocData.PrintOptionsData?, hasHeader: Bool, hasFooter: Bool, hasInvisibles: Bool) {
        if let options = printOptions {
            // 保存された設定を復元
            lineNumberOption = options.lineNumberOption
            colorOption = options.colorOption
            printHeader = options.printHeader
            printFooter = options.printFooter
            printInvisibles = options.printInvisibles
        } else {
            // デフォルト設定
            lineNumberOption = 0  // Same as Editing Window
            colorOption = 0       // Same as Editing Window
            printHeader = hasHeader
            printFooter = hasFooter
            printInvisibles = hasInvisibles
        }

        if isViewLoaded {
            syncUIWithProperties()
        }
    }

    /// 現在の設定をPrintOptionsDataに変換
    func toPrintOptionsData() -> NewDocData.PrintOptionsData {
        return NewDocData.PrintOptionsData(
            lineNumberOption: lineNumberOption,
            colorOption: colorOption,
            printHeader: printHeader,
            printFooter: printFooter,
            printInvisibles: printInvisibles
        )
    }

    // MARK: - Private

    /// UIコントロールをプロパティ値と同期
    private func syncUIWithProperties() {
        lineNumberPopup?.selectItem(at: lineNumberOption)
        colorPopup?.selectItem(at: colorOption)
        printHeaderCheckbox?.state = printHeader ? .on : .off
        printFooterCheckbox?.state = printFooter ? .on : .off
        printInvisiblesCheckbox?.state = printInvisibles ? .on : .off
    }

    /// 印刷ビューの再描画を要求
    private func notifyPrintPageViewNeedsDisplay() {
        guard let view = printPageView else { return }
        view.needsDisplay = true
    }
}
