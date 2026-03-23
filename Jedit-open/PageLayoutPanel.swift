//
//  PageLayoutPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/03.
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

/// ページレイアウト設定パネル（ヘッダー・フッター、マージン設定）
class PageLayoutPanel: NSWindow {

    // MARK: - IBOutlets

    // Paper Margin
    @IBOutlet var leftMarginField: NSTextField!
    @IBOutlet var rightMarginField: NSTextField!
    @IBOutlet var topMarginField: NSTextField!
    @IBOutlet var bottomMarginField: NSTextField!
    @IBOutlet var marginUnitPopup: NSPopUpButton!

    // Header
    @IBOutlet var headerTextView: NSTextView!
    @IBOutlet var headerInsertVariablesPopup: NSPopUpButton!
    @IBOutlet var headerColorWell: NSColorWell!
    @IBOutlet var headerRulerCheckbox: NSButton!

    // Footer
    @IBOutlet var footerTextView: NSTextView!
    @IBOutlet var footerInsertVariablesPopup: NSPopUpButton!
    @IBOutlet var footerColorWell: NSColorWell!
    @IBOutlet var footerRulerCheckbox: NSButton!

    // Buttons
    @IBOutlet var revertToDefaultsButton: NSButton!
    @IBOutlet var setButton: NSButton!

    // MARK: - Properties

    private weak var targetDocument: NSDocument?

    // Unit conversion constants
    private let pointsPerCm: CGFloat = 28.3465
    private let pointsPerInch: CGFloat = 72.0

    // MARK: - Initialization

    /// XIBからパネルをロードして返す
    static func loadFromNib() -> PageLayoutPanel? {
        var topLevelObjects: NSArray?
        let bundle = Bundle.main
        let nibName = "PageLayoutPanel"

        guard bundle.loadNibNamed(nibName, owner: nil, topLevelObjects: &topLevelObjects) else {
            print("Failed to load \(nibName).xib")
            return nil
        }

        // NSWindowを探す
        for object in topLevelObjects ?? [] {
            if let panel = object as? PageLayoutPanel {
                return panel
            }
        }

        return nil
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        self.isReleasedWhenClosed = false

        // Insert Variablesポップアップのアクションを設定
        headerInsertVariablesPopup?.target = self
        headerInsertVariablesPopup?.action = #selector(insertHeaderVariable(_:))
        footerInsertVariablesPopup?.target = self
        footerInsertVariablesPopup?.action = #selector(insertFooterVariable(_:))

        // ユニットポップアップのアクションを設定
        marginUnitPopup?.target = self
        marginUnitPopup?.action = #selector(marginUnitChanged(_:))

        // チェックボックスのアクションを設定（ルーラー表示用）
        headerRulerCheckbox?.target = self
        headerRulerCheckbox?.action = #selector(headerRulerChanged(_:))
        footerRulerCheckbox?.target = self
        footerRulerCheckbox?.action = #selector(footerRulerChanged(_:))

        // Revert to Defaultsボタンのアクションを設定
        revertToDefaultsButton?.target = self
        revertToDefaultsButton?.action = #selector(revertToDefaults(_:))

        // Setボタンのアクションを設定
        setButton?.target = self
        setButton?.action = #selector(setClicked(_:))

        // TextViewのルーラー使用を有効化
        headerTextView?.usesRuler = true
        footerTextView?.usesRuler = true
    }

    // MARK: - Public Methods

    /// ドキュメントに対してパネルを表示
    func showPanel(for document: NSDocument) {
        self.targetDocument = document

        // 現在の設定を読み込んでUIに反映
        loadCurrentSettings()

        // パネルを表示
        self.makeKeyAndOrderFront(nil)
    }

    // MARK: - Private Methods

    /// ターゲットドキュメントをDocumentとして取得
    private var document: Document? {
        return targetDocument as? Document
    }

    private func loadCurrentSettings() {
        guard let document = document else { return }

        // マージン設定を読み込み
        let printInfo = document.printInfo
        let unit = marginUnitPopup?.indexOfSelectedItem ?? 0

        leftMarginField?.doubleValue = convertFromPoints(printInfo.leftMargin, toUnit: unit)
        rightMarginField?.doubleValue = convertFromPoints(printInfo.rightMargin, toUnit: unit)
        topMarginField?.doubleValue = convertFromPoints(printInfo.topMargin, toUnit: unit)
        bottomMarginField?.doubleValue = convertFromPoints(printInfo.bottomMargin, toUnit: unit)

        // presetDataからヘッダー・フッター設定を読み込み
        if let headerFooter = document.presetData?.headerFooter {
            // ヘッダー
            let headerAttrString = NewDocData.HeaderFooterData.attributedString(from: headerFooter.headerRTFData)
            headerTextView?.textStorage?.setAttributedString(headerAttrString)

            // フッター
            let footerAttrString = NewDocData.HeaderFooterData.attributedString(from: headerFooter.footerRTFData)
            footerTextView?.textStorage?.setAttributedString(footerAttrString)
        }

        // カラー設定
        if let colors = document.presetData?.fontAndColors.colors {
            headerColorWell?.color = colors.header.nsColor
            footerColorWell?.color = colors.footer.nsColor
        }

        // ルーラー表示状態を初期化
        updateRulerVisibility()
    }

    private func updateRulerVisibility() {
        // ヘッダーTextViewのルーラー表示
        let showHeaderRuler = headerRulerCheckbox?.state == .on
        headerTextView?.isRulerVisible = showHeaderRuler

        // フッターTextViewのルーラー表示
        let showFooterRuler = footerRulerCheckbox?.state == .on
        footerTextView?.isRulerVisible = showFooterRuler
    }

    private func convertFromPoints(_ points: CGFloat, toUnit unit: Int) -> Double {
        switch unit {
        case 0: // cm
            return Double(points / pointsPerCm)
        case 1: // inches
            return Double(points / pointsPerInch)
        case 2: // points
            return Double(points)
        default:
            return Double(points / pointsPerCm)
        }
    }

    private func convertToPoints(_ value: Double, fromUnit unit: Int) -> CGFloat {
        switch unit {
        case 0: // cm
            return CGFloat(value) * pointsPerCm
        case 1: // inches
            return CGFloat(value) * pointsPerInch
        case 2: // points
            return CGFloat(value)
        default:
            return CGFloat(value) * pointsPerCm
        }
    }

    private func insertVariable(_ tag: Int, into textView: NSTextView?) {
        guard let textView = textView else { return }

        let variable: String
        switch tag {
        case 1: variable = "%page" // Page Number
        case 2: variable = "%total" // Page Total
        case 3: variable = "%date" // Current Date
        case 4: variable = "%time" // Current Time
        case 5: variable = "%name" // Document Title
        case 6: variable = "%path" // File Path
        case 7: variable = "%user" // User Name
        case 8: variable = "%moddate" // Modification Date
        case 9: variable = "%modtime" // Modification Time
        case 10: variable = "%author" // Author
        case 11: variable = "%company" // Company
        case 12: variable = "%copyright" // Copyright
        case 13: variable = "%title" // Title
        case 14: variable = "%subject" // Subject
        case 15: variable = "%keywords" // Keywords
        case 16: variable = "%comment" // Comment
        default: return
        }

        textView.insertText(variable, replacementRange: textView.selectedRange())
    }

    // MARK: - Actions

    @objc private func marginUnitChanged(_ sender: NSPopUpButton) {
        // ユニット変更時に現在のポイント値を新しい単位で再表示
        guard let document = document else { return }

        let printInfo = document.printInfo
        let unit = sender.indexOfSelectedItem

        leftMarginField?.doubleValue = convertFromPoints(printInfo.leftMargin, toUnit: unit)
        rightMarginField?.doubleValue = convertFromPoints(printInfo.rightMargin, toUnit: unit)
        topMarginField?.doubleValue = convertFromPoints(printInfo.topMargin, toUnit: unit)
        bottomMarginField?.doubleValue = convertFromPoints(printInfo.bottomMargin, toUnit: unit)
    }

    @objc private func insertHeaderVariable(_ sender: NSPopUpButton) {
        let tag = sender.selectedItem?.tag ?? 0
        if tag > 0 {
            insertVariable(tag, into: headerTextView)
        }
        // ポップアップを最初の項目に戻す
        sender.selectItem(at: 0)
    }

    @objc private func insertFooterVariable(_ sender: NSPopUpButton) {
        let tag = sender.selectedItem?.tag ?? 0
        if tag > 0 {
            insertVariable(tag, into: footerTextView)
        }
        // ポップアップを最初の項目に戻す
        sender.selectItem(at: 0)
    }

    @objc private func headerRulerChanged(_ sender: NSButton) {
        // ヘッダーTextViewのルーラー表示を切り替え
        headerTextView?.isRulerVisible = (sender.state == .on)
    }

    @objc private func footerRulerChanged(_ sender: NSButton) {
        // フッターTextViewのルーラー表示を切り替え
        footerTextView?.isRulerVisible = (sender.state == .on)
    }

    @objc private func revertToDefaults(_ sender: NSButton) {
        // UIをデフォルト値に戻す（Documentには反映しない）
        _ = NSPrintInfo.shared
        let unit = marginUnitPopup?.indexOfSelectedItem ?? 0

        // デフォルトのマージン値をUIに設定
        let defaultLayout = NewDocData.PageLayoutData.default
        leftMarginField?.doubleValue = convertFromPoints(defaultLayout.leftMarginPoints, toUnit: unit)
        rightMarginField?.doubleValue = convertFromPoints(defaultLayout.rightMarginPoints, toUnit: unit)
        topMarginField?.doubleValue = convertFromPoints(defaultLayout.topMarginPoints, toUnit: unit)
        bottomMarginField?.doubleValue = convertFromPoints(defaultLayout.bottomMarginPoints, toUnit: unit)

        // デフォルトのヘッダー・フッターをUIに設定
        let defaultHeaderFooter = NewDocData.HeaderFooterData.default
        let headerAttrString = NewDocData.HeaderFooterData.attributedString(from: defaultHeaderFooter.headerRTFData)
        headerTextView?.textStorage?.setAttributedString(headerAttrString)
        let footerAttrString = NewDocData.HeaderFooterData.attributedString(from: defaultHeaderFooter.footerRTFData)
        footerTextView?.textStorage?.setAttributedString(footerAttrString)

        // ルーラーをオンに
        headerRulerCheckbox?.state = .on
        footerRulerCheckbox?.state = .on
        updateRulerVisibility()
    }

    /// Setボタンが押されたときにDocumentに設定を反映
    @IBAction func setClicked(_ sender: Any) {
        guard let document = document else { return }

        let unit = marginUnitPopup?.indexOfSelectedItem ?? 0

        // マージン設定をDocumentに反映
        let leftPoints = convertToPoints(leftMarginField?.doubleValue ?? 0, fromUnit: unit)
        let rightPoints = convertToPoints(rightMarginField?.doubleValue ?? 0, fromUnit: unit)
        let topPoints = convertToPoints(topMarginField?.doubleValue ?? 0, fromUnit: unit)
        let bottomPoints = convertToPoints(bottomMarginField?.doubleValue ?? 0, fromUnit: unit)

        document.printInfo.leftMargin = leftPoints
        document.printInfo.rightMargin = rightPoints
        document.printInfo.topMargin = topPoints
        document.printInfo.bottomMargin = bottomPoints

        // presetDataのpageLayoutも更新
        document.presetData?.pageLayout.topMarginPoints = topPoints
        document.presetData?.pageLayout.leftMarginPoints = leftPoints
        document.presetData?.pageLayout.rightMarginPoints = rightPoints
        document.presetData?.pageLayout.bottomMarginPoints = bottomPoints

        // ヘッダー・フッターのテキストをDocumentに反映
        if let headerTextStorage = headerTextView?.textStorage,
           let footerTextStorage = footerTextView?.textStorage {
            let headerAttrString = NSAttributedString(attributedString: headerTextStorage)
            let footerAttrString = NSAttributedString(attributedString: footerTextStorage)

            document.presetData?.headerFooter.headerRTFData = NewDocData.HeaderFooterData.rtfData(from: headerAttrString)
            document.presetData?.headerFooter.footerRTFData = NewDocData.HeaderFooterData.rtfData(from: footerAttrString)
        }

        // カラー設定をDocumentに反映
        if let headerColor = headerColorWell?.color {
            document.presetData?.fontAndColors.colors.header = CodableColor(headerColor)
        }
        if let footerColor = footerColorWell?.color {
            document.presetData?.fontAndColors.colors.footer = CodableColor(footerColor)
        }

        // printInfoDidChangeを通知
        NotificationCenter.default.post(name: Document.printInfoDidChangeNotification, object: document)

        // パネルを閉じる
        self.orderOut(nil)
    }
}
