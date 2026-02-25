//
//  Document+Bookmark.swift
//  Jedit-open
//
//  Document にブックマーク機能を追加する拡張。
//  カスタムアンカー属性の定義、ブックマーク選択、アンカー管理を含む。
//  JeditΩ の JODocument+bookmark を Swift で再実装。
//

import Cocoa
import ObjectiveC

// MARK: - Custom Anchor Attribute Key

extension NSAttributedString.Key {
    /// ブックマークアンカーのカスタム属性キー。
    /// 値は UUID 文字列（フォーマット: "JEDITANCHOR:<UUID>"）。
    /// プレーンテキスト・リッチテキストの両方で使用可能。
    static let anchor = NSAttributedString.Key("jp.co.artman21.Jedit-open.anchor")
}

// MARK: - Document + Bookmark

extension Document {

    // MARK: - Associated Object Keys

    private struct AssociatedKeys {
        nonisolated(unsafe) static var rootBookmark: UInt8 = 0
    }

    // MARK: - Root Bookmark

    /// ブックマークツリーのルートノード（不可視、ツリーの根として機能）。
    /// 初回アクセス時に遅延生成される。
    var rootBookmark: Bookmark {
        if let existing = objc_getAssociatedObject(self, &AssociatedKeys.rootBookmark) as? Bookmark {
            return existing
        }
        let root = Bookmark(uuid: "ROOT", displayName: "Root", range: NSRange(location: 0, length: 0))
        objc_setAssociatedObject(self, &AssociatedKeys.rootBookmark, root, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return root
    }

    // MARK: - Bookmark Selection

    /// 現在の選択範囲からブックマークを作成する。
    /// メニューの "Bookmark Selection" またはブックマークパネルの (+) ボタンから呼び出される。
    @objc func bookmarkSelection(_ sender: Any?) {
        guard let textView = currentTextView else { return }

        guard let bookmark = createBookmarkFromRange(textView.selectedRange()) else {
            NSSound.beep()
            return
        }

        // パネルで選択中のブックマークの後に挿入、なければ root の末尾に追加
        let panelController = BookmarkPanelController.shared
        if panelController.isPanelVisible,
           let selectedInPanel = panelController.selectedBookmark(),
           let parent = selectedInPanel.parentBookmark {
            parent.insertChild(bookmark, after: selectedInPanel)
        } else {
            rootBookmark.addChild(bookmark)
        }

        // ブックマークパネルを表示してアウトラインビューを更新、追加したブックマークを選択
        if !panelController.isPanelVisible {
            panelController.showPanel()
        } else {
            panelController.reloadOutlineView()
        }
        panelController.selectBookmarkInOutlineView(bookmark)
    }

    // MARK: - Bookmark Creation

    /// 指定した選択範囲からブックマークを作成して返す。
    /// 行全体に拡張し、アンカー属性を設定する。ツリーへの追加は呼び出し側が行う。
    /// - Parameter selectedRange: ブックマークを作成する選択範囲。
    /// - Returns: 作成された Bookmark オブジェクト。空行のみの場合や、キャンセル時は nil。
    func createBookmarkFromRange(_ selectedRange: NSRange) -> Bookmark? {
        guard textStorage.length > 0 else { return nil }

        var range = selectedRange

        // 選択が空（挿入ポイント）の場合、少なくとも1文字に拡張
        if range.length == 0 {
            range.length = 1
            if range.location == textStorage.length {
                range.location -= 1
            }
        }

        // 選択範囲を行全体に拡張
        let string = textStorage.string as NSString
        let lineRange = string.lineRange(for: range)

        // 表示名を取得（空行でない最初の行テキスト、最大50文字）
        let lineText = string.substring(with: lineRange)
        let lines = lineText.components(separatedBy: .newlines)

        // 空行でない最初の行を探す
        guard let firstNonEmptyLine = lines.first(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            return nil
        }

        let trimmed = firstNonEmptyLine.trimmingCharacters(in: .whitespaces)
        let displayName: String
        let maxLength = 50
        if trimmed.count > maxLength {
            displayName = String(trimmed.prefix(maxLength)) + "…"
        } else {
            displayName = trimmed
        }

        // アンカーを作成
        guard let uuid = createAnchor(for: lineRange, ask: true) else { return nil }

        return Bookmark(uuid: uuid, displayName: displayName, range: lineRange)
    }

    // MARK: - Bookmark Range Update

    /// ブックマークツリーの全 range を textStorage のアンカー属性から更新する。
    /// 書類編集後に range が古くなるため、sortByLocation など range を使う操作の前に呼ぶ。
    func refreshBookmarkRanges() {
        // textStorage から UUID → NSRange のマップを構築
        var rangeMap: [String: NSRange] = [:]
        let fullRange = NSRange(location: 0, length: textStorage.length)
        textStorage.enumerateAttribute(.anchor, in: fullRange, options: []) { value, attrRange, _ in
            if let uuid = value as? String {
                rangeMap[uuid] = attrRange
            }
        }

        // ブックマークツリーを再帰的に更新
        refreshRangesRecursively(rootBookmark, rangeMap: rangeMap)
    }

    /// ブックマークとその子孫の range を再帰的に更新する。
    private func refreshRangesRecursively(_ bookmark: Bookmark, rangeMap: [String: NSRange]) {
        if let newRange = rangeMap[bookmark.uuid] {
            bookmark.range = newRange
        }
        for child in bookmark.childBookmarks {
            refreshRangesRecursively(child, rangeMap: rangeMap)
        }
    }

    // MARK: - Anchor Management

    /// 指定範囲にアンカー属性を作成する。
    /// - Parameters:
    ///   - range: アンカーを設定する範囲。
    ///   - ask: true の場合、既存アンカーがあればアラートを表示する。
    /// - Returns: 作成されたアンカーの UUID 文字列。キャンセル時は nil。
    func createAnchor(for range: NSRange, ask: Bool) -> String? {
        // 範囲内に既存のアンカーがあるかチェック
        if ask {
            var existingAnchorCount = 0
            textStorage.enumerateAttribute(.anchor, in: range, options: []) { value, _, _ in
                if value != nil {
                    existingAnchorCount += 1
                }
            }

            if existingAnchorCount > 0 {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString(
                    "Another bookmark already exists in the range.",
                    comment: "Bookmark exists alert title")
                alert.informativeText = NSLocalizedString(
                    "If you make new bookmark, The range of old bookmark may be broken.",
                    comment: "Bookmark exists alert message")
                alert.alertStyle = .informational
                alert.addButton(withTitle: NSLocalizedString("OK", comment: "OK button"))
                alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel button"))

                let response = alert.runModal()
                if response != .alertFirstButtonReturn {
                    return nil
                }
            }
        }

        // UUID を生成
        let uuid = "JEDITANCHOR:\(UUID().uuidString)"

        // textStorage にアンカー属性をセット
        textStorage.addAttribute(.anchor, value: uuid, range: range)

        // ドキュメントを変更済みとしてマーク
        updateChangeCount(.changeDone)

        return uuid
    }

    /// 指定した識別子のアンカーを検索し、選択してスクロールする。
    /// - Parameter identifier: アンカーの UUID 文字列。
    /// - Returns: アンカーが見つかった場合は true。
    @discardableResult
    func selectAnchor(identifier: String) -> Bool {
        guard let textView = currentTextView else { return false }

        let fullRange = NSRange(location: 0, length: textStorage.length)
        var foundRange: NSRange?

        textStorage.enumerateAttribute(.anchor, in: fullRange, options: []) { value, attrRange, stop in
            if let anchorValue = value as? String, anchorValue == identifier {
                foundRange = attrRange
                stop.pointee = true
            }
        }

        if let range = foundRange {
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
            return true
        }
        return false
    }

    /// 指定した識別子のアンカー属性を textStorage から削除する。
    /// - Parameter identifier: 削除するアンカーの UUID 文字列。
    /// - Returns: アンカーが見つかって削除された場合は true。
    @discardableResult
    func removeAnchor(identifier: String) -> Bool {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var rangesToRemove: [NSRange] = []

        textStorage.enumerateAttribute(.anchor, in: fullRange, options: []) { value, attrRange, _ in
            if let anchorValue = value as? String, anchorValue == identifier {
                rangesToRemove.append(attrRange)
            }
        }

        guard !rangesToRemove.isEmpty else { return false }

        textStorage.beginEditing()
        for range in rangesToRemove {
            textStorage.removeAttribute(.anchor, range: range)
        }
        textStorage.endEditing()

        updateChangeCount(.changeDone)
        return true
    }

    // MARK: - Bookmark Serialization (Save)

    /// ブックマークツリーを BookmarkData 配列にシリアライズして presetData に保存する。
    /// updatePresetDataFromCurrentState() から呼ばれる。
    func serializeBookmarksToPresetData() {
        // range を最新に更新
        refreshBookmarkRanges()

        let children = rootBookmark.childBookmarks
        if children.isEmpty {
            presetData?.bookmarks = nil
        } else {
            presetData?.bookmarks = children.map { BookmarkData(from: $0) }
        }
    }

    /// RTF 保存前にアンカー属性をリンク属性に変換する。
    /// 保存後は restoreAnchorsAfterSave(_:) で元に戻す。
    /// - Returns: 復元用のデータ。
    func convertAnchorsToLinksForSave() -> [(range: NSRange, uuid: String, originalLink: Any?)] {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var anchorData: [(range: NSRange, uuid: String, originalLink: Any?)] = []

        textStorage.enumerateAttribute(.anchor, in: fullRange, options: []) { value, attrRange, _ in
            if let uuid = value as? String {
                let originalLink = textStorage.attribute(.link, at: attrRange.location, effectiveRange: nil)
                anchorData.append((attrRange, uuid, originalLink))
            }
        }

        guard !anchorData.isEmpty else { return [] }

        textStorage.beginEditing()
        for (range, uuid, _) in anchorData {
            textStorage.removeAttribute(.anchor, range: range)
            textStorage.addAttribute(.link, value: uuid, range: range)
        }
        textStorage.endEditing()

        return anchorData
    }

    /// RTF 保存後にリンク属性をアンカー属性に復元する。
    /// - Parameter savedData: convertAnchorsToLinksForSave() で返されたデータ。
    func restoreAnchorsAfterSave(_ savedData: [(range: NSRange, uuid: String, originalLink: Any?)]) {
        guard !savedData.isEmpty else { return }

        textStorage.beginEditing()
        for (range, uuid, originalLink) in savedData {
            textStorage.removeAttribute(.link, range: range)
            textStorage.addAttribute(.anchor, value: uuid, range: range)
            if let originalLink = originalLink {
                textStorage.addAttribute(.link, value: originalLink, range: range)
            }
        }
        textStorage.endEditing()
    }

    // MARK: - Bookmark Restoration (Load)

    /// presetData のブックマークデータからブックマークツリーを復元し、
    /// textStorage にアンカー属性を付加する。
    /// RTF の場合、保存時に anchor→link に変換された JEDITANCHOR: リンク属性を
    /// 全て削除してからアンカー属性を設定する。
    /// - Returns: ブックマークが復元された場合は true。
    @discardableResult
    func restoreBookmarksFromPresetData() -> Bool {
        guard let bookmarkDataArray = presetData?.bookmarks, !bookmarkDataArray.isEmpty else {
            return false
        }

        let root = rootBookmark
        root.childBookmarks.removeAll()

        for data in bookmarkDataArray {
            root.addChild(data.toBookmark())
        }

        // RTF から読み込んだ場合、JEDITANCHOR: リンク属性が残っているので一括削除
        removeAllAnchorLinkAttributes()

        // textStorage にアンカー属性を設定
        applyAnchorAttributesFromBookmarks(root)

        return true
    }

    /// リンク属性値から文字列を取得するヘルパー。
    /// RTF ラウンドトリップ後、リンク属性値が String / URL / NSURL のいずれかになりうるため、
    /// 全てのケースを処理する。
    private func linkValueAsString(_ value: Any?) -> String? {
        if let str = value as? String {
            return str
        } else if let url = value as? URL {
            return url.absoluteString
        } else if let url = value as? NSURL {
            return url.absoluteString
        } else if let value = value {
            // その他の型の場合、文字列表現を試す
            let str = "\(value)"
            if str.hasPrefix("JEDITANCHOR:") {
                return str
            }
        }
        return nil
    }

    /// textStorage 内の全ての JEDITANCHOR: リンク属性を削除する。
    private func removeAllAnchorLinkAttributes() {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var rangesToRemove: [NSRange] = []

        textStorage.enumerateAttribute(.link, in: fullRange, options: []) { value, attrRange, _ in
            if let linkString = self.linkValueAsString(value),
               linkString.hasPrefix("JEDITANCHOR:") {
                rangesToRemove.append(attrRange)
            }
        }

        guard !rangesToRemove.isEmpty else { return }

        textStorage.beginEditing()
        for range in rangesToRemove {
            textStorage.removeAttribute(.link, range: range)
        }
        textStorage.endEditing()
    }

    /// リッチテキストのリンク属性からブックマークを復元する。
    /// "JEDITANCHOR:" で始まるリンク属性をアンカー属性に変換し、
    /// ブックマークツリーを構築する。
    /// - Returns: ブックマークが復元された場合は true。
    @discardableResult
    func restoreBookmarksFromLinkAttributes() -> Bool {
        let fullRange = NSRange(location: 0, length: textStorage.length)
        var anchorLinks: [(range: NSRange, uuid: String)] = []

        textStorage.enumerateAttribute(.link, in: fullRange, options: []) { value, attrRange, _ in
            if let linkString = self.linkValueAsString(value),
               linkString.hasPrefix("JEDITANCHOR:") {
                anchorLinks.append((attrRange, linkString))
            }
        }

        guard !anchorLinks.isEmpty else { return false }

        // リンク属性をアンカー属性に変換
        textStorage.beginEditing()
        for (range, uuid) in anchorLinks {
            textStorage.removeAttribute(.link, range: range)
            textStorage.addAttribute(.anchor, value: uuid, range: range)
        }
        textStorage.endEditing()

        // ブックマークツリーを構築
        let root = rootBookmark
        root.childBookmarks.removeAll()

        for (range, uuid) in anchorLinks {
            let text = (textStorage.string as NSString).substring(with: range)
            let lines = text.components(separatedBy: .newlines)
            let displayName = lines.first(where: {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            })?.trimmingCharacters(in: .whitespaces) ?? "Bookmark"
            let maxLength = 50
            let trimmedName = displayName.count > maxLength
                ? String(displayName.prefix(maxLength)) + "…" : displayName

            let bookmark = Bookmark(uuid: uuid, displayName: trimmedName, range: range)
            root.addChild(bookmark)
        }

        return true
    }

    /// ブックマークツリーの全ブックマークのアンカー属性を textStorage に設定する。
    /// 呼び出し前に removeAllAnchorLinkAttributes() で JEDITANCHOR: リンクを
    /// 削除済みであること。
    private func applyAnchorAttributesFromBookmarks(_ bookmark: Bookmark) {
        for child in bookmark.childBookmarks {
            let range = child.range
            // 範囲が textStorage 内に収まることを確認
            if range.location + range.length <= textStorage.length {
                textStorage.addAttribute(.anchor, value: child.uuid, range: range)
            }
            // 子孫を再帰的に処理
            applyAnchorAttributesFromBookmarks(child)
        }
    }

    // MARK: - Show Bookmark Panel

    /// ブックマークパネルを表示する（メニューアクションから呼び出される）。
    @objc func showBookmarkPanel(_ sender: Any?) {
        BookmarkPanelController.shared.showPanel()
    }
}
