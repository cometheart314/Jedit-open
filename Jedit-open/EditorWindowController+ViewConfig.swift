//
//  EditorWindowController+ViewConfig.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
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

extension EditorWindowController {

    // MARK: - Line Number Actions

    @IBAction func toggleLineNumberMode(_ sender: Any?) {
        // モードを順番に切り替え: none -> paragraph -> row -> none
        switch lineNumberMode {
        case .none:
            lineNumberMode = .paragraph
        case .paragraph:
            lineNumberMode = .row
        case .row:
            lineNumberMode = .none
        }

        updateLineNumberDisplay()
    }

    @IBAction func hideLineNumbers(_ sender: Any?) {
        guard lineNumberMode != .none else { return }
        lineNumberMode = .none
        updateLineNumberDisplay()
    }

    @IBAction func showParagraphNumbers(_ sender: Any?) {
        guard lineNumberMode != .paragraph else { return }
        lineNumberMode = .paragraph
        updateLineNumberDisplay()
    }

    @IBAction func showRowNumbers(_ sender: Any?) {
        guard lineNumberMode != .row else { return }
        lineNumberMode = .row
        updateLineNumberDisplay()
    }

    internal func updateLineNumberDisplay() {
        switch displayMode {
        case .continuous:
            // scrollView1の行番号を更新
            if let scrollView = scrollView1,
               let textView = scrollView.documentView as? NSTextView {
                updateLineNumberView(for: scrollView, textView: textView, lineNumberViewRef: &lineNumberView1, constraintRef: &lineNumberWidthConstraint1)
            }

            // scrollView2の行番号を更新（splitViewが表示されている場合）
            if let scrollView = scrollView2,
               !scrollView.isHidden,
               let textView = scrollView.documentView as? NSTextView {
                updateLineNumberView(for: scrollView, textView: textView, lineNumberViewRef: &lineNumberView2, constraintRef: &lineNumberWidthConstraint2)
            }

        case .page:
            // ページモードではpagesViewの行番号モードを更新
            pagesView1?.lineNumberMode = lineNumberMode
            pagesView2?.lineNumberMode = lineNumberMode
        }

        // presetData に反映
        switch lineNumberMode {
        case .none:
            textDocument?.presetData?.view.lineNumberType = .none
        case .paragraph:
            textDocument?.presetData?.view.lineNumberType = .logical
        case .row:
            textDocument?.presetData?.view.lineNumberType = .physical
        }
        markDocumentAsEdited()
    }

    internal func updateLineNumberView(for scrollView: NSScrollView, textView: NSTextView, lineNumberViewRef: inout LineNumberView?, constraintRef: inout NSLayoutConstraint?) {
        if lineNumberMode != .none {
            if let existingView = lineNumberViewRef {
                // 既存の行番号ビューがある場合はモードを更新
                existingView.lineNumberMode = lineNumberMode
            } else {
                // 新しい行番号ビューを作成
                setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberViewRef, constraintRef: &constraintRef)
                lineNumberViewRef?.textView = textView
            }
        } else {
            // 行番号ビューを削除
            lineNumberViewRef?.removeFromSuperview()
            lineNumberViewRef = nil
            constraintRef = nil

            // ScrollViewの制約をリセット（親ビューいっぱいに広げる）
            if let parentView = scrollView.superview {
                // ScrollViewの既存の制約を削除
                let scrollViewConstraints = parentView.constraints.filter { constraint in
                    (constraint.firstItem as? NSView) === scrollView || (constraint.secondItem as? NSView) === scrollView
                }
                NSLayoutConstraint.deactivate(scrollViewConstraints)

                scrollView.translatesAutoresizingMaskIntoConstraints = false
                // 新しい制約を追加
                NSLayoutConstraint.activate([
                    scrollView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
                    scrollView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
                    scrollView.topAnchor.constraint(equalTo: parentView.topAnchor),
                    scrollView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor)
                ])
            }
        }
    }

    // MARK: - Ruler Actions

    @IBAction func showHideTextRuler(_ sender: Any?) {
        isRulerVisible = !isRulerVisible
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerHide(_ sender: Any?) {
        rulerType = .none
        isRulerVisible = false
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerPoints(_ sender: Any?) {
        rulerType = .point
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerCentimeters(_ sender: Any?) {
        rulerType = .centimeter
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerInches(_ sender: Any?) {
        rulerType = .inch
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    @IBAction func setRulerCharacters(_ sender: Any?) {
        rulerType = .character
        isRulerVisible = true
        updateRulerVisibility()
        updatePresetDataRulerType()
    }

    /// presetData のルーラータイプを更新
    internal func updatePresetDataRulerType() {
        if isRulerVisible {
            textDocument?.presetData?.view.rulerType = rulerType
        } else {
            textDocument?.presetData?.view.rulerType = .none
        }
        markDocumentAsEdited()
    }

    internal func updateRulerVisibility() {
        switch displayMode {
        case .continuous:
            updateContinuousModeRuler(scrollView: scrollView1, isFirstResponder: true)
            if let scrollView = scrollView2, !scrollView.isHidden {
                updateContinuousModeRuler(scrollView: scrollView, isFirstResponder: false)
            }
        case .page:
            updatePageModeRuler(scrollView: scrollView1, textViews: textViews1, isFirstResponder: true)
            if let scrollView = scrollView2, !scrollView.isHidden {
                updatePageModeRuler(scrollView: scrollView, textViews: textViews2, isFirstResponder: false)
            }
        }
    }

    /// 連続モードのルーラー設定
    internal func updateContinuousModeRuler(scrollView: NSScrollView?, isFirstResponder: Bool) {
        guard let scrollView = scrollView,
              let textView = scrollView.documentView as? NSTextView else { return }

        // ルーラーの種類を切り替え（縦書き/横書き対応）
        let needsHorizontalRuler = !isVerticalLayout
        let needsVerticalRuler = isVerticalLayout
        let currentRuler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
        let needsRulerSetup = scrollView.hasHorizontalRuler != needsHorizontalRuler ||
                              scrollView.hasVerticalRuler != needsVerticalRuler ||
                              !(currentRuler is LabeledRulerView)

        // ルーラーを一度非表示にしてから再表示することで、レイアウトを強制的に再計算
        scrollView.rulersVisible = false

        if needsRulerSetup {
            scrollView.hasHorizontalRuler = needsHorizontalRuler
            scrollView.hasVerticalRuler = needsVerticalRuler
            // カスタムルーラーを再設定
            setupLabeledRuler(for: scrollView)
        }

        // tileを呼んでレイアウトを更新
        scrollView.tile()

        // ScrollViewのルーラー表示状態を更新
        scrollView.rulersVisible = isRulerVisible
        textView.isRulerVisible = isRulerVisible
        textView.usesRuler = true

        if isRulerVisible {
            let ruler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
            if let ruler = ruler {
                ruler.originOffset = textDocument?.containerInset.width ?? 0
                ruler.clientView = textView
                // ルーラーの単位を設定
                configureRulerUnit(ruler)
                if isFirstResponder {
                    window?.makeFirstResponder(textView)
                }
                textView.updateRuler()

                // プレーンテキストの場合はルーラーのアクセサリビュー（段落スタイルコントロール）を非表示
                if textDocument?.documentType == .plain {
                    ruler.accessoryView = nil
                    ruler.reservedThicknessForAccessoryView = 0
                }
            }
        }
        updateTextViewSize(for: scrollView)
    }

    /// ページモードのルーラー設定
    internal func updatePageModeRuler(scrollView: NSScrollView?, textViews: [NSTextView], isFirstResponder: Bool) {
        guard let scrollView = scrollView else { return }

        // ルーラーの種類を切り替え
        scrollView.rulersVisible = false
        scrollView.hasHorizontalRuler = !isVerticalLayout
        scrollView.hasVerticalRuler = isVerticalLayout
        // カスタムルーラーを再設定
        setupLabeledRuler(for: scrollView)
        scrollView.tile()
        scrollView.rulersVisible = isRulerVisible

        // ルーラーの設定
        if let firstTextView = textViews.first {
            firstTextView.usesRuler = true
            firstTextView.isRulerVisible = isRulerVisible

            if isRulerVisible {
                let ruler = isVerticalLayout ? scrollView.verticalRulerView : scrollView.horizontalRulerView
                if let ruler = ruler {
                    ruler.clientView = firstTextView
                    // ページモードでは、ルーラーの0地点をテキストの開始位置に合わせる
                    // 縦書き: topMargin、横書き: leftMargin + lineFragmentPadding
                    let lineFragmentPadding = firstTextView.textContainer?.lineFragmentPadding ?? 5.0
                    let marginOffset = isVerticalLayout ? pageTopMargin : pageLeftMargin
                    ruler.originOffset = marginOffset + lineFragmentPadding
                    // ルーラーの単位を設定
                    configureRulerUnit(ruler)

                    // プレーンテキストの場合はルーラーのアクセサリビュー（段落スタイルコントロール）を非表示
                    if textDocument?.documentType == .plain {
                        ruler.accessoryView = nil
                        ruler.reservedThicknessForAccessoryView = 0
                    }
                }
                if isFirstResponder {
                    window?.makeFirstResponder(firstTextView)
                }
                firstTextView.updateRuler()
            }
        }

        // 他のテキストビューにも設定
        for textView in textViews.dropFirst() {
            textView.usesRuler = true
            textView.isRulerVisible = isRulerVisible
        }
    }

    /// ScrollViewにカスタムルーラーを設定
    internal func setupLabeledRuler(for scrollView: NSScrollView) {
        // 横ルーラーを設定
        if scrollView.hasHorizontalRuler {
            let horizontalRuler = LabeledRulerView(
                scrollView: scrollView,
                orientation: .horizontalRuler
            )
            // マーカーとアクセサリビュー用の予約スペースを0にして、
            // 縦ルーラーがある場合でもヘッダー領域を表示しない
            horizontalRuler.reservedThicknessForMarkers = 0
            horizontalRuler.reservedThicknessForAccessoryView = 0
            scrollView.horizontalRulerView = horizontalRuler
        } else {
            // 横ルーラーが不要な場合は明示的にnilを設定して、
            // 上部のスペースが確保されないようにする
            scrollView.horizontalRulerView = nil
        }

        // 縦ルーラーを設定
        if scrollView.hasVerticalRuler {
            let verticalRuler = LabeledRulerView(
                scrollView: scrollView,
                orientation: .verticalRuler
            )
            // マーカーとアクセサリビュー用の予約スペースを0にして、
            // 横ルーラーがある場合でもヘッダー領域を表示しない
            verticalRuler.reservedThicknessForMarkers = 0
            verticalRuler.reservedThicknessForAccessoryView = 0
            scrollView.verticalRulerView = verticalRuler
        } else {
            // 縦ルーラーが不要な場合は明示的にnilを設定して、
            // 左側のスペースが確保されないようにする
            scrollView.verticalRulerView = nil
        }
    }

    /// ルーラーの単位を設定
    internal func configureRulerUnit(_ ruler: NSRulerView) {
        var labelText = ""

        switch rulerType {
        case .none:
            // noneの場合は表示しないため、ここには来ないはず
            break
        case .point:
            ruler.measurementUnits = .points
            labelText = "Points"
        case .centimeter:
            ruler.measurementUnits = .centimeters
            labelText = "cm"
        case .inch:
            ruler.measurementUnits = .inches
            labelText = "Inches"
        case .character:
            // 基本フォントから文字幅を計算してカスタム単位を登録
            if let presetData = textDocument?.presetData {
                let fontData = presetData.fontAndColors
                if let basicFont = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                    let charWidth = basicCharWidth(from: basicFont)
                    registerCharacterRulerUnit(charWidth: charWidth)
                    ruler.measurementUnits = .characters
                    // フォント名とサイズを簡潔に表示
                    let shortName = basicFont.displayName ?? basicFont.fontName
                    labelText = "\(shortName) \(Int(fontData.baseFontSize))pt"
                }
            } else {
                // presetDataがない場合はシステムフォントを使用
                let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
                let charWidth = basicCharWidth(from: systemFont)
                registerCharacterRulerUnit(charWidth: charWidth)
                ruler.measurementUnits = .characters
                labelText = "System \(Int(NSFont.systemFontSize))pt"
            }
        }

        // LabeledRulerViewの場合はラベルを設定
        if let labeledRuler = ruler as? LabeledRulerView {
            labeledRuler.typeLabel = labelText
        }
    }

    // MARK: - Caret Position Indicator

    /// テキストビューの選択範囲変更を監視してルーラーのキャレット位置を更新
    @objc internal func textViewSelectionDidChange(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        updateRulerCaretPosition(for: textView)
        scheduleStatisticsUpdate()
    }

    /// ルーラー上のキャレット位置インジケータを更新
    internal func updateRulerCaretPosition(for textView: NSTextView) {
        guard isRulerVisible else { return }
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        // キャレット位置（挿入点）を取得
        let selectedRange = textView.selectedRange()
        let insertionPoint = selectedRange.location

        // 挿入点のグリフインデックスを取得
        let glyphIndex: Int
        let useEndPosition: Bool
        if insertionPoint < layoutManager.numberOfGlyphs {
            glyphIndex = layoutManager.glyphIndexForCharacter(at: insertionPoint)
            useEndPosition = false
        } else if layoutManager.numberOfGlyphs > 0 {
            // 文書末尾の場合は最後のグリフの末尾を使用
            glyphIndex = layoutManager.numberOfGlyphs - 1
            useEndPosition = true
        } else {
            // 空の文書の場合
            glyphIndex = 0
            useEndPosition = false
        }

        // 対応するScrollViewを見つけてルーラーを更新
        if let scrollView = textView.enclosingScrollView {
            let lineFragmentPadding = textContainer.lineFragmentPadding
            let isPageMode = (displayMode == .page)

            if isVerticalLayout {
                // 縦書きモード：縦ルーラーを使用
                // 縦書きでは画面上は文字が上から下に流れるが、
                // NSLayoutManagerは内部的に横書きと同じ座標系を使用している
                // つまり location.x が文字の進行方向（縦ルーラーのY位置）に対応する
                if let verticalRuler = scrollView.verticalRulerView as? LabeledRulerView {
                    var caretY: CGFloat = 0

                    if layoutManager.numberOfGlyphs > 0 {
                        let safeGlyphIndex = max(0, min(glyphIndex, layoutManager.numberOfGlyphs - 1))

                        // lineFragmentRectを取得
                        var effectiveRange = NSRange()
                        let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: safeGlyphIndex, effectiveRange: &effectiveRange)

                        // グリフの位置を取得
                        let location = layoutManager.location(forGlyphAt: safeGlyphIndex)

                        // 縦書きでは location.x が縦方向の位置を示す
                        // lineFragmentRect.origin.x + location.x が縦ルーラー上のY位置になる
                        if useEndPosition {
                            // 文書末尾の場合、グリフの下端（右端）を使用
                            let glyphRange = NSRange(location: safeGlyphIndex, length: 1)
                            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                            caretY = lineFragmentRect.origin.x + location.x + boundingRect.width
                        } else {
                            // 通常はグリフの上端（左端）を使用
                            caretY = lineFragmentRect.origin.x + location.x
                        }
                    }

                    // lineFragmentPaddingを引いてルーラーの0地点と一致させる
                    var adjustedCaretY = caretY - lineFragmentPadding

                    if isPageMode {
                        // ページモードでの調整（縦書き: topMarginを使用）
                        adjustedCaretY += textView.frame.origin.y - pageTopMargin
                    }

                    verticalRuler.caretPosition = adjustedCaretY
                }
            } else {
                // 横書きモード：横ルーラーを使用
                // lineFragmentRectとlocationを使用して正確な位置を計算
                var effectiveRange = NSRange()
                let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: max(0, min(glyphIndex, layoutManager.numberOfGlyphs - 1)), effectiveRange: &effectiveRange)

                // グリフの行フラグメント内での位置を取得
                let locationInLineFragment: NSPoint
                if layoutManager.numberOfGlyphs > 0 {
                    locationInLineFragment = layoutManager.location(forGlyphAt: glyphIndex)
                } else {
                    locationInLineFragment = .zero
                }

                // テキストコンテナ座標でのキャレットX位置を計算
                let caretX: CGFloat
                if useEndPosition {
                    // 文書末尾の場合、グリフの右端を使用
                    let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
                    caretX = glyphRect.maxX
                } else {
                    caretX = lineFragmentRect.origin.x + locationInLineFragment.x
                }

                if let horizontalRuler = scrollView.horizontalRulerView as? LabeledRulerView {
                    var adjustedCaretX = caretX - lineFragmentPadding
                    if isPageMode {
                        // ページモードでの調整（横書き: leftMarginを使用）
                        adjustedCaretX += textView.frame.origin.x - pageLeftMargin
                    }
                    horizontalRuler.caretPosition = adjustedCaretX
                }
            }
        }
    }

    /// 全てのテキストビューのルーラーキャレット位置を更新
    internal func updateAllRulerCaretPositions() {
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            updateRulerCaretPosition(for: textView)
        }
        if let scrollView = scrollView2, !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            updateRulerCaretPosition(for: textView)
        }
        for textView in textViews1 {
            updateRulerCaretPosition(for: textView)
        }
        for textView in textViews2 {
            updateRulerCaretPosition(for: textView)
        }
    }

    /// ズーム変更時にルーラーのキャレット位置を更新
    @objc internal func magnificationDidChange(_ notification: Notification) {
        // このウィンドウのScrollViewからの通知かチェック
        guard let scrollView = notification.object as? ScalingScrollView,
              scrollView === scrollView1 || scrollView === scrollView2 else { return }

        // ルーラーを再描画してキャレット位置を更新
        if let horizontalRuler = scrollView.horizontalRulerView as? LabeledRulerView {
            horizontalRuler.needsDisplay = true
        }
        if let verticalRuler = scrollView.verticalRulerView as? LabeledRulerView {
            verticalRuler.needsDisplay = true
        }

        // スケール表示を更新
        scrollView.updateScaleDisplay()

        // presetDataのスケールを更新（ピンチジェスチャー等での変更を保存）
        updatePresetDataScale()
    }

    // MARK: - Invisible Character Actions

    @IBAction func toggleAllInvisibleCharacters(_ sender: Any?) {
        if invisibleCharacterOptions == .none {
            // 1つもvisibleでない場合は全てオン
            invisibleCharacterOptions = .all
        } else {
            // 1つでもvisibleの場合は全てオフ
            invisibleCharacterOptions = .none
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowReturnCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.returnCharacter) {
            invisibleCharacterOptions.remove(.returnCharacter)
        } else {
            invisibleCharacterOptions.insert(.returnCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowTabCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.tabCharacter) {
            invisibleCharacterOptions.remove(.tabCharacter)
        } else {
            invisibleCharacterOptions.insert(.tabCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowSpaceCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.spaceCharacter) {
            invisibleCharacterOptions.remove(.spaceCharacter)
        } else {
            invisibleCharacterOptions.insert(.spaceCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowFullWidthSpaceCharacter(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.fullWidthSpaceCharacter) {
            invisibleCharacterOptions.remove(.fullWidthSpaceCharacter)
        } else {
            invisibleCharacterOptions.insert(.fullWidthSpaceCharacter)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowLineSeparator(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.lineSeparator) {
            invisibleCharacterOptions.remove(.lineSeparator)
        } else {
            invisibleCharacterOptions.insert(.lineSeparator)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowNonBreakingSpace(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.nonBreakingSpace) {
            invisibleCharacterOptions.remove(.nonBreakingSpace)
        } else {
            invisibleCharacterOptions.insert(.nonBreakingSpace)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowPageBreak(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.pageBreak) {
            invisibleCharacterOptions.remove(.pageBreak)
        } else {
            invisibleCharacterOptions.insert(.pageBreak)
        }
        updateInvisibleCharacterDisplay()
    }

    @IBAction func toggleShowVerticalTab(_ sender: Any?) {
        if invisibleCharacterOptions.contains(.verticalTab) {
            invisibleCharacterOptions.remove(.verticalTab)
        } else {
            invisibleCharacterOptions.insert(.verticalTab)
        }
        updateInvisibleCharacterDisplay()
    }

    internal func updateInvisibleCharacterDisplay() {
        // textStorageに関連付けられた全てのLayoutManagerを更新
        guard let textStorage = textDocument?.textStorage else { return }

        for layoutManager in textStorage.layoutManagers {
            if let invisibleLayoutManager = layoutManager as? InvisibleCharacterLayoutManager {
                invisibleLayoutManager.invisibleCharacterOptions = invisibleCharacterOptions
            }
        }

        // presetData に反映
        textDocument?.presetData?.view.showInvisibles = NewDocData.ViewData.ShowInvisibles(from: invisibleCharacterOptions)
        markDocumentAsEdited()
    }

    // MARK: - Plain/Rich Text Toggle

    @IBAction func toggleRichText(_ sender: Any?) {
        guard let document = textDocument else { return }
        let isRich = document.documentType != .plain

        // Rich → Plain で情報が失われる場合はアラートを表示
        if isRich && toggleRichWillLoseInformation() {
            let alert = NSAlert()
            alert.messageText = "Convert this document to plain text?".localized
            alert.informativeText = "Making a rich text document plain will lose all text styles (such as fonts and colors), and images.".localized
            alert.addButton(withTitle: "OK".localized)
            alert.addButton(withTitle: "Cancel".localized)
            alert.beginSheetModal(for: self.window!) { response in
                if response == .alertFirstButtonReturn {
                    self.performToggleRichText(newFileType: nil)
                }
            }
        } else {
            performToggleRichText(newFileType: nil)
        }
    }

    /// リッチテキスト→プレーンテキストに変換するときに情報が失われるかどうかを判定
    internal func toggleRichWillLoseInformation() -> Bool {
        guard let document = textDocument else { return false }
        let textStorage = document.textStorage
        let length = textStorage.length
        guard document.documentType != .plain, length > 0 else { return false }

        // プリセットからデフォルトの属性を構築
        var defaultAttrs: [NSAttributedString.Key: Any] = [:]
        if let fontData = document.presetData?.fontAndColors,
           let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            defaultAttrs[.font] = font
        }
        if let colors = document.presetData?.fontAndColors.colors {
            defaultAttrs[.foregroundColor] = colors.character.nsColor
        }

        var range = NSRange()
        let attrs = textStorage.attributes(at: 0, effectiveRange: &range)

        // 属性が全体に統一されていない場合は情報が失われる
        if range.length < length {
            return true
        }

        // アタッチメントが含まれている場合は情報が失われる
        if textStorage.containsAttachments {
            return true
        }

        // フォントがデフォルトと異なる場合は情報が失われる
        if let defaultFont = defaultAttrs[NSAttributedString.Key.font] as? NSFont,
           let existingFont = attrs[NSAttributedString.Key.font] as? NSFont,
           defaultFont != existingFont {
            return true
        }

        return false
    }

    /// 実際のリッチ/プレーン切り替えを実行する（Undo対応）
    internal func performToggleRichText(newFileType: String?) {
        guard let document = textDocument else { return }
        let isRich = document.documentType != .plain
        let textStorage = document.textStorage

        guard let undoManager = document.undoManager else { return }
        undoManager.beginUndoGrouping()

        // Undo用に元のファイルタイプを記録
        let oldFileType: String
        if isRich {
            oldFileType = textStorage.containsAttachments || document.documentType == .rtfd
                ? "com.apple.rtfd" : "public.rtf"
        } else {
            oldFileType = "public.plain-text"
        }
        undoManager.registerUndo(withTarget: self) { [weak self] target in
            self?.performToggleRichText(newFileType: oldFileType)
        }

        // テキストビューのリッチテキスト関連プロパティを更新
        updateForRichTextState(!isRich)

        // テキスト属性を変換
        convertTextForRichTextState(!isRich, removeAttachments: isRich)

        // ドキュメントタイプを切り替え
        if isRich {
            // Rich → Plain
            document.documentType = .plain

            // プレーンテキスト用のエンコーディング・改行コード・BOMをデフォルトに設定
            document.documentEncoding = .utf8
            document.lineEnding = .lf
            document.hasBOM = false

            // presetDataを更新
            document.presetData?.format.richText = false
            document.presetData?.format.fileExtension = "txt"
        } else {
            // Plain → Rich
            let type = newFileType ?? "public.rtf"
            document.documentType = (type == "com.apple.rtfd") ? .rtfd : .rtf

            // presetDataを更新
            document.presetData?.format.richText = true
        }

        // Undoアクション名を設定
        let actionName: String
        if undoManager.isUndoing != isRich {
            // Undo中なら逆のアクション名
            actionName = "Make Plain Text".localized
        } else {
            actionName = "Make Rich Text".localized
        }
        undoManager.setActionName(actionName)

        undoManager.endUndoGrouping()

        // ファイルタイプを更新
        // テキストタイプが変わるため、元のfileURLへのautosaveは行わず
        // fileURLをクリアして新規ドキュメント扱いにする（ユーザーが「名前を付けて保存」で保存する）
        let targetFileType = newFileType ?? (isRich ? "public.plain-text" : "public.rtf")
        if document.fileURL != nil {
            document.fileURL = nil
        }
        document.fileType = targetFileType

        // 通知を発行してUIを更新
        NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)

        // テキストビューを再構築してUIを完全に更新
        setupTextViews(with: textStorage)

        document.presetDataEdited = true
    }

    /// テキストビューのリッチテキスト関連プロパティを更新する
    internal func updateForRichTextState(_ rich: Bool) {
        // リッチテキストで縦書きの場合はインスペクタバーを強制表示
        if rich && isVerticalLayout && displayMode == .continuous {
            isInspectorBarVisible = true
        }

        // Continuousモード
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }

        // Pageモード
        for textView in textViews1 {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }
        for textView in textViews2 {
            textView.isRichText = rich
            textView.usesRuler = rich
            textView.importsGraphics = rich
        }
    }

    /// テキスト属性をリッチ/プレーンに合わせて変換する
    internal func convertTextForRichTextState(_ rich: Bool, removeAttachments: Bool) {
        guard let document = textDocument else { return }
        let textStorage = document.textStorage
        guard let undoManager = document.undoManager else { return }

        // デフォルトの属性を構築
        var textAttributes: [NSAttributedString.Key: Any] = [:]
        if let fontData = document.presetData?.fontAndColors,
           let font = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
            textAttributes[.font] = font
        } else {
            let fallbackFont: NSFont = NSFont.userFont(ofSize: 0) ?? NSFont.systemFont(ofSize: 13)
            textAttributes[.font] = fallbackFont
        }

        if let colors = document.presetData?.fontAndColors.colors {
            textAttributes[.foregroundColor] = colors.character.nsColor
        } else {
            textAttributes[.foregroundColor] = NSColor.textColor
        }

        // デフォルトのパラグラフスタイルをpresetDataから構築
        let formatData = document.presetData?.format
        let tabWidth: CGFloat = {
            if let fmt = formatData {
                return fmt.tabWidthUnit == .points ? fmt.tabWidthPoints : 28.0
            }
            return 28.0
        }()

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.defaultTabInterval = tabWidth
        paraStyle.tabStops = []
        paraStyle.lineHeightMultiple = formatData?.lineHeightMultiple ?? 1.0
        paraStyle.minimumLineHeight = formatData?.lineHeightMinimum ?? 0
        paraStyle.maximumLineHeight = formatData?.lineHeightMaximum ?? 0
        paraStyle.lineSpacing = formatData?.interLineSpacing ?? 0
        paraStyle.paragraphSpacingBefore = formatData?.paragraphSpacingBefore ?? 0
        paraStyle.paragraphSpacing = formatData?.paragraphSpacingAfter ?? 0
        textAttributes[.paragraphStyle] = paraStyle

        // Undo/Redo時はテキスト変換をスキップ（textView自身がUndo処理を行う）
        if !undoManager.isUndoing && !undoManager.isRedoing {
            // アタッチメントの除去（Rich → Plain）
            if !rich && removeAttachments {
                self.removeAttachments(from: textStorage)
            }

            // 属性を一括適用
            let range = NSRange(location: 0, length: textStorage.length)
            if let textView = currentTextView() ?? (scrollView1?.documentView as? NSTextView) {
                if textView.shouldChangeText(in: range, replacementString: nil) {
                    textStorage.beginEditing()
                    // 書字方向を保持しながら属性を適用
                    textStorage.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, paragraphRange, _ in
                        let writingDirection: NSWritingDirection = (value as? NSParagraphStyle)?.baseWritingDirection ?? .natural
                        textStorage.enumerateAttribute(.writingDirection, in: paragraphRange, options: []) { dirValue, attrRange, _ in
                            textStorage.setAttributes(textAttributes, range: attrRange)
                            if let dirValue = dirValue {
                                textStorage.addAttribute(.writingDirection, value: dirValue, range: attrRange)
                            }
                        }
                        if writingDirection != .natural {
                            textStorage.setBaseWritingDirection(writingDirection, range: paragraphRange)
                        }
                    }
                    textStorage.endEditing()
                    textView.didChangeText()
                }
            }
        }

        // typingAttributesとdefaultParagraphStyleを更新
        let allTextViews: [NSTextView] = {
            var views: [NSTextView] = []
            if let tv = scrollView1?.documentView as? NSTextView { views.append(tv) }
            if let tv = scrollView2?.documentView as? NSTextView { views.append(tv) }
            views.append(contentsOf: textViews1)
            views.append(contentsOf: textViews2)
            return views
        }()

        for textView in allTextViews {
            textView.typingAttributes = textAttributes
            textView.defaultParagraphStyle = paraStyle
        }
    }

    /// テキストストレージからアタッチメント文字を除去する
    internal func removeAttachments(from textStorage: NSTextStorage) {
        var loc = 0
        let textView = currentTextView() ?? (scrollView1?.documentView as? NSTextView)

        textStorage.beginEditing()
        while loc < textStorage.length {
            var attachmentRange = NSRange()
            let attachment = textStorage.attribute(.attachment, at: loc, longestEffectiveRange: &attachmentRange, in: NSRange(location: loc, length: textStorage.length - loc))
            if attachment != nil {
                let ch = (textStorage.string as NSString).character(at: loc)
                if ch == unichar(0xFFFC) {
                    if let textView = textView,
                       textView.shouldChangeText(in: NSRange(location: loc, length: 1), replacementString: "") {
                        textStorage.replaceCharacters(in: NSRange(location: loc, length: 1), with: "")
                        textView.didChangeText()
                    } else {
                        textStorage.replaceCharacters(in: NSRange(location: loc, length: 1), with: "")
                    }
                    // lengthが変わったのでlocは進めない
                } else {
                    loc += 1
                }
            } else {
                loc = NSMaxRange(attachmentRange)
            }
        }
        textStorage.endEditing()
    }

    // MARK: - Layout Orientation Actions

    @IBAction func toggleLayoutOrientation(_ sender: Any?) {
        // 現在の選択範囲を保存
        let savedRange = getCurrentSelectedRange()

        isVerticalLayout = !isVerticalLayout
        applyLayoutOrientation(savedRange: savedRange)

        // presetData に反映
        textDocument?.presetData?.format.editingDirection = isVerticalLayout ? .rightToLeft : .leftToRight
        markDocumentAsEdited()
    }

    internal func applyLayoutOrientation(savedRange: NSRange? = nil) {
        let orientation: NSLayoutManager.TextLayoutOrientation = isVerticalLayout ? .vertical : .horizontal

        // ページモードの場合はTextViewを再構築（setLayoutOrientationは大量テキストでフリーズするため）
        if displayMode == .page {
            guard let textDocument = self.textDocument else { return }
            setupTextViews(with: textDocument.textStorage)
            // ルーラー表示状態を引き継ぐ
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.updateRulerVisibility()
            }
            // Document Colorsを再適用
            if let colors = textDocument.presetData?.fontAndColors.colors {
                applyColorsToTextViews(colors)
            }
            // 選択範囲を復元してスクロール
            if let range = savedRange {
                restoreSelectionAndScrollToVisible(range, delay: 0.3)
            }
            return
        }

        // Continuous modeのテキストビュー
        if let scrollView = scrollView1,
           let textView = scrollView.documentView as? NSTextView {
            textView.setLayoutOrientation(orientation)
            // サイズとスクロールバーを更新（updateTextViewSize内でスクロールバー設定も行う）
            updateTextViewSize(for: scrollView)
        }
        if let scrollView = scrollView2,
           !scrollView.isHidden,
           let textView = scrollView.documentView as? NSTextView {
            textView.setLayoutOrientation(orientation)
            updateTextViewSize(for: scrollView)
        }

        for textView in textViews1 {
            textView.setLayoutOrientation(orientation)
        }
        for textView in textViews2 {
            textView.setLayoutOrientation(orientation)
        }

        // ルーラーの向きを更新
        updateRulerVisibility()

        // 行番号ビューを再構築（縦書き/横書きで位置が変わるため）
        if lineNumberMode != .none {
            if let scrollView = scrollView1 {
                setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberView1, constraintRef: &lineNumberWidthConstraint1)
                lineNumberView1?.textView = scrollView.documentView as? NSTextView
            }
            if let scrollView = scrollView2, !scrollView.isHidden {
                setupLineNumberView(for: scrollView, lineNumberViewRef: &lineNumberView2, constraintRef: &lineNumberWidthConstraint2)
                lineNumberView2?.textView = scrollView.documentView as? NSTextView
            }
        }

        // Document Colorsを再適用（行番号ビューの色など）
        if let colors = textDocument?.presetData?.fontAndColors.colors {
            applyColorsToTextViews(colors)
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.2)
        }
    }
}
