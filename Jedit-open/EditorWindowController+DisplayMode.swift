//
//  EditorWindowController+DisplayMode.swift
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

    // MARK: - Display Mode Actions

    @IBAction func toggleDisplayMode(_ sender: Any?) {
        // 現在の選択範囲を保存
        let savedRange = getCurrentSelectedRange()

        // モードを切り替え
        switch displayMode {
        case .continuous:
            // ページモードへの切り替え時は警告チェック
            switchToPageModeWithWarning(savedRange: savedRange)
            return
        case .page:
            displayMode = .continuous
        }

        // TextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
            // Document Colorsを再適用
            if let colors = textDocument.presetData?.fontAndColors.colors {
                applyColorsToTextViews(colors)
            }
        }
        // ルーラー表示状態を引き継ぐ（レイアウト完了後に実行）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateRulerVisibility()
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.2)
        }

        // presetData に反映
        textDocument?.presetData?.view.pageMode = (displayMode == .page)
        markDocumentAsEdited()
    }

    @IBAction func switchToContinuousMode(_ sender: Any?) {
        // 現在の選択範囲を保存
        let savedRange = getCurrentSelectedRange()

        displayMode = .continuous
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
            // Document Colorsを再適用
            if let colors = textDocument.presetData?.fontAndColors.colors {
                applyColorsToTextViews(colors)
            }
        }
        // ルーラー表示状態を引き継ぐ（レイアウト完了後に実行）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self = self else { return }
            self.updateRulerVisibility()
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.2)
        }

        // presetData に反映
        textDocument?.presetData?.view.pageMode = false
        markDocumentAsEdited()
    }

    @IBAction func switchToPageMode(_ sender: Any?) {
        switchToPageModeWithWarning(savedRange: getCurrentSelectedRange())
    }

    internal func switchToPageModeWithWarning(savedRange: NSRange? = nil) {
        guard let textDocument = self.textDocument else { return }
        displayMode = .page
        setupTextViews(with: textDocument.textStorage)
        // Document Colorsを再適用
        if let colors = textDocument.presetData?.fontAndColors.colors {
            applyColorsToTextViews(colors)
        }
        // ルーラー表示状態を引き継ぐ（レイアウト完了後に実行）
        // レイアウト処理が完了するまで待つ必要があるため、遅延を長めに設定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateRulerVisibility()
        }

        // 選択範囲を復元してスクロール
        if let range = savedRange {
            restoreSelectionAndScrollToVisible(range, delay: 0.3)
        }

        // presetData に反映
        textDocument.presetData?.view.pageMode = true
        markDocumentAsEdited()
    }

    // MARK: - Line Wrap Mode Actions (for Continuous mode)

    @IBAction func setLineWrapPaperWidth(_ sender: Any?) {
        lineWrapMode = .paperWidth
        applyLineWrapMode()
    }

    @IBAction func setLineWrapWindowWidth(_ sender: Any?) {
        lineWrapMode = .windowWidth
        applyLineWrapMode()
    }

    @IBAction func setLineWrapNoWrap(_ sender: Any?) {
        lineWrapMode = .noWrap
        applyLineWrapMode()
    }

    @IBAction func setLineWrapFixedWidth(_ sender: Any?) {
        // 固定幅を文字数で入力するダイアログを表示
        let alert = NSAlert()
        alert.messageText = "Fixed Width".localized
        alert.informativeText = "Enter the document width in characters:".localized
        alert.addButton(withTitle: "OK".localized)
        alert.addButton(withTitle: "Cancel".localized)

        // アクセサリビュー（テキストフィールド + ラベル）
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 80, height: 24))
        textField.integerValue = fixedWrapWidthInChars
        textField.alignment = .right
        // NumberFormatterを設定
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = 10
        formatter.maximum = 9999
        formatter.allowsFloats = false
        textField.formatter = formatter
        containerView.addSubview(textField)

        let label = NSTextField(labelWithString: "chars.".localized)
        label.frame = NSRect(x: 85, y: 4, width: 50, height: 17)
        containerView.addSubview(label)

        alert.accessoryView = containerView

        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                let chars = textField.integerValue
                if chars >= 10 && chars <= 9999 {
                    self?.fixedWrapWidthInChars = chars
                    self?.lineWrapMode = .fixedWidth
                    self?.applyLineWrapMode()
                }
            }
        }
    }

    // MARK: - Word Wrapping Actions

    @IBAction func setWordWrappingSystemDefault(_ sender: Any?) {
        setWordWrappingType(.systemDefault)
    }

    @IBAction func setWordWrappingJapanese(_ sender: Any?) {
        setWordWrappingType(.japaneseWordwrap)
    }

    @IBAction func setWordWrappingNone(_ sender: Any?) {
        setWordWrappingType(.dontWordwrap)
    }

    internal func setWordWrappingType(_ type: NewDocData.FormatData.WordWrappingType) {
        guard textDocument?.presetData != nil else { return }
        textDocument?.presetData?.format.wordWrappingType = type
        textDocument?.presetDataEdited = true

        // JOTextStorageに反映
        if let textStorage = textDocument?.textStorage {
            textStorage.setLineBreakingType(type.rawValue)

            // 禁則処理の変更は lineBreakBeforeIndex の結果に影響するため、
            // 全レイアウトを無効化する。
            //
            // ただし invalidate の後にページ表示モードで addPage を呼ぶと、
            // addPage 内の `textView.isSelectable = true` 等が setNeedsDisplayInRect
            // 経由で `_glyphRangeForBoundingRect(... okToFillHoles:YES)` を走らせ、
            // 無効化された範囲の穴埋めを試みてデリゲート addPage を無限に要求するため
            // フリーズする。
            //
            // そこで順序を: ①事前に余分なページを追加（レイアウトがまだ有効なので穴埋め不要）
            // → ②その後で invalidate → ③再描画時は既に十分なコンテナがあるので
            // デリゲートが addPage を追加せずに済む、とする。

            // ① 事前にページを多めに確保（この時点ではレイアウトは有効なので再入ループ無し）
            if displayMode == .page {
                let extraPages = 20
                if let lm1 = layoutManager1, let sv1 = scrollView1 {
                    for _ in 0..<extraPages {
                        addPage(to: lm1, in: sv1, for: .scrollView1)
                    }
                }
                if let lm2 = layoutManager2, let sv2 = scrollView2, !(sv2.isHidden) {
                    for _ in 0..<extraPages {
                        addPage(to: lm2, in: sv2, for: .scrollView2)
                    }
                }
            }

            // ② レイアウトを無効化
            let fullRange = NSRange(location: 0, length: textStorage.length)
            for layoutManager in textStorage.layoutManagers {
                layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            }
            lastAddPageLayoutedChar = -1

            // ③ ページフレームを更新（余剰ページは後続の checkForLayoutIssues で除去される）
            if displayMode == .page {
                updateAllTextViewFrames(for: .scrollView1)
                if let sv2 = scrollView2, !sv2.isHidden {
                    updateAllTextViewFrames(for: .scrollView2)
                }
            }
        }

        // 文書幅を再計算してレイアウトを更新
        applyLineWrapMode(updatePresetData: false)
    }

    /// 固定幅をポイント値で取得（文字数 × 基本文字幅）
    internal func getFixedWrapWidthInPoints() -> CGFloat {
        let charWidth: CGFloat
        if let presetData = textDocument?.presetData {
            let fontData = presetData.fontAndColors
            if let basicFont = NSFont(name: fontData.baseFontName, size: fontData.baseFontSize) {
                charWidth = basicCharWidth(from: basicFont)
            } else {
                charWidth = 8.0  // フォントが見つからない場合のデフォルト
            }
        } else {
            // presetDataがない場合はシステムフォントを使用
            let systemFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            charWidth = basicCharWidth(from: systemFont)
        }

        // 日本語禁則処理（japaneseWordwrap = 1）の場合、ぶら下げ用に+1文字分の幅を追加
        let extraChar: Int
        if let presetData = textDocument?.presetData,
           presetData.format.wordWrappingType == .japaneseWordwrap {
            extraChar = 1
        } else {
            extraChar = 0
        }

        return CGFloat(fixedWrapWidthInChars + extraChar) * charWidth
    }

    internal func applyLineWrapMode(updatePresetData: Bool = true) {
        // presetData に反映（メニューからの変更時のみ更新、初期化時は更新しない）
        if updatePresetData {
            updatePresetDataDocWidth()
        }

        guard displayMode == .continuous else { return }

        // ScalingScrollViewのautoAdjustsContainerSizeOnFrameChangeを設定
        // 横書きのwindowWidthモードのみScalingScrollViewにコンテナサイズ調整を任せる
        // 縦書きでは常にfalse（textViewの幅が縮小されるのを防ぐため）
        let autoAdjust = !isVerticalLayout && (lineWrapMode == .windowWidth)
        scrollView1?.autoAdjustsContainerSizeOnFrameChange = autoAdjust
        scrollView2?.autoAdjustsContainerSizeOnFrameChange = autoAdjust

        if let scrollView = scrollView1 {
            updateTextViewSize(for: scrollView)
        }
        if let scrollView = scrollView2, !scrollView.isHidden {
            updateTextViewSize(for: scrollView)
        }

        // モード切り替え直後は NSScrollView のスクロールバー/contentView の再配置が
        // まだ確定しておらず、縦書き + .noWrap → .windowWidth の切り替え時に
        // 古い contentView.frame で計算されて行長がウィンドウを超える現象が起きる。
        // 次のランループでもう一度計算し直して最終的なレイアウトに追従する。
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let scrollView = self.scrollView1 {
                self.updateTextViewSize(for: scrollView)
            }
            if let scrollView = self.scrollView2, !scrollView.isHidden {
                self.updateTextViewSize(for: scrollView)
            }
        }
    }

    /// presetData の Document Width 設定を更新
    internal func updatePresetDataDocWidth() {
        syncDocWidthToPresetData()
        markDocumentAsEdited()
    }

    /// 現在の Document Width 設定を presetData に同期
    internal func syncDocWidthToPresetData() {
        switch lineWrapMode {
        case .paperWidth:
            textDocument?.presetData?.view.docWidthType = .paperWidth
        case .windowWidth:
            textDocument?.presetData?.view.docWidthType = .windowWidth
        case .noWrap:
            textDocument?.presetData?.view.docWidthType = .noWrap
        case .fixedWidth:
            textDocument?.presetData?.view.docWidthType = .fixedWidth
            textDocument?.presetData?.view.fixedDocWidth = fixedWrapWidthInChars
        }
    }

    /// presetData の変更をマーク（保存時に拡張属性が更新される）
    /// ウィンドウタイトルに「Edited」は表示されない
    internal func markDocumentAsEdited() {
        textDocument?.presetDataEdited = true
    }

    // MARK: - Pagination Methods

    internal enum ScrollViewTarget {
        case scrollView1
        case scrollView2
    }

    internal func addPage(to layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {
        // 再入防止
        guard !isAddingPage else { return }
        isAddingPage = true
        defer { isAddingPage = false }

        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]
        var pagesView: MultiplePageView?

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            pagesView = pagesView1
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            pagesView = pagesView2
        }

        guard let pagesView = pagesView else { return }

        let textContainerSize = pagesView.documentSizeInPage

        // 新しいTextContainerを作成
        let textContainer = NSTextContainer(containerSize: textContainerSize)
        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        // LayoutManagerにTextContainerを追加
        layoutManager.addTextContainer(textContainer)

        // 一時的なフレームでTextViewを作成（後でupdateAllTextViewFramesで更新される、画像クリック対応）
        let tempFrame = NSRect(x: 0, y: 0, width: textContainerSize.width, height: textContainerSize.height)
        let textView = JeditTextView(frame: tempFrame, textContainer: textContainer)
        textView.isEditable = !(textDocument?.presetData?.view.preventEditing ?? false)
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.autoresizingMask = []
        textView.textContainerInset = NSSize(width: 0, height: 0)
        // リッチテキスト書類の場合はisRichTextとimportsGraphicsを設定
        let isPlainTextNewPage = textDocument?.documentType == .plain
        textView.isRichText = !isPlainTextNewPage
        textView.importsGraphics = !isPlainTextNewPage
        // ダークモード対応（プレーンテキストのみ）
        // リッチテキストは白背景固定（文字色はユーザー設定を保持）
        if isPlainTextNewPage {
            textView.backgroundColor = .textBackgroundColor
            textView.textColor = .textColor
        } else {
            textView.backgroundColor = .white
        }
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.usesInspectorBar = isInspectorBarVisible
        textView.usesRuler = true
        textView.usesFindBar = false
        textView.isIncrementalSearchingEnabled = true
        // ImageResizeControllerを設定
        textView.imageResizeController = imageResizeController

        // レイアウト方向の設定は addPage 内では行わない。
        // NSTextView.setLayoutOrientation は対象コンテナのレイアウトを無効化するため、
        // 縦書きでページ表示の際、addPage が NSLayoutManager の fill-holes パス中に
        // 呼ばれると「新コンテナに流し込み→orientation 変更で再無効化→もう一度流し込み」
        // を外側ループが無限に繰り返してフリーズする（横書きや連続モードでは発生しない）。
        //
        // ここでは設定せず、addPage 完了後の updateAllTextViewFrames で
        // レイアウトパスの外側で一括設定する。

        // 一時的に非表示（フレームはupdateAllTextViewFramesで更新される）
        textView.isHidden = true

        // 配列に追加
        textContainers.append(textContainer)
        textViews.append(textView)

        // pagesViewにTextViewを追加（まだ表示位置は未設定）
        pagesView.addSubview(textView)

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // ページ追加をマーク（レイアウト完了後にフレームを更新するため）
        needsPageFrameUpdate = true
    }

    internal func removeExcessPages(from layoutManager: NSLayoutManager, in scrollView: NSScrollView, for target: ScrollViewTarget) {
        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            guard pagesView1 != nil else { return }
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            guard pagesView2 != nil else { return }
        }

        // テキストストレージの長さを取得
        guard let textStorage = layoutManager.textStorage else { return }
        let textLength = textStorage.length

        // 最初の空のコンテナを見つける（それ以降はすべて削除対象）
        var firstEmptyIndex = textContainers.count  // デフォルトは削除なし

        // 前方から探索して、最初の空または無効なコンテナを見つける
        let totalGlyphs = layoutManager.numberOfGlyphs
        let validContainers = Set(layoutManager.textContainers)
        for index in 0..<textContainers.count {
            let container = textContainers[index]
            // コンテナがレイアウトマネージャに存在しない場合は無効として削除対象
            guard validContainers.contains(container) else {
                firstEmptyIndex = index
                break
            }
            let glyphRange = layoutManager.glyphRange(for: container)

            if glyphRange.length == 0 {
                // グリフがない - このコンテナ以降を削除
                firstEmptyIndex = index
                break
            } else {
                // グリフがある場合、文字範囲とグリフ範囲が有効かチェック
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                // 文字範囲の終端がテキスト長を超えている場合は無効（古いデータ）
                if NSMaxRange(charRange) > textLength {
                    firstEmptyIndex = index
                    break
                }
                // グリフ範囲の開始位置が総グリフ数以上の場合は無効（古いデータ）
                if glyphRange.location >= totalGlyphs {
                    firstEmptyIndex = index
                    break
                }
            }
        }

        // 最初の空コンテナ以降を削除対象にする（ただし最低1ページは残す）
        var indicesToRemove: [Int] = []
        let startIndex = max(1, firstEmptyIndex)  // 最初のページは残す
        for index in startIndex..<textContainers.count {
            indicesToRemove.append(index)
        }

        // 逆順で削除（インデックスのずれを防ぐ）
        for index in indicesToRemove.reversed() {
            let container = textContainers[index]
            let textView = textViews[index]

            // TextViewをpagesViewから削除
            textView.removeFromSuperview()

            // layoutManagerから削除（layoutManager内のインデックスを見つける）
            if let layoutManagerIndex = layoutManager.textContainers.firstIndex(of: container) {
                layoutManager.removeTextContainer(at: layoutManagerIndex)
            }

            // 配列から削除
            textContainers.remove(at: index)
            textViews.remove(at: index)
        }

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }
    }

    /// レイアウト完了後の遅延チェック：問題があれば修正
    internal func checkForLayoutIssues(layoutManager: NSLayoutManager, scrollView: NSScrollView, target: ScrollViewTarget, retryCount: Int = 0) {
        // 更新中なら少し待ってから再試行（最大5回）
        if isUpdatingPages {
            if retryCount < 5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                    self?.checkForLayoutIssues(layoutManager: layoutManager, scrollView: scrollView, target: target, retryCount: retryCount + 1)
                }
            } else {
                isUpdatingPages = false
                // 再帰呼び出しせず、直接実行
            }
            if retryCount < 5 { return }
        }

        let currentContainers = target == .scrollView1 ? textContainers1 : textContainers2
        guard let textStorage = layoutManager.textStorage else { return }
        let textLength = textStorage.length

        // レイアウトマネージャに実際に存在するコンテナのセットを取得
        let validContainers = Set(layoutManager.textContainers)

        // 全コンテナの文字範囲を確認
        var totalLayoutedChars = 0
        var emptyContainerCount = 0
        for container in currentContainers {
            // コンテナがレイアウトマネージャに存在するか確認
            guard validContainers.contains(container) else { continue }

            let glyphRange = layoutManager.glyphRange(for: container)
            if glyphRange.length > 0 {
                let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                totalLayoutedChars += charRange.length
            } else {
                emptyContainerCount += 1
            }
        }

        // 問題があれば対処
        if totalLayoutedChars > textLength {
            // 古いデータがある場合は再構築
            isUpdatingPages = true
            defer { isUpdatingPages = false }
            rebuildAllPages(for: layoutManager, in: scrollView, target: target)
        } else if emptyContainerCount > 0 {
            // 空のコンテナがある場合は削除
            isUpdatingPages = true
            defer { isUpdatingPages = false }
            removeExcessPages(from: layoutManager, in: scrollView, for: target)

            // ページ数を更新
            let newCount = target == .scrollView1 ? textContainers1.count : textContainers2.count
            if let pagesView = (target == .scrollView1 ? pagesView1 : pagesView2) {
                pagesView.setNumberOfPages(newCount)
                // 強制的に再描画
                pagesView.needsDisplay = true
                pagesView.needsLayout = true
            }
            updateAllTextViewFrames(for: target)

            // すべてのテキストビューを再描画
            let textViews = target == .scrollView1 ? textViews1 : textViews2
            for textView in textViews {
                textView.needsDisplay = true
            }
        }
    }

    /// テキスト長が減少した場合に全ページを再構築
    internal func rebuildAllPages(for layoutManager: NSLayoutManager, in scrollView: NSScrollView, target: ScrollViewTarget) {
        var textContainers: [NSTextContainer]
        var textViews: [NSTextView]
        var pagesView: MultiplePageView?

        switch target {
        case .scrollView1:
            textContainers = textContainers1
            textViews = textViews1
            pagesView = pagesView1
        case .scrollView2:
            textContainers = textContainers2
            textViews = textViews2
            pagesView = pagesView2
        }

        guard let pagesView = pagesView else { return }

        // 全てのテキストビューを削除
        for textView in textViews {
            textView.removeFromSuperview()
        }

        // 全てのテキストコンテナをレイアウトマネージャーから削除
        while layoutManager.textContainers.count > 0 {
            layoutManager.removeTextContainer(at: 0)
        }

        // 配列をクリア
        textContainers.removeAll()
        textViews.removeAll()

        // 配列をプロパティに戻す
        switch target {
        case .scrollView1:
            textContainers1 = textContainers
            textViews1 = textViews
        case .scrollView2:
            textContainers2 = textContainers
            textViews2 = textViews
        }

        // 必要なページ数を推定（1ページあたりの文字数を概算）
        guard let textStorage = layoutManager.textStorage else { return }
        let charsPerPage = 1000
        let estimatedPages = max(1, (textStorage.length + charsPerPage - 1) / charsPerPage)

        // ページを再作成
        createAllPages(count: estimatedPages, for: layoutManager, in: scrollView, target: target)

        // ページ数を設定
        let newPageCount = target == .scrollView1 ? textContainers1.count : textContainers2.count
        pagesView.setNumberOfPages(newPageCount)

        // フレームを更新
        updateAllTextViewFrames(for: target)

        // ビューの再描画を強制
        pagesView.needsDisplay = true
        pagesView.needsLayout = true
    }
}
