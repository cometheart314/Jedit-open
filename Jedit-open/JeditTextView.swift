//
//  JeditTextView.swift
//  Jedit-open
//
//  Custom NSTextView subclass that detects clicks on image attachments
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
import UniformTypeIdentifiers

// MARK: - JeditTextView

class JeditTextView: NSTextView {

    // MARK: - Properties

    /// Controller for handling image resize operations
    var imageResizeController: ImageResizeController?

    /// Character index of the image attachment for context menu action
    private var contextMenuImageCharIndex: Int?

    /// カラーパネルのモード（前景色か背景色か）
    enum ColorPanelMode {
        case none
        case foreground
        case background
    }
    var colorPanelMode: ColorPanelMode = .none

    /// updateRuler()の再入防止フラグ
    private var isUpdatingRuler: Bool = false

    /// ドラッグ開始時のソース選択範囲（ドロップ時に selectedRange() が変わっている場合の保護）
    var dragSourceRange: NSRange?

    /// 同一書類内ドラッグを自前で処理したかどうか（super のソース削除を防ぐフラグ）
    var handledSameDocumentDrag = false

    /// ドラッグ操作用の一時ファイルURL（遅延クリーンアップ）
    var dragTempFileURLs: [URL] = []

    /// RTFD昇格済みフラグ（performDragOperationでアラート表示後にreadSelectionで再チェックしない）
    var rtfdUpgradeHandled: Bool = false

    /// テキストファイルドロップ処理中フラグ（readSelectionでのパス名挿入を抑制）
    var handlingTextFileDrop: Bool = false

    /// Returns whether this document is plain text
    var isPlainText: Bool {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return false
        }
        return windowController.textDocument?.documentType == .plain
    }

    /// Returns whether substitutions should only apply to rich text
    private var richTextSubstitutionsOnly: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
    }

    /// 英語と日本語の間にスペースを自動挿入するかどうか
    var isSmartSeparationEnglishJapaneseEnabled: Bool = false

    /// mouseDown 中の不要な scrollRangeToVisible を抑制するフラグ
    private var suppressScrollRangeToVisible = false
    /// scrollRangeToVisible の再入防止フラグ（レイアウト中の再帰呼び出しを防止）
    private var isInsideScrollRangeToVisible = false

    /// SmartLanguageSeparation インスタンスへのアクセス
    var smartLanguageSeparation: SmartLanguageSeparation? {
        return (textStorage?.delegate as? FontFallbackRecoveryDelegate)?.smartLanguageSeparation
    }

    /// 同期的にdocumentTypeをRTFDに昇格させる（アラートなし）
    /// readSelection(from:type:)のような同期メソッドから呼ばれる
    /// ドラッグ＆ドロップ時は既にRTFDであるはずだが、念のため昇格を確認する
    func performUpgradeToRTFD() {
        guard let windowController = window?.windowController as? EditorWindowController,
              let document = windowController.textDocument else {
            return
        }

        // すでにRTFDなら何もしない
        if document.documentType == .rtfd {
            return
        }

        // RTFの場合はサイレントに昇格
        if document.documentType == .rtf {
            document.documentType = .rtfd
            document.updateFileTypeFromDocumentType()
            // fileURLをクリアして次回保存時にSave Panelを表示させる（.rtfd拡張子で保存）
            document.fileURL = nil
            document.autosavedContentsFileURL = nil
            NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
        }
    }

    /// 画像挿入時にdocumentTypeをRTFDに昇格させる（必要に応じてアラートを表示）
    /// - Parameter completion: 昇格が完了（または不要）した場合にtrueを渡して呼び出される。キャンセルの場合はfalse。
    func upgradeToRTFDIfNeeded(completion: @escaping (Bool) -> Void) {
        guard let windowController = window?.windowController as? EditorWindowController,
              let document = windowController.textDocument else {
            completion(false)
            return
        }

        // すでにRTFDなら何もしない
        if document.documentType == .rtfd {
            completion(true)
            return
        }

        // RTFの場合はアラートを表示
        guard document.documentType == .rtf else {
            completion(false)
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Convert this document to RTFD format?".localized
        alert.informativeText = "This document contains graphics or attachments and will be saved in RTFD format (RTF with graphics). RTFD documents may not be compatible with some applications. Do you want to convert?".localized
        alert.addButton(withTitle: "Convert".localized)
        alert.addButton(withTitle: "Duplicate".localized)
        alert.addButton(withTitle: "Cancel".localized)

        guard let parentWindow = window else {
            completion(false)
            return
        }

        alert.beginSheetModal(for: parentWindow) { response in
            switch response {
            case .alertFirstButtonReturn:
                // 変換: そのままRTFDに昇格
                document.documentType = .rtfd
                document.updateFileTypeFromDocumentType()
                // fileURLをクリアして次回保存時にSave Panelを表示させる（.rtfd拡張子で保存）
                document.fileURL = nil
                document.autosavedContentsFileURL = nil
                NotificationCenter.default.post(name: Document.documentTypeDidChangeNotification, object: document)
                completion(true)

            case .alertSecondButtonReturn:
                // 複製: 新しいRTFD書類を作成してコンテンツをコピー
                do {
                    guard let newDocument = try NSDocumentController.shared.makeUntitledDocument(ofType: "com.apple.rtfd") as? Document else {
                        completion(false)
                        return
                    }
                    newDocument.applyPresetData(NewDocData.richText)
                    newDocument.documentType = .rtfd
                    newDocument.updateFileTypeFromDocumentType()
                    NSDocumentController.shared.addDocument(newDocument)
                    newDocument.makeWindowControllers()
                    newDocument.showWindows()

                    // 元の書類のコンテンツをコピー
                    newDocument.textStorage.setAttributedString(document.textStorage)

                    completion(true)
                } catch {
                    completion(false)
                }

            default:
                // キャンセル
                completion(false)
            }
        }
    }

    /// 段落スタイル変更前の状態を保持（リスト検出用）
    var previousTextLists: [NSTextList]?

    /// 段落スタイル変更前の状態を保持
    var previousParagraphStyle: NSParagraphStyle?

    // MARK: - Text Replacement with Undo Support

    /// テキストまたは属性付きテキストを指定範囲に置換（Undo/Redo対応）
    /// すべてのテキスト変更はこのメソッドを経由することで、自動的にUndo/Redoがサポートされる
    /// - Parameters:
    ///   - range: 置換する範囲
    ///   - string: 置換するテキスト（String または NSAttributedString）
    func replaceString(in range: NSRange, with string: Any) {
        if let plainString = string as? String {
            if shouldChangeText(in: range, replacementString: plainString) {
                replaceCharacters(in: range, with: plainString)
                didChangeText()
            }
        } else if let attributedString = string as? NSAttributedString {
            if shouldChangeText(in: range, replacementString: attributedString.string) {
                textStorage?.beginEditing()
                textStorage?.replaceCharacters(in: range, with: attributedString)
                textStorage?.endEditing()
                didChangeText()
            }
        }
    }

    /// 指定範囲の属性を変更（Undo/Redo対応）
    /// - Parameters:
    ///   - range: 変更する範囲
    ///   - attributes: 適用する属性の辞書
    func applyAttributes(_ attributes: [NSAttributedString.Key: Any], to range: NSRange) {
        guard let textStorage = textStorage,
              range.length > 0,
              range.location + range.length <= textStorage.length else { return }

        // 現在のテキストを取得して属性を変更
        let currentAttributedString = textStorage.attributedSubstring(from: range)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.addAttributes(attributes, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        replaceString(in: range, with: mutableString)
    }

    /// 指定範囲から属性を削除（Undo/Redo対応）
    /// - Parameters:
    ///   - attributeKey: 削除する属性のキー
    ///   - range: 変更する範囲
    func removeAttribute(_ attributeKey: NSAttributedString.Key, from range: NSRange) {
        guard let textStorage = textStorage,
              range.length > 0,
              range.location + range.length <= textStorage.length else { return }

        // 現在のテキストを取得して属性を削除
        let currentAttributedString = textStorage.attributedSubstring(from: range)
        let mutableString = NSMutableAttributedString(attributedString: currentAttributedString)
        mutableString.removeAttribute(attributeKey, range: NSRange(location: 0, length: mutableString.length))

        // replaceStringを使って置換（Undo対応）
        replaceString(in: range, with: mutableString)
    }

    // MARK: - Drag Source / Destination Operation — See JeditTextView+DragDrop.swift

    // MARK: - Text/RTF File Drop Handling — See JeditTextView+DragDrop.swift

    // MARK: - Attach Files — See JeditTextView+DragDrop.swift

    // MARK: - Continuity Camera — See JeditTextView+DragDrop.swift

    // MARK: - Selection Change

    /// カーソル移動時に typingAttributes をカーソル位置のテキスト属性にリセットする。
    /// applyTextStyle 等でカスタム typingAttributes を設定した後、別の位置に
    /// カーソルを移動してもカスタム属性が持ち越されてしまう問題を防止する。
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)

        // ドラッグ中（stillSelecting）は更新しない
        guard !stillSelecting else { return }

        // リッチテキストのみ対象
        guard isRichText, let textStorage = textStorage, textStorage.length > 0 else { return }

        // 挿入ポイント（選択範囲なし）の場合のみリセット
        guard let firstRange = ranges.first?.rangeValue,
              firstRange.length == 0 else { return }

        // カーソル位置のテキスト属性を取得して typingAttributes に反映
        // カーソルが文末にある場合は直前の文字の属性を使用
        let attrIndex = firstRange.location > 0
            ? firstRange.location - 1
            : firstRange.location
        if attrIndex < textStorage.length {
            var attrs = textStorage.attributes(at: attrIndex, effectiveRange: nil)
            // リンク属性は持ち越さない（リンク文字列の直後でリンクが継続するのを防ぐ）
            attrs.removeValue(forKey: .link)
            typingAttributes = attrs
        }
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        // JEDITANCHOR: リンクのクリック → アンカー位置にジャンプ（Cmd 不要）
        if event.clickCount == 1,
           let anchorID = anchorLinkAtPoint(point) {
            if let document = window?.windowController?.document as? Document {
                document.selectAnchor(identifier: anchorID, registerUndo: true)
            }
            return
        }

        // Cmd+クリックで URL/ファイルパスを開く（Cmd+ドラッグ選択と共存）
        // super.mouseDown() に渡すと不連続選択として消費されるため、
        // リンク位置では自前でマウスをトラッキングしてクリックかドラッグかを判定する。
        if event.modifierFlags.contains(.command),
           event.clickCount == 1,
           urlAtPoint(point) != nil || filePathAtPoint(point) != nil,
           let eventWindow = event.window {

            var didDrag = false
            while let nextEvent = eventWindow.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
                if nextEvent.type == .leftMouseUp { break }
                let dragPoint = convert(nextEvent.locationInWindow, from: nil)
                let dx = dragPoint.x - point.x
                let dy = dragPoint.y - point.y
                if dx * dx + dy * dy >= 9.0 {
                    didDrag = true
                    break
                }
            }

            if didDrag {
                // ドラッグ → super に渡して通常の選択処理
                suppressScrollRangeToVisible = true
                super.mouseDown(with: event)
                suppressScrollRangeToVisible = false
            } else {
                // クリック → URL/ファイルパスを開く
                // URLを先にチェック（filePathAtPoint が URL の一部を誤検出する場合があるため）
                if let url = urlAtPoint(point) {
                    NSWorkspace.shared.open(url)
                } else if let filePath = filePathAtPoint(point) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
                }
            }
            return
        }

        // Check for double-click on an attachment
        if event.clickCount == 2 {
            // アタッチメントがファイルアタッチメント（非画像）の場合は対応アプリで開く
            if let attachment = attachmentAtPoint(point),
               isFileAttachment(attachment) {
                openFileAttachment(attachment)
                return
            }

            // 画像アタッチメントの場合はリサイズパネルを表示
            if let controller = imageResizeController,
               controller.handleClick(in: self, at: point) {
                return
            }
        }

        // Not an attachment double-click, proceed with normal behavior
        // mouseDown 中の不要な自動スクロールを抑制して画面揺れを防止
        suppressScrollRangeToVisible = true
        super.mouseDown(with: event)
        suppressScrollRangeToVisible = false
    }

    override func scrollRangeToVisible(_ range: NSRange) {
        if suppressScrollRangeToVisible { return }
        // レイアウト中の再帰呼び出しを防止（テーブル挿入後のペースト等で
        // calculateStatistics → layout → scrollRangeToVisible → layout の
        // 無限ループが発生する問題を回避）
        if isInsideScrollRangeToVisible { return }

        // rangeの末尾（＝操作後のカーソル位置）が既にvisibleRect内に見えている
        // 場合のみ不要なスクロールを抑制する。NSTextViewのinsertText等が内部的に
        // scrollRangeToVisibleを呼ぶが、カーソルが見えているのに強制スクロールが
        // 発生する問題を防止する。
        // ペースト等でrangeの末尾がウィンドウ外に出る場合はスクロールを実行する。
        if let layoutManager = layoutManager, let textContainer = textContainer {
            let glyphCount = layoutManager.numberOfGlyphs
            let endLocation = min(range.location + range.length, glyphCount)

            var endRect: NSRect
            if endLocation < glyphCount {
                let endGlyphRange = layoutManager.glyphRange(
                    forCharacterRange: NSRange(location: endLocation, length: 0),
                    actualCharacterRange: nil
                )
                endRect = layoutManager.boundingRect(
                    forGlyphRange: endGlyphRange, in: textContainer
                )
            } else {
                // 文書末尾の場合: boundingRectが空rectを返す可能性があるため
                // extraLineFragmentRectを使用してカーソル位置を正確に取得
                endRect = layoutManager.extraLineFragmentRect
            }

            // endRectが有効（非空）な場合のみ可視チェックを行う
            // 空の場合はガードをスキップしてsuper実行（安全側に倒す）
            if !endRect.isEmpty {
                // textContainerOriginを加算してビュー座標に変換
                let endCursorRect = endRect.offsetBy(
                    dx: textContainerOrigin.x,
                    dy: textContainerOrigin.y
                )
                // ズーム時のサブピクセル座標精度問題に対応するため、
                // visibleRectに少しマージンを持たせる
                let marginedVisibleRect = visibleRect.insetBy(dx: -2, dy: -2)
                if marginedVisibleRect.contains(endCursorRect.origin) {
                    return
                }
            }
        }

        isInsideScrollRangeToVisible = true
        super.scrollRangeToVisible(range)
        isInsideScrollRangeToVisible = false
    }

    /// 指定座標にあるNSTextAttachmentを取得
    private func attachmentAtPoint(_ point: NSPoint) -> NSTextAttachment? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0 else {
            return nil
        }

        let textContainerOrigin = textContainerOrigin
        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        return attributes[.attachment] as? NSTextAttachment
    }

    /// 指定座標にある JEDITANCHOR: リンクの UUID を取得する。
    /// ブックマークアンカーへのリンクは通常の URL ではないため、別メソッドで処理する。
    private func anchorLinkAtPoint(_ point: NSPoint) -> String? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0 else {
            return nil
        }

        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        if let link = attributes[.link] {
            // link 属性値は String / URL / NSURL のいずれかになりうる
            let linkString: String?
            if let str = link as? String {
                linkString = str
            } else if let url = link as? URL {
                linkString = url.absoluteString
            } else if let url = link as? NSURL {
                linkString = url.absoluteString
            } else {
                linkString = nil
            }
            if let str = linkString, str.hasPrefix("JEDITANCHOR:") {
                return str
            }
        }
        return nil
    }

    /// 指定座標にあるURLを取得（.link属性またはベアURL検出）
    private func urlAtPoint(_ point: NSPoint) -> URL? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0 else {
            return nil
        }

        let textContainerOrigin = textContainerOrigin
        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        // 1. .link属性があればそれを使う（Markdownリンクなど）
        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        if let link = attributes[.link] {
            if let url = link as? URL {
                return url
            } else if let urlString = link as? String, let url = URL(string: urlString) {
                return url
            }
        }

        // 2. テキストからベアURLを検出
        let string = textStorage.string as NSString
        // クリック位置を含む行の範囲を取得
        let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineString = string.substring(with: lineRange)

        // URLパターンで検索
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: lineString, range: NSRange(location: 0, length: lineString.utf16.count))

        // クリック位置がURL範囲内にあるかチェック
        let charOffsetInLine = charIndex - lineRange.location
        for match in matches {
            if match.range.contains(charOffsetInLine), let url = match.url {
                return url
            }
        }

        return nil
    }

    /// 指定座標にあるファイルパスを取得（絶対パスまたは~/パス）
    private func filePathAtPoint(_ point: NSPoint) -> String? {
        guard let layoutManager = layoutManager,
              let textContainer = textContainer,
              let textStorage = textStorage,
              textStorage.length > 0 else {
            return nil
        }

        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < textStorage.length else { return nil }

        let nsString = textStorage.string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
        let lineString = nsString.substring(with: lineRange)
        let charOffsetInLine = charIndex - lineRange.location

        // パスの正規表現: ~/... または /... で始まり、引用符・制御文字などで終わる
        // スペースを含む macOS パスに対応するため、空白は区切りに含めない
        // U+FFFC（Object Replacement Character: 画像アタッチメント）も除外
        let pattern = "(?:~/|/)[^\"'<>|;\\t\\n\\r\u{FFFC}]+"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: lineString, range: NSRange(location: 0, length: lineString.utf16.count))

        for match in matches {
            guard match.range.contains(charOffsetInLine) else { continue }

            var pathString = (lineString as NSString).substring(with: match.range)

            // 末尾の空白・句読点を除去
            while let last = pathString.last, ".,;:!?)]} \t".contains(last) {
                pathString = String(pathString.dropLast())
            }

            // クリック位置がトリム後のパス範囲内かチェック
            let pathStartInLine = match.range.location
            let pathLengthUtf16 = (pathString as NSString).length
            guard charOffsetInLine >= pathStartInLine,
                  charOffsetInLine < pathStartInLine + pathLengthUtf16 else {
                continue
            }

            // チルダ展開（サンドボックスアプリでは expandingTildeInPath がコンテナパスに
            // 展開されるため、実際のホームディレクトリを使う）
            let expanded = expandTilde(in: pathString)

            // ファイルの存在を確認できればそのパスを返す
            if let resolved = resolveExistingPath(expanded) {
                return resolved
            }

            // スペースを含むパスが誤って長くマッチした場合 → 末尾をスペース単位で削る
            var candidate = pathString
            var found = false
            while let spaceRange = candidate.range(of: " ", options: .backwards) {
                candidate = String(candidate[..<spaceRange.lowerBound])
                let candidateLengthUtf16 = (candidate as NSString).length
                // クリック位置が候補パスの範囲外になったら終了
                guard charOffsetInLine < pathStartInLine + candidateLengthUtf16 else { break }

                let expandedCandidate = expandTilde(in: candidate)
                if let resolved = resolveExistingPath(expandedCandidate) {
                    found = true
                    return resolved
                }
            }

            // サンドボックスで fileExists が制限される場合があるため、
            // 存在確認できなくてもパスパターンに合致すれば返す
            // （Finder 側でファイルの有無を処理する）
            if !found {
                return expanded
            }
        }

        return nil
    }

    /// チルダをサンドボックスの影響を受けない実際のホームディレクトリに展開する。
    /// expandingTildeInPath はサンドボックスコンテナに展開されてしまうため使用しない。
    private func expandTilde(in path: String) -> String {
        guard path.hasPrefix("~/") else { return path }
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return String(cString: dir) + String(path.dropFirst(1))
        }
        return (path as NSString).expandingTildeInPath
    }

    /// パスの存在を確認する。Unicode 正規化（NFC/NFD）の違いも考慮し、
    /// ファイルが見つからない場合は親ディレクトリの存在もチェックする。
    private func resolveExistingPath(_ path: String) -> String? {
        let fm = FileManager.default

        // そのままのパスで確認
        if fm.fileExists(atPath: path) {
            return path
        }
        // Unicode NFC（合成済み）で再試行
        let nfc = path.precomposedStringWithCanonicalMapping
        if nfc != path, fm.fileExists(atPath: nfc) {
            return nfc
        }
        // Unicode NFD（分解済み）で再試行
        let nfd = path.decomposedStringWithCanonicalMapping
        if nfd != path, nfd != nfc, fm.fileExists(atPath: nfd) {
            return nfd
        }
        // ファイルが見つからないが祖先ディレクトリが存在する場合はパスを返す
        // （サンドボックスにより fileExists が false を返す場合への対策）
        var ancestor = (path as NSString).deletingLastPathComponent
        while !ancestor.isEmpty, ancestor != "/" {
            if fm.fileExists(atPath: ancestor) {
                return path
            }
            ancestor = (ancestor as NSString).deletingLastPathComponent
        }

        return nil
    }

    /// アタッチメントがファイルアタッチメント（非画像）かどうかを判定
    /// 画像拡張子を持つファイルは画像アタッチメントとして扱う
    private func isFileAttachment(_ attachment: NSTextAttachment) -> Bool {
        guard let fileWrapper = attachment.fileWrapper,
              let filename = fileWrapper.preferredFilename ?? fileWrapper.filename else {
            return false
        }

        // 画像拡張子の場合は画像アタッチメント（リサイズ対象）
        let ext = (filename as NSString).pathExtension.lowercased()
        let imageExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "tiff", "tif", "bmp", "ico", "heic", "heif", "webp", "svg"
        ]
        if imageExtensions.contains(ext) {
            return false  // 画像アタッチメント
        }

        // ファイルラッパーがディレクトリの場合もファイルアタッチメント
        // 拡張子が画像でない場合はファイルアタッチメント
        return true
    }

    /// ファイルアタッチメントを対応アプリで開く
    private func openFileAttachment(_ attachment: NSTextAttachment) {
        guard let fileWrapper = attachment.fileWrapper else { return }

        // 一時ディレクトリにファイルを書き出してから開く
        let tempDir = FileManager.default.temporaryDirectory
        let filename = fileWrapper.preferredFilename ?? fileWrapper.filename ?? "attachment"
        let tempURL = tempDir.appendingPathComponent(filename)

        do {
            // 既存ファイルがあれば削除
            if FileManager.default.fileExists(atPath: tempURL.path) {
                try FileManager.default.removeItem(at: tempURL)
            }
            try fileWrapper.write(to: tempURL, options: .atomic, originalContentsURL: nil)
            NSWorkspace.shared.open(tempURL)
        } catch {
            NSSound.beep()
        }
    }

    // MARK: - Link Panel

    /// カスタムリンクパネルを表示する（Format > Link… メニューから呼び出される）
    @objc func showLinkPanel(_ sender: Any?) {
        LinkPanelController.shared.showPanel()
    }

    // MARK: - Context Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let defaults = UserDefaults.standard
        let showDefaultMenu = !defaults.bool(forKey: UserDefaults.Keys.dontShowContextMenuDefaultItems)
        let hiddenActions = Set(defaults.stringArray(forKey: UserDefaults.Keys.hiddenContextMenuActions) ?? [])

        // デフォルトメニューまたは空メニュー
        let menu: NSMenu
        if showDefaultMenu {
            guard let defaultMenu = super.menu(for: event) else { return nil }
            menu = defaultMenu
        } else {
            menu = NSMenu()
        }

        // Jedit カスタム項目: Change Image Size（動画は自動伸縮するため対象外）
        if !hiddenActions.contains("changeImageSize:"),
           let layoutManager = layoutManager,
           let textContainer = textContainer,
           let textStorage = textStorage,
           textStorage.length > 0 {
            let point = convert(event.locationInWindow, from: nil)
            let textContainerOrigin = textContainerOrigin
            let locationInContainer = NSPoint(
                x: point.x - textContainerOrigin.x,
                y: point.y - textContainerOrigin.y
            )
            var fraction: CGFloat = 0
            let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

            if charIndex < textStorage.length,
               let controller = imageResizeController,
               let attachmentInfo = controller.getImageAttachment(in: self, at: charIndex),
               !controller.isVideo(attachment: attachmentInfo.attachment) {
                contextMenuImageCharIndex = charIndex
                let changeImageSizeItem = NSMenuItem(
                    title: "Change Image Size...".localized,
                    action: #selector(changeImageSize(_:)),
                    keyEquivalent: ""
                )
                changeImageSizeItem.target = self
                menu.insertItem(changeImageSizeItem, at: 0)
                if menu.items.count > 1 {
                    menu.insertItem(NSMenuItem.separator(), at: 1)
                }
            }
        }

        // Jedit カスタム項目: Styles サブメニュー
        if !isPlainText && !hiddenActions.contains("submenu:styles") {
            if menu.items.count > 0 {
                menu.addItem(.separator())
            }
            let stylesItem = StyleMenuManager.shared.createContextStylesMenuItem()
            menu.addItem(stylesItem)
        }

        // Jedit カスタム項目: スタイルとルーラーをコピー / ペースト
        if !isPlainText && !hiddenActions.contains("copyStyleAndRuler:") {
            if menu.items.count > 0 {
                menu.addItem(.separator())
            }
            let copyItem = NSMenuItem(
                title: "Copy Style and Ruler".localized,
                action: #selector(copyStyleAndRuler(_:)),
                keyEquivalent: ""
            )
            copyItem.target = nil  // responder chain
            menu.addItem(copyItem)

            if !hiddenActions.contains("pasteStyleAndRuler:") {
                let pasteItem = NSMenuItem(
                    title: "Paste Style and Ruler".localized,
                    action: #selector(pasteStyleAndRuler(_:)),
                    keyEquivalent: ""
                )
                pasteItem.target = nil  // responder chain
                menu.addItem(pasteItem)
            }
        } else if !isPlainText && !hiddenActions.contains("pasteStyleAndRuler:") {
            if menu.items.count > 0 {
                menu.addItem(.separator())
            }
            let pasteItem = NSMenuItem(
                title: "Paste Style and Ruler".localized,
                action: #selector(pasteStyleAndRuler(_:)),
                keyEquivalent: ""
            )
            pasteItem.target = nil  // responder chain
            menu.addItem(pasteItem)
        }

        // デフォルトメニュー項目の個別フィルタリング
        if showDefaultMenu {
            filterContextMenu(menu, hiddenActions: hiddenActions)
        }

        cleanupSeparators(in: menu)
        return menu
    }

    /// デフォルトメニュー項目を個別にフィルタリング
    private func filterContextMenu(_ menu: NSMenu, hiddenActions: Set<String>) {
        guard !hiddenActions.isEmpty else { return }

        let itemsToRemove = menu.items.filter { item in
            guard !item.isSeparatorItem else { return false }
            let identifier = ContextMenuPreferencesViewController.identifierForMenuItem(item)
            return hiddenActions.contains(identifier)
        }
        for item in itemsToRemove {
            menu.removeItem(item)
        }
    }

    /// メニュー内の余分なセパレータを除去
    private func cleanupSeparators(in menu: NSMenu) {
        // 先頭のセパレータを除去
        while let first = menu.items.first, first.isSeparatorItem {
            menu.removeItem(first)
        }
        // 末尾のセパレータを除去
        while let last = menu.items.last, last.isSeparatorItem {
            menu.removeItem(last)
        }
        // 連続するセパレータを除去
        var i = 0
        while i < menu.items.count - 1 {
            if menu.items[i].isSeparatorItem && menu.items[i + 1].isSeparatorItem {
                menu.removeItem(at: i + 1)
            } else {
                i += 1
            }
        }
    }

    /// Action for "Copy Style and Ruler" context menu item
    @objc func copyStyleAndRuler(_ sender: Any?) {
        copyFont(sender)
        copyRuler(sender)
    }

    /// Action for "Paste Style and Ruler" context menu item
    @objc func pasteStyleAndRuler(_ sender: Any?) {
        pasteFont(sender)
        pasteRuler(sender)
    }

    /// Action for "Change Image Size..." context menu item
    @objc private func changeImageSize(_ sender: Any?) {
        guard let charIndex = contextMenuImageCharIndex,
              let controller = imageResizeController else {
            return
        }

        controller.showResizePanelForAttachment(in: self, at: charIndex)
        contextMenuImageCharIndex = nil
    }

    // MARK: - Spelling and Grammar Menu Actions

    @IBAction override func toggleContinuousSpellChecking(_ sender: Any?) {
        super.toggleContinuousSpellChecking(sender)
        UserDefaults.standard.set(isContinuousSpellCheckingEnabled, forKey: UserDefaults.Keys.checkSpellingAsYouType)
    }

    @IBAction override func toggleGrammarChecking(_ sender: Any?) {
        super.toggleGrammarChecking(sender)
        UserDefaults.standard.set(isGrammarCheckingEnabled, forKey: UserDefaults.Keys.checkGrammarWithSpelling)
    }

    @IBAction override func toggleAutomaticSpellingCorrection(_ sender: Any?) {
        super.toggleAutomaticSpellingCorrection(sender)
        UserDefaults.standard.set(isAutomaticSpellingCorrectionEnabled, forKey: UserDefaults.Keys.correctSpellingAutomatically)
    }

    // MARK: - Substitutions Menu Actions

    @IBAction override func toggleSmartInsertDelete(_ sender: Any?) {
        super.toggleSmartInsertDelete(sender)
        UserDefaults.standard.set(smartInsertDeleteEnabled, forKey: UserDefaults.Keys.smartCopyPaste)
    }

    @IBAction override func toggleAutomaticQuoteSubstitution(_ sender: Any?) {
        super.toggleAutomaticQuoteSubstitution(sender)
        UserDefaults.standard.set(isAutomaticQuoteSubstitutionEnabled, forKey: UserDefaults.Keys.smartQuotes)
    }

    @IBAction override func toggleAutomaticDashSubstitution(_ sender: Any?) {
        super.toggleAutomaticDashSubstitution(sender)
        UserDefaults.standard.set(isAutomaticDashSubstitutionEnabled, forKey: UserDefaults.Keys.smartDashes)
    }

    @IBAction override func toggleAutomaticLinkDetection(_ sender: Any?) {
        super.toggleAutomaticLinkDetection(sender)
        UserDefaults.standard.set(isAutomaticLinkDetectionEnabled, forKey: UserDefaults.Keys.smartLinks)
    }

    @IBAction override func toggleAutomaticDataDetection(_ sender: Any?) {
        super.toggleAutomaticDataDetection(sender)
        UserDefaults.standard.set(isAutomaticDataDetectionEnabled, forKey: UserDefaults.Keys.dataDetectors)
    }

    @IBAction override func toggleAutomaticTextReplacement(_ sender: Any?) {
        super.toggleAutomaticTextReplacement(sender)
        UserDefaults.standard.set(isAutomaticTextReplacementEnabled, forKey: UserDefaults.Keys.textReplacements)
    }

    @IBAction func toggleSmartSeparationEnglishJapanese(_ sender: Any?) {
        isSmartSeparationEnglishJapaneseEnabled.toggle()
        UserDefaults.standard.set(isSmartSeparationEnglishJapaneseEnabled, forKey: UserDefaults.Keys.smartSeparationEnglishJapanese)
    }

    // MARK: - Stamp Date/Time Actions

    @IBAction func stampDate(_ sender: Any?) {
        let dateFormatType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.dateFormatType)
        guard let formatType = CalendarDateHelper.DateFormatType(rawValue: dateFormatType) else { return }
        let dateString = formatType.formattedDate()
        insertText(dateString, replacementRange: selectedRange())
    }

    @IBAction func stampTime(_ sender: Any?) {
        let timeFormatType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.timeFormatType)
        guard let formatType = CalendarDateHelper.TimeFormatType(rawValue: timeFormatType) else { return }
        let timeString = formatType.formattedTime()
        insertText(timeString, replacementRange: selectedRange())
    }

    // MARK: - Font Panel Support — See JeditTextView+Styling.swift

    // MARK: - Kern Support — See JeditTextView+Styling.swift

    // MARK: - Ligature Support — See JeditTextView+Styling.swift

    // MARK: - Text Alignment Support — See JeditTextView+Styling.swift

    // MARK: - Paragraph Style Support (Inspector Bar) — See JeditTextView+Styling.swift

    // MARK: - Character Color Support — See JeditTextView+Styling.swift

    // MARK: - Plain Text Attribute Change Support — See JeditTextView+Styling.swift

    // MARK: - Tab Handling / Indent — See JeditTextView+Indent.swift

    // MARK: - Auto Indent — See JeditTextView+Indent.swift

    // MARK: - Ruler Update Safety

    /// ルーラー更新をオーバーライドして空のtextStorageでのクラッシュを防ぐ
    /// プレーンテキストの場合はアクセサリビュー（段落スタイルコントロール）を非表示にする
    override func updateRuler() {
        // 再入防止
        guard !isUpdatingRuler else { return }
        isUpdatingRuler = true
        defer { isUpdatingRuler = false }

        // ウィンドウが閉じようとしている場合はスキップ
        guard let window = window else { return }

        // textStorageが空または無効な場合はルーラー更新をスキップ
        guard let textStorage = textStorage,
              textStorage.length > 0 else {
            return
        }
        super.updateRuler()

        // プレーンテキストの場合はルーラーのアクセサリビューを非表示にする
        // ウィンドウが表示中かつウィンドウコントローラーにアクセス可能な場合のみ
        if window.isVisible,
           let windowController = window.windowController as? EditorWindowController,
           windowController.textDocument?.documentType == .plain {
            if let scrollView = enclosingScrollView {
                if let horizontalRuler = scrollView.horizontalRulerView,
                   horizontalRuler.accessoryView != nil {
                    horizontalRuler.accessoryView = nil
                    horizontalRuler.reservedThicknessForAccessoryView = 0
                }
                if let verticalRuler = scrollView.verticalRulerView,
                   verticalRuler.accessoryView != nil {
                    verticalRuler.accessoryView = nil
                    verticalRuler.reservedThicknessForAccessoryView = 0
                }
            }
        }
    }

    // MARK: - Paste and Drop Text Conversion — See JeditTextView+DragDrop.swift

    // MARK: - Menu Validation

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

        // スタイルメニュー項目のバリデーション
        if action == #selector(applyTextStyle(_:)) {
            return !isPlainText
        }

        // Set paperclip image for Attach Files menu item
        if action == #selector(attachFile(_:)), menuItem.image == nil {
            if let image = NSImage(systemSymbolName: "paperclip", accessibilityDescription: "Attach Files") {
                image.size = NSSize(width: 16, height: 16)
                menuItem.image = image
            }
        }

        // Baseline submenu actions, Character colors, and Attach Files are disabled for plain text
        // (These attributes are not meaningful in plain text documents)
        if isPlainText {
            // Note: subscript is a Swift keyword, so we use NSSelectorFromString
            let subscriptSelector = NSSelectorFromString("subscript:")
            switch action {
            case #selector(raiseBaseline(_:)),
                 #selector(lowerBaseline(_:)),
                 #selector(superscript(_:)),
                 #selector(unscript(_:)),
                 subscriptSelector,
                 #selector(changeForeColor(_:)),
                 #selector(orderFrontForeColorPanel(_:)),
                 #selector(changeBackColor(_:)),
                 #selector(orderFrontBackColorPanel(_:)),
                 #selector(attachFile(_:)):
                return false
            default:
                break
            }
        }

        // Substitution actions that respect "Rich Text Only" setting
        // When "Following Substitutions Enabled Only in Rich Text" is ON and this is plain text,
        // show these items as unchecked (but still enabled)
        if richTextSubstitutionsOnly && isPlainText {
            switch action {
            case #selector(toggleAutomaticQuoteSubstitution(_:)),
                 #selector(toggleAutomaticDashSubstitution(_:)),
                 #selector(toggleAutomaticTextReplacement(_:)),
                 #selector(toggleAutomaticSpellingCorrection(_:)):
                menuItem.state = .off
                return true
            default:
                break
            }
        }

        // Smart Separation のチェックマーク制御
        if action == #selector(toggleSmartSeparationEnglishJapanese(_:)) {
            menuItem.state = isSmartSeparationEnglishJapaneseEnabled ? .on : .off
            return true
        }

        // リッチテキスト書類でクリップボードに画像がある場合、Pasteを有効化
        if action == #selector(paste(_:)) {
            if !isPlainText {
                let pasteboard = NSPasteboard.general
                if pasteboard.availableType(from: [.tiff, .png]) != nil {
                    return true
                }
            }
        }

        return super.validateMenuItem(menuItem)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        // リッチテキスト書類でクリップボードに画像がある場合、Pasteを有効化
        if item.action == #selector(paste(_:)) {
            if !isPlainText {
                let pasteboard = NSPasteboard.general
                if pasteboard.availableType(from: [.tiff, .png]) != nil {
                    return true
                }
            }
        }

        return super.validateUserInterfaceItem(item)
    }

    // MARK: - Style Menu Actions — See JeditTextView+Styling.swift

    // MARK: - Tag Jump (検索結果ファイルからのジャンプ)

    /// 検索結果保存ファイルのリンクをクリックした時、URL の fragment に
    /// 埋め込まれた `loc=N&len=N` を読み取り、ファイルを開いてその位置へ
    /// ジャンプする。fragment が無いリンクは super に委譲する。
    override func clicked(onLink link: Any, at charIndex: Int) {
        if let url = resolveLinkURL(link),
           url.isFileURL,
           let range = parseTagJumpFragment(in: url) {
            let cleanURL = stripFragment(from: url)
            performTagJump(to: cleanURL, selecting: range)
            return
        }
        super.clicked(onLink: link, at: charIndex)
    }

    /// .link の値（URL or String）から URL を取り出す。
    private func resolveLinkURL(_ link: Any) -> URL? {
        if let url = link as? URL { return url }
        if let s = link as? String { return URL(string: s) }
        return nil
    }

    /// URL の fragment から `loc=N&len=N` を抽出して NSRange を返す。
    private func parseTagJumpFragment(in url: URL) -> NSRange? {
        guard let frag = url.fragment, !frag.isEmpty else { return nil }
        var loc: Int?
        var len: Int?
        for kv in frag.split(separator: "&") {
            let parts = kv.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            switch parts[0] {
            case "loc": loc = Int(parts[1])
            case "len": len = Int(parts[1])
            default: break
            }
        }
        guard let l = loc, let n = len, l >= 0, n >= 0 else { return nil }
        return NSRange(location: l, length: n)
    }

    /// fragment を取り除いた URL を返す。
    private func stripFragment(from url: URL) -> URL {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.fragment = nil
        return comps?.url ?? url
    }

    /// ファイルを開いて指定範囲を選択・スクロールする。
    /// 初回オープン時は textStorage のロード完了を待ってから選択を反映する。
    private func performTagJump(to url: URL, selecting range: NSRange) {
        NSDocumentController.shared.openDocument(
            withContentsOf: url, display: true
        ) { document, _, error in
            guard error == nil, let document = document else {
                NSSound.beep()
                return
            }
            guard let editor = document.windowControllers.first(
                where: { $0 is EditorWindowController }
            ) as? EditorWindowController else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak editor] in
                editor?.restoreSelectionAndScrollToVisible(range, delay: 0)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
