//
//  ImageClickableTextView.swift
//  Jedit-open
//
//  Custom NSTextView subclass that detects clicks on image attachments
//

import Cocoa

// MARK: - ImageClickableTextView

class ImageClickableTextView: NSTextView {

    // MARK: - Properties

    /// Controller for handling image resize operations
    var imageResizeController: ImageResizeController?

    /// Returns whether this document is plain text
    private var isPlainText: Bool {
        guard let windowController = window?.windowController as? EditorWindowController else {
            return false
        }
        return windowController.textDocument?.documentType == .plain
    }

    /// Returns whether substitutions should only apply to rich text
    private var richTextSubstitutionsOnly: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaults.Keys.richTextSubstitutionsEnabled)
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Check if we clicked on an image attachment
        let point = convert(event.locationInWindow, from: nil)

        if let controller = imageResizeController,
           controller.handleClick(in: self, at: point) {
            // Image was clicked, panel is shown, don't pass the event
            return
        }

        // Not an image click, proceed with normal behavior
        super.mouseDown(with: event)
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

    // MARK: - Font Panel Support

    /// フォントパネルからのフォント変更を処理
    /// Format > Font メニューやインスペクターバーからのフォント変更に対応
    @objc override func changeFont(_ sender: Any?) {
        // BasicFontPanelController がアクティブな場合は処理をスキップ
        // （Basic Font パネルは独自に処理する）
        if BasicFontPanelController.shared.isFontPanelActive {
            return
        }

        // NSTextView のデフォルト実装を使用
        // これにより Undo/Redo も自動的にサポートされる
        super.changeFont(sender)
    }

    // MARK: - Tab Handling

    /// タブキーが押されたときの処理
    /// タブ幅の単位が "spaces" の場合はスペース文字を挿入
    override func insertTab(_ sender: Any?) {
        guard let windowController = window?.windowController as? EditorWindowController,
              let presetData = windowController.textDocument?.presetData else {
            super.insertTab(sender)
            return
        }

        let tabUnit = presetData.format.tabWidthUnit

        if tabUnit == .spaces {
            // スペースモード: 指定された数のスペース文字を挿入
            let spaceCount = Int(presetData.format.tabWidthPoints)
            let spaces = String(repeating: " ", count: max(1, spaceCount))
            insertText(spaces, replacementRange: selectedRange())
        } else {
            // ポイントモード: 通常のタブ文字を挿入
            super.insertTab(sender)
        }
    }

    // MARK: - Auto Indent

    /// 改行が挿入されたときの処理
    /// Auto Indent が有効な場合、現在の行の先頭の空白文字を新しい行にコピー
    /// プレーンテキストで Wrapped Line Indent が有効な場合、パラグラフスタイルも設定
    override func insertNewline(_ sender: Any?) {
        guard let windowController = window?.windowController as? EditorWindowController,
              let presetData = windowController.textDocument?.presetData,
              presetData.format.autoIndent else {
            // Auto Indent が無効な場合は通常の改行
            super.insertNewline(sender)
            return
        }

        // 現在のカーソル位置を取得
        let currentRange = selectedRange()

        // 現在の行の先頭のインデント文字列を取得
        let indentString = getLeadingIndent(at: currentRange.location)

        // 改行 + インデント文字列を挿入
        let newlineWithIndent = "\n" + indentString
        insertText(newlineWithIndent, replacementRange: currentRange)

        // プレーンテキストの場合のみ Wrapped Line Indent のパラグラフスタイルを適用
        if isPlainText {
            applyWrappedLineIndentStyle(
                indentString: indentString,
                presetData: presetData
            )
        }
    }

    /// Wrapped Line Indent のパラグラフスタイルを新しい行に適用（プレーンテキスト専用）
    /// - Parameters:
    ///   - indentString: Auto Indent でコピーされた空白文字列
    ///   - presetData: ドキュメントのプリセットデータ
    private func applyWrappedLineIndentStyle(indentString: String, presetData: NewDocData) {
        guard let textStorage = textStorage else { return }

        // 現在のカーソル位置（改行 + インデント挿入後）
        let cursorLocation = selectedRange().location

        // 新しい行の開始位置を計算（カーソル位置 - インデント文字列の長さ）
        let newLineStart = cursorLocation - indentString.count

        // 新しい行のパラグラフ範囲を取得
        let paragraphRange = (textStorage.string as NSString).paragraphRange(for: NSRange(location: newLineStart, length: 0))

        // インデント文字列の幅をポイントで計算
        let indentWidth = calculateIndentWidth(indentString: indentString, presetData: presetData)

        // 現在のパラグラフスタイルを取得または新規作成
        let existingStyle = textStorage.attribute(.paragraphStyle, at: newLineStart, effectiveRange: nil) as? NSParagraphStyle
        let newStyle = (existingStyle?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()

        if presetData.format.indentWrappedLines {
            // Wrapped Line Indent がオンの場合
            // firstLineHeadIndent = 0
            // headIndent = インデント幅 + wrappedLineIndent
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = indentWidth + presetData.format.wrappedLineIndent
        } else {
            // Wrapped Line Indent がオフの場合
            // firstLineHeadIndent = 0
            // headIndent = 0
            newStyle.firstLineHeadIndent = 0
            newStyle.headIndent = 0
        }

        // パラグラフスタイルを適用
        textStorage.addAttribute(.paragraphStyle, value: newStyle, range: paragraphRange)
    }

    /// インデント文字列の幅をポイントで計算
    /// - Parameters:
    ///   - indentString: 空白文字列（タブ、半角スペース、全角スペース）
    ///   - presetData: ドキュメントのプリセットデータ
    /// - Returns: インデント幅（ポイント）
    private func calculateIndentWidth(indentString: String, presetData: NewDocData) -> CGFloat {
        var totalWidth: CGFloat = 0

        // フォントを取得
        let font = NSFont(name: presetData.fontAndColors.baseFontName, size: presetData.fontAndColors.baseFontSize)
            ?? NSFont.systemFont(ofSize: presetData.fontAndColors.baseFontSize)

        // タブ幅を取得
        let tabWidth: CGFloat
        if presetData.format.tabWidthUnit == .spaces {
            // スペースモードの場合、スペースの幅 × スペース数
            let spaceWidth = " ".size(withAttributes: [.font: font]).width
            tabWidth = spaceWidth * presetData.format.tabWidthPoints
        } else {
            // ポイントモードの場合、直接ポイント数を使用
            tabWidth = presetData.format.tabWidthPoints
        }

        // 各文字の幅を計算
        for char in indentString {
            switch char {
            case "\t":
                // タブ文字
                totalWidth += tabWidth
            case " ":
                // 半角スペース
                let spaceWidth = " ".size(withAttributes: [.font: font]).width
                totalWidth += spaceWidth
            case "\u{3000}":
                // 全角スペース
                let fullWidthSpaceWidth = "　".size(withAttributes: [.font: font]).width
                totalWidth += fullWidthSpaceWidth
            default:
                break
            }
        }

        return totalWidth
    }

    /// 指定位置の行の先頭にある空白文字（タブ、半角スペース、全角スペース）を取得
    /// - Parameter location: テキスト内の位置
    /// - Returns: 行の先頭の空白文字列
    private func getLeadingIndent(at location: Int) -> String {
        guard let textStorage = textStorage else { return "" }
        let text = textStorage.string as NSString

        // 現在位置から行の先頭を探す
        var lineStart = location
        while lineStart > 0 {
            let prevChar = text.character(at: lineStart - 1)
            // 改行文字（\n, \r）を見つけたらそこで止める
            if prevChar == 0x0A || prevChar == 0x0D {
                break
            }
            lineStart -= 1
        }

        // 行の先頭から空白文字を収集
        var indentString = ""
        var pos = lineStart
        while pos < text.length && pos < location {
            let char = text.character(at: pos)
            // タブ (0x09), 半角スペース (0x20), 全角スペース (0x3000)
            if char == 0x09 || char == 0x20 || char == 0x3000 {
                indentString.append(Character(UnicodeScalar(char)!))
                pos += 1
            } else {
                // 空白以外の文字が出現したら終了
                break
            }
        }

        return indentString
    }

    // MARK: - Ruler Update Safety

    /// ルーラー更新をオーバーライドして空のtextStorageでのクラッシュを防ぐ
    override func updateRuler() {
        // textStorageが空または無効な場合はルーラー更新をスキップ
        guard let textStorage = textStorage,
              textStorage.length > 0 else {
            return
        }
        super.updateRuler()
    }

    // MARK: - Menu Validation

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action

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

        return super.validateMenuItem(menuItem)
    }
}
