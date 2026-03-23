//
//  MarkdownParser.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/13.
//

import Cocoa

/// Markdown テキストを NSAttributedString に変換するパーサー
enum MarkdownParser {

    // MARK: - Custom Attribute Keys

    /// Markdown のブロックタイプを NSAttributedString に埋め込むためのカスタム属性キー
    /// 逆変換（markdownString(from:)）で正確にブロックタイプを判定するために使用
    static let markdownBlockTypeKey = NSAttributedString.Key("jp.co.artman21.Jedit.markdownBlockType")

    /// インラインコードの背景色（LayoutManager でテキスト高さに合わせて描画するため、
    /// .backgroundColor ではなくカスタム属性を使用する）
    static let inlineCodeBackgroundKey = NSAttributedString.Key("jp.co.artman21.Jedit.inlineCodeBackground")

    /// リモート画像のURL（非同期読み込み用）
    static let remoteImageURLKey = NSAttributedString.Key("jp.co.artman21.Jedit.remoteImageURL")

    /// リモート画像の表示サイズ（非同期読み込み用）
    static let remoteImageSizeKey = NSAttributedString.Key("jp.co.artman21.Jedit.remoteImageSize")

    /// 画像の元ソース（逆変換用：<img>タグ全体 または ![alt](url) 形式の文字列）
    static let imageSourceKey = NSAttributedString.Key("jp.co.artman21.Jedit.imageSource")

    /// リモート画像キャッシュ
    private static let imageCache = NSCache<NSURL, NSImage>()

    /// ブロックタイプの値（カスタム属性に設定する文字列）
    private enum MarkdownBlockValue {
        static let heading1 = "h1"
        static let heading2 = "h2"
        static let heading3 = "h3"
        static let heading4 = "h4"
        static let heading5 = "h5"
        static let heading6 = "h6"
        static let paragraph = "p"
        static let codeBlock = "code"
        static let blockquote = "blockquote"
        static let unorderedList = "ul"
        static let orderedList = "ol"
        static let horizontalRule = "hr"
        static let tableHeader = "th"
        static let tableSeparator = "table-sep"
        static let tableRow = "td"
    }

    // MARK: - Styling Constants

    private static let baseFontSize: CGFloat = 14.0
    private static let headingFontSizes: [CGFloat] = [28, 24, 20, 17, 15, 13]  // H1-H6
    private static let codeFontSize: CGFloat = 12.0
    private static let listIndent: CGFloat = 24.0
    private static let blockquoteIndent: CGFloat = 20.0
    private static let lineSpacingAmount: CGFloat = baseFontSize * 0.8

    private static var baseFont: NSFont {
        NSFont.systemFont(ofSize: baseFontSize)
    }

    private static var boldFont: NSFont {
        NSFont.boldSystemFont(ofSize: baseFontSize)
    }

    private static var codeFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
    }

    private static var codeBackgroundColor: NSColor {
        NSColor(calibratedWhite: 0.93, alpha: 1.0)
    }

    private static var blockquoteColor: NSColor {
        NSColor.secondaryLabelColor
    }

    private static var horizontalRuleColor: NSColor {
        NSColor(calibratedWhite: 0.7, alpha: 1.0)
    }

    // MARK: - Escape Sequence Placeholders

    /// バックスラッシュエスケープ用のプレースホルダー（U+E000-U+E0FF Private Use Area）
    private static let escapableCharacters: [(character: String, placeholder: String)] = [
        ("\\", "\u{E000}"),
        ("`", "\u{E001}"),
        ("*", "\u{E002}"),
        ("_", "\u{E003}"),
        ("{", "\u{E004}"),
        ("}", "\u{E005}"),
        ("[", "\u{E006}"),
        ("]", "\u{E007}"),
        ("(", "\u{E008}"),
        (")", "\u{E009}"),
        ("#", "\u{E00A}"),
        ("+", "\u{E00B}"),
        ("-", "\u{E00C}"),
        (".", "\u{E00D}"),
        ("!", "\u{E00E}"),
        ("|", "\u{E00F}"),
        ("~", "\u{E010}"),
        (">", "\u{E011}"),
    ]

    // MARK: - Reference Link Storage

    /// 参照リンク定義を格納する型
    private struct ReferenceLinkDefinition {
        let url: String
        let title: String?
    }

    // MARK: - Block Types

    private enum BlockType {
        case heading(level: Int, text: String)
        case paragraph(lines: [String])
        case codeBlock(language: String?, lines: [String])
        case blockquote(level: Int, lines: [String])
        case unorderedList(items: [ListItem])
        case orderedList(items: [ListItem])
        case horizontalRule
        case table(rows: [[String]], hasHeader: Bool)
        case emptyLine
    }

    private struct ListItem {
        let text: String
        let indentLevel: Int
        let isTask: Bool
        let isChecked: Bool
        let isOrdered: Bool
        let number: Int
    }

    // MARK: - Public API

    /// Markdown テキストを NSAttributedString に変換
    /// - Parameters:
    ///   - markdownText: Markdown テキスト
    ///   - baseURL: 相対パスの画像解決用ベースURL（オプション）
    /// - Returns: 変換された NSAttributedString
    static func attributedString(from markdownText: String, baseURL: URL? = nil) -> NSAttributedString {
        // Pre-pass: 参照リンク定義を収集し、定義行を除去
        let (cleanedText, referenceLinks) = collectReferenceLinks(from: markdownText)

        let blocks = parseBlocks(from: cleanedText)
        let result = NSMutableAttributedString()

        for (index, block) in blocks.enumerated() {
            if index > 0, case .emptyLine = block {
                // empty line は段落間スペースとして扱う
                continue
            }

            let blockString = renderBlock(block, baseURL: baseURL, referenceLinks: referenceLinks)
            if result.length > 0, case .emptyLine = block {} else if result.length > 0 {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(blockString)
        }

        return result
    }

    // MARK: - Reference Link Pre-pass

    /// テキストから参照リンク定義 [id]: url "title" を収集し、定義行を除去したテキストを返す
    private static func collectReferenceLinks(from text: String) -> (String, [String: ReferenceLinkDefinition]) {
        var referenceLinks: [String: ReferenceLinkDefinition] = [:]
        // パターン: [id]: url "optional title" or [id]: url (optional title) or [id]: <url> "optional title"
        let pattern = #"^\s{0,3}\[([^\]]+)\]:\s+<?([^\s>]+)>?(?:\s+(?:"([^"]*)"|'([^']*)'|\(([^)]*)\)))?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .anchorsMatchLines) else {
            return (text, referenceLinks)
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        // 定義を収集
        for match in matches {
            let id = nsText.substring(with: match.range(at: 1)).lowercased()
            let url = nsText.substring(with: match.range(at: 2))
            var title: String?
            // title は group 3, 4, 5 のいずれか
            for groupIndex in 3...5 {
                let range = match.range(at: groupIndex)
                if range.location != NSNotFound {
                    title = nsText.substring(with: range)
                    break
                }
            }
            referenceLinks[id] = ReferenceLinkDefinition(url: url, title: title)
        }

        // 定義行を除去（後方から）
        var lines = text.components(separatedBy: "\n")
        let linePattern = #"^\s{0,3}\[([^\]]+)\]:\s+<?[^\s>]+>?(?:\s+(?:"[^"]*"|'[^']*'|\([^)]*\)))?\s*$"#
        guard let lineRegex = try? NSRegularExpression(pattern: linePattern) else {
            return (text, referenceLinks)
        }

        lines = lines.filter { line in
            let range = NSRange(location: 0, length: (line as NSString).length)
            return lineRegex.firstMatch(in: line, range: range) == nil
        }

        return (lines.joined(separator: "\n"), referenceLinks)
    }

    // MARK: - Block-Level Parsing (Pass 1)

    private static func parseBlocks(from text: String) -> [BlockType] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [BlockType] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 空行
            if trimmed.isEmpty {
                blocks.append(.emptyLine)
                i += 1
                continue
            }

            // コードブロック（フェンス```）
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language.isEmpty ? nil : language, lines: codeLines))
                continue
            }

            // 水平線
            if isHorizontalRule(trimmed) {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // 見出し（ATX style）
            if let (level, headingText) = parseHeading(trimmed) {
                blocks.append(.heading(level: level, text: headingText))
                i += 1
                continue
            }

            // 見出し（HTML <h1>〜<h6> タグ）
            if let (level, headingText) = parseHTMLHeading(trimmed) {
                blocks.append(.heading(level: level, text: headingText))
                i += 1
                continue
            }

            // テーブル
            if isTableRow(trimmed) && i + 1 < lines.count && isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                var tableRows: [[String]] = []
                // ヘッダー行
                tableRows.append(parseTableRow(trimmed))
                i += 1  // セパレーター行をスキップ
                i += 1
                // データ行
                while i < lines.count {
                    let rowLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if isTableRow(rowLine) {
                        tableRows.append(parseTableRow(rowLine))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.table(rows: tableRows, hasHeader: true))
                continue
            }

            // 引用
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                var level = 1
                while i < lines.count {
                    let qLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if qLine.hasPrefix(">") {
                        let stripped = stripBlockquotePrefix(qLine)
                        let currentLevel = countBlockquoteLevel(qLine)
                        if currentLevel > level { level = currentLevel }
                        quoteLines.append(stripped)
                        i += 1
                    } else if qLine.isEmpty {
                        break
                    } else if isHorizontalRule(qLine)
                                || parseHeading(qLine) != nil
                                || qLine.hasPrefix("```")
                                || isUnorderedListItem(qLine)
                                || isOrderedListItem(qLine)
                                || isTableRow(qLine) {
                        // ブロック要素が来たら引用を中断（CommonMark 仕様準拠）
                        break
                    } else {
                        // 引用の続き（lazy continuation）
                        quoteLines.append(qLine)
                        i += 1
                    }
                }
                blocks.append(.blockquote(level: level, lines: quoteLines))
                continue
            }

            // リスト（箇条書き）
            if isUnorderedListItem(trimmed) {
                var items: [ListItem] = []
                while i < lines.count {
                    let listLine = lines[i]
                    let listTrimmed = listLine.trimmingCharacters(in: .whitespaces)
                    if listTrimmed.isEmpty { break }
                    if let item = parseUnorderedListItem(listLine) {
                        items.append(item)
                        i += 1
                    } else if listTrimmed.hasPrefix("  ") || listTrimmed.hasPrefix("\t") {
                        // 継続行
                        if !items.isEmpty {
                            let last = items.removeLast()
                            items.append(ListItem(
                                text: last.text + " " + listTrimmed,
                                indentLevel: last.indentLevel,
                                isTask: last.isTask,
                                isChecked: last.isChecked,
                                isOrdered: false,
                                number: 0
                            ))
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.unorderedList(items: items))
                continue
            }

            // リスト（番号付き）
            if isOrderedListItem(trimmed) {
                var items: [ListItem] = []
                while i < lines.count {
                    let listLine = lines[i]
                    let listTrimmed = listLine.trimmingCharacters(in: .whitespaces)
                    if listTrimmed.isEmpty { break }
                    if let item = parseOrderedListItem(listLine) {
                        items.append(item)
                        i += 1
                    } else if listTrimmed.hasPrefix("  ") || listTrimmed.hasPrefix("\t") {
                        // 継続行
                        if !items.isEmpty {
                            let last = items.removeLast()
                            items.append(ListItem(
                                text: last.text + " " + listTrimmed,
                                indentLevel: last.indentLevel,
                                isTask: last.isTask,
                                isChecked: last.isChecked,
                                isOrdered: true,
                                number: last.number
                            ))
                        }
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.orderedList(items: items))
                continue
            }

            // 4スペースインデントのコードブロック
            if line.hasPrefix("    ") || line.hasPrefix("\t") {
                var codeLines: [String] = []
                while i < lines.count {
                    if lines[i].hasPrefix("    ") {
                        codeLines.append(String(lines[i].dropFirst(4)))
                        i += 1
                    } else if lines[i].hasPrefix("\t") {
                        codeLines.append(String(lines[i].dropFirst(1)))
                        i += 1
                    } else if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                        codeLines.append("")
                        i += 1
                    } else {
                        break
                    }
                }
                // 末尾の空行を除去
                while codeLines.last?.isEmpty == true { codeLines.removeLast() }
                blocks.append(.codeBlock(language: nil, lines: codeLines))
                continue
            }

            // Setext style 見出し（次の行が === または ---）
            if i + 1 < lines.count {
                let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
                if !nextTrimmed.isEmpty && nextTrimmed.allSatisfy({ $0 == "=" }) {
                    blocks.append(.heading(level: 1, text: trimmed))
                    i += 2
                    continue
                }
                if !nextTrimmed.isEmpty && nextTrimmed.allSatisfy({ $0 == "-" }) && nextTrimmed.count >= 2 {
                    blocks.append(.heading(level: 2, text: trimmed))
                    i += 2
                    continue
                }
            }

            // 通常の段落
            var paragraphLines: [String] = []
            while i < lines.count {
                let pLine = lines[i].trimmingCharacters(in: .whitespaces)
                if pLine.isEmpty { break }
                if pLine.hasPrefix("#") || pLine.hasPrefix("```") || pLine.hasPrefix(">") || isHorizontalRule(pLine) {
                    break
                }
                if isUnorderedListItem(pLine) || isOrderedListItem(pLine) { break }
                if isTableRow(pLine) && i + 1 < lines.count && isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                    break
                }
                paragraphLines.append(pLine)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(lines: paragraphLines))
            }
        }

        return blocks
    }

    // MARK: - Block Helpers

    private static func parseHeading(_ line: String) -> (Int, String)? {
        var level = 0
        for ch in line {
            if ch == "#" { level += 1 }
            else { break }
        }
        guard level >= 1, level <= 6 else { return nil }
        let rest = String(line.dropFirst(level)).trimmingCharacters(in: .whitespaces)
        // 末尾の # を除去
        let text = rest.replacingOccurrences(of: #"\s*#+\s*$"#, with: "", options: .regularExpression)
        return (level, text)
    }

    /// HTML <h1>〜<h6> タグをパースして (level, text) を返す
    private static func parseHTMLHeading(_ line: String) -> (Int, String)? {
        let pattern = #"^<h([1-6])(?:\s[^>]*)?>(.+?)</h\1>$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else { return nil }
        let levelStr = nsLine.substring(with: match.range(at: 1))
        guard let level = Int(levelStr) else { return nil }
        let text = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return (level, text)
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        if stripped.count >= 3 {
            if stripped.allSatisfy({ $0 == "-" }) { return true }
            if stripped.allSatisfy({ $0 == "*" }) { return true }
            if stripped.allSatisfy({ $0 == "_" }) { return true }
        }
        return false
    }

    private static func isUnorderedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
    }

    private static func isOrderedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return false }
        let prefix = trimmed[trimmed.startIndex..<dotIndex]
        if prefix.isEmpty { return false }
        if !prefix.allSatisfy({ $0.isNumber }) { return false }
        let afterDot = trimmed.index(after: dotIndex)
        return afterDot < trimmed.endIndex && trimmed[afterDot] == " "
    }

    private static func parseUnorderedListItem(_ line: String) -> ListItem? {
        // インデントレベルを計算
        let indentLevel = countLeadingSpaces(line) / 4
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return nil }
        let markers: [String] = ["- ", "* ", "+ "]
        for marker in markers {
            if trimmed.hasPrefix(marker) {
                var text = String(trimmed.dropFirst(marker.count))
                // タスクリスト
                var isTask = false
                var isChecked = false
                if text.hasPrefix("[ ] ") {
                    isTask = true
                    isChecked = false
                    text = String(text.dropFirst(4))
                } else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                    isTask = true
                    isChecked = true
                    text = String(text.dropFirst(4))
                }
                return ListItem(text: text, indentLevel: indentLevel, isTask: isTask, isChecked: isChecked, isOrdered: false, number: 0)
            }
        }
        return nil
    }

    private static func parseOrderedListItem(_ line: String) -> ListItem? {
        let indentLevel = countLeadingSpaces(line) / 4
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return nil }
        let prefix = trimmed[trimmed.startIndex..<dotIndex]
        guard let number = Int(prefix) else { return nil }
        let afterDot = trimmed.index(after: dotIndex)
        guard afterDot < trimmed.endIndex, trimmed[afterDot] == " " else { return nil }
        let text = String(trimmed[trimmed.index(after: afterDot)...])
        return ListItem(text: text, indentLevel: indentLevel, isTask: false, isChecked: false, isOrdered: true, number: number)
    }

    private static func countLeadingSpaces(_ line: String) -> Int {
        var count = 0
        for ch in line {
            if ch == " " { count += 1 }
            else if ch == "\t" { count += 4 }
            else { break }
        }
        return count
    }

    private static func isTableRow(_ line: String) -> Bool {
        return line.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let stripped = line.trimmingCharacters(in: .whitespaces)
        guard stripped.contains("|") else { return false }
        let cells = stripped.split(separator: "|", omittingEmptySubsequences: false)
        for cell in cells {
            let trimmedCell = cell.trimmingCharacters(in: .whitespaces)
            if trimmedCell.isEmpty { continue }
            // :--- or --- or ---: or :---:
            if !trimmedCell.allSatisfy({ $0 == "-" || $0 == ":" }) { return false }
        }
        return true
    }

    private static func parseTableRow(_ line: String) -> [String] {
        var cells: [String] = []
        let stripped = line.trimmingCharacters(in: .whitespaces)
        // 先頭と末尾の | を除去
        var content = stripped
        if content.hasPrefix("|") { content = String(content.dropFirst()) }
        if content.hasSuffix("|") { content = String(content.dropLast()) }
        let parts = content.split(separator: "|", omittingEmptySubsequences: false)
        for part in parts {
            cells.append(part.trimmingCharacters(in: .whitespaces))
        }
        return cells
    }

    private static func countBlockquoteLevel(_ line: String) -> Int {
        var level = 0
        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]
            if ch == ">" {
                level += 1
                index = line.index(after: index)
                if index < line.endIndex && line[index] == " " {
                    index = line.index(after: index)
                }
            } else if ch == " " {
                index = line.index(after: index)
            } else {
                break
            }
        }
        return level
    }

    private static func stripBlockquotePrefix(_ line: String) -> String {
        var result = line
        // 先頭の > を除去（ネスト対応）
        while result.hasPrefix(">") {
            result = String(result.dropFirst())
            if result.hasPrefix(" ") {
                result = String(result.dropFirst())
            }
        }
        return result
    }

    // MARK: - Block Rendering

    private static func renderBlock(_ block: BlockType, baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        switch block {
        case .heading(let level, let text):
            return renderHeading(level: level, text: text, baseURL: baseURL, referenceLinks: referenceLinks)
        case .paragraph(let lines):
            return renderParagraph(lines: lines, baseURL: baseURL, referenceLinks: referenceLinks)
        case .codeBlock(_, let lines):
            return renderCodeBlock(lines: lines)
        case .blockquote(let level, let lines):
            return renderBlockquote(level: level, lines: lines, baseURL: baseURL, referenceLinks: referenceLinks)
        case .unorderedList(let items):
            return renderList(items: items, baseURL: baseURL, referenceLinks: referenceLinks)
        case .orderedList(let items):
            return renderList(items: items, baseURL: baseURL, referenceLinks: referenceLinks)
        case .horizontalRule:
            return renderHorizontalRule()
        case .table(let rows, let hasHeader):
            return renderTable(rows: rows, hasHeader: hasHeader, baseURL: baseURL, referenceLinks: referenceLinks)
        case .emptyLine:
            return NSAttributedString()
        }
    }

    private static func renderHeading(level: Int, text: String, baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        let fontSize = headingFontSizes[min(level - 1, 5)]
        let font = NSFont.boldSystemFont(ofSize: fontSize)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacingBefore = fontSize * 0.5
        paragraphStyle.paragraphSpacing = fontSize * 0.3
        paragraphStyle.lineSpacing = lineSpacingAmount

        let blockValue = "h\(level)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
            markdownBlockTypeKey: blockValue
        ]

        let result = NSMutableAttributedString(string: text, attributes: attributes)
        applyInlineFormatting(to: result, baseFont: font, baseURL: baseURL, referenceLinks: referenceLinks)
        return result
    }

    private static func renderParagraph(lines: [String], baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        // 末尾2スペースの改行を処理: 行末に2つ以上のスペースがある場合は改行を挿入
        var processedLines: [String] = []
        for (index, line) in lines.enumerated() {
            if line.hasSuffix("  ") && index < lines.count - 1 {
                // 末尾スペースを除去し、改行文字を追加
                processedLines.append(line.replacingOccurrences(of: #"\s{2,}$"#, with: "", options: .regularExpression))
                processedLines.append("\n")
            } else {
                processedLines.append(line)
            }
        }

        let text: String
        var parts: [String] = []
        var current = ""
        for part in processedLines {
            if part == "\n" {
                parts.append(current)
                current = ""
            } else {
                if !current.isEmpty { current += " " }
                current += part
            }
        }
        if !current.isEmpty { parts.append(current) }
        text = parts.joined(separator: "\n")

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = baseFontSize * 0.4
        paragraphStyle.lineSpacing = lineSpacingAmount

        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
            markdownBlockTypeKey: MarkdownBlockValue.paragraph
        ]

        let result = NSMutableAttributedString(string: text, attributes: attributes)
        applyInlineFormatting(to: result, baseFont: baseFont, baseURL: baseURL, referenceLinks: referenceLinks)
        return result
    }

    private static func renderCodeBlock(lines: [String]) -> NSAttributedString {
        let text = lines.joined(separator: "\n")

        let textBlock = NSTextBlock()
        textBlock.backgroundColor = codeBackgroundColor
        textBlock.setContentWidth(100, type: .percentageValueType)
        textBlock.setWidth(12.0, type: .absoluteValueType, for: .padding)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textBlocks = [textBlock]
        paragraphStyle.lineSpacing = lineSpacingAmount

        let attributes: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle,
            markdownBlockTypeKey: MarkdownBlockValue.codeBlock
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func renderBlockquote(level: Int, lines: [String], baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        let text = lines.joined(separator: "\n")
        let indent = blockquoteIndent * CGFloat(level)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = baseFontSize * 0.3
        paragraphStyle.lineSpacing = lineSpacingAmount

        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: blockquoteColor,
            .paragraphStyle: paragraphStyle,
            markdownBlockTypeKey: MarkdownBlockValue.blockquote
        ]

        let result = NSMutableAttributedString(string: text, attributes: attributes)
        applyInlineFormatting(to: result, baseFont: baseFont, baseURL: baseURL, referenceLinks: referenceLinks)
        return result
    }

    private static func renderList(items: [ListItem], baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        let result = NSMutableAttributedString()

        for (index, item) in items.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            let indent = listIndent * CGFloat(item.indentLevel + 1)
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.headIndent = indent
            paragraphStyle.firstLineHeadIndent = indent - listIndent + 4
            paragraphStyle.lineSpacing = lineSpacingAmount

            // マーカー
            let marker: String
            if item.isTask {
                marker = item.isChecked ? "\u{2611} " : "\u{2610} "
            } else if item.isOrdered {
                marker = "\(item.number). "
            } else {
                marker = "\u{2022} "  // bullet
            }

            let blockValue = item.isOrdered ? MarkdownBlockValue.orderedList : MarkdownBlockValue.unorderedList
            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle,
                markdownBlockTypeKey: blockValue
            ]

            let line = NSMutableAttributedString(string: marker + item.text, attributes: attributes)
            applyInlineFormatting(to: line, baseFont: baseFont, baseURL: baseURL, referenceLinks: referenceLinks)
            result.append(line)
        }

        return result
    }

    private static func renderHorizontalRule() -> NSAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.paragraphSpacingBefore = 8.0
        paragraphStyle.paragraphSpacing = 8.0
        paragraphStyle.lineSpacing = lineSpacingAmount

        let ruleText = String(repeating: "\u{2500}", count: 40)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: horizontalRuleColor,
            .paragraphStyle: paragraphStyle,
            markdownBlockTypeKey: MarkdownBlockValue.horizontalRule
        ]

        return NSAttributedString(string: ruleText, attributes: attributes)
    }

    private static func renderTable(rows: [[String]], hasHeader: Bool, baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        guard !rows.isEmpty else { return NSAttributedString() }
        let result = NSMutableAttributedString()
        let tableFont = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)
        let headerFont = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .bold)

        let columnCount = rows.map { $0.count }.max() ?? 0
        guard columnCount > 0 else { return NSAttributedString() }

        let table = NSTextTable()
        table.numberOfColumns = columnCount
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        table.collapsesBorders = true

        // カラム幅をレンダリング後の表示幅に基づいて計算
        var maxColWidths = [CGFloat](repeating: 0, count: columnCount)
        for row in rows {
            for (colIndex, cell) in row.enumerated() where colIndex < columnCount {
                let width = estimateDisplayWidth(cell)
                maxColWidths[colIndex] = max(maxColWidths[colIndex], width)
            }
        }
        // 最小幅を保証
        for i in 0..<columnCount {
            maxColWidths[i] = max(maxColWidths[i], 3)
        }
        let totalWidth = maxColWidths.reduce(0, +)

        for (rowIndex, row) in rows.enumerated() {
            let font = (hasHeader && rowIndex == 0) ? headerFont : tableFont
            let blockValue = (hasHeader && rowIndex == 0) ? MarkdownBlockValue.tableHeader : MarkdownBlockValue.tableRow

            for colIndex in 0..<columnCount {
                let cellText = colIndex < row.count ? row[colIndex] : ""

                let block = NSTextTableBlock(table: table, startingRow: rowIndex, rowSpan: 1, startingColumn: colIndex, columnSpan: 1)
                // コンテンツに基づいたカラム幅を設定
                let widthPercent = maxColWidths[colIndex] / totalWidth * 100.0
                block.setContentWidth(widthPercent, type: .percentageValueType)
                block.setWidth(4, type: .absoluteValueType, for: .padding)

                // ヘッダー行の下罫線
                if hasHeader && rowIndex == 0 {
                    block.setWidth(1.0, type: .absoluteValueType, for: .border, edge: .maxY)
                    block.setBorderColor(horizontalRuleColor, for: .maxY)
                }

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.textBlocks = [block]

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.textColor,
                    .paragraphStyle: paragraphStyle,
                    markdownBlockTypeKey: blockValue
                ]

                let cellAttr = NSMutableAttributedString(string: cellText, attributes: attrs)
                applyInlineFormatting(to: cellAttr, baseFont: font, baseURL: baseURL, referenceLinks: referenceLinks)

                // 画像を含むセルはセンタリング
                var hasImage = false
                cellAttr.enumerateAttribute(.attachment, in: NSRange(location: 0, length: cellAttr.length)) { value, _, _ in
                    if value != nil { hasImage = true }
                }
                let finalParagraphStyle: NSParagraphStyle
                if hasImage {
                    let centeredStyle = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                    centeredStyle.alignment = .center
                    finalParagraphStyle = centeredStyle
                } else {
                    finalParagraphStyle = paragraphStyle
                }

                // インラインフォーマット適用後もparagraphStyleとblockTypeを維持
                cellAttr.addAttribute(.paragraphStyle, value: finalParagraphStyle, range: NSRange(location: 0, length: cellAttr.length))
                cellAttr.addAttribute(markdownBlockTypeKey, value: blockValue, range: NSRange(location: 0, length: cellAttr.length))
                // NSTextTable は各セル末尾に改行が必要
                var finalAttrs = attrs
                finalAttrs[.paragraphStyle] = finalParagraphStyle
                cellAttr.append(NSAttributedString(string: "\n", attributes: finalAttrs))
                result.append(cellAttr)
            }
        }

        return result
    }

    /// セルテキストのレンダリング後の表示幅を推定（文字数ベース）
    /// Markdownリンクや画像タグを考慮して実際の表示幅を返す
    private static func estimateDisplayWidth(_ text: String) -> CGFloat {
        var s = text

        // <img ...> → 画像は固定幅で推定
        if let imgRegex = try? NSRegularExpression(pattern: #"<img\s[^>]*>"#) {
            let range = NSRange(location: 0, length: (s as NSString).length)
            if imgRegex.firstMatch(in: s, range: range) != nil {
                // 画像セルは画像幅相当（高さ20pxの画像 ≒ 10文字幅程度）
                s = imgRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "XXXXXXXXXX")
            }
        }

        // [text](url) → text のみ
        if let linkRegex = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\([^\)]*\)"#) {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = linkRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }

        // ![alt](url) → alt のみ（短い幅）
        if let imgMdRegex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\([^\)]*\)"#) {
            let range = NSRange(location: 0, length: (s as NSString).length)
            s = imgMdRegex.stringByReplacingMatches(in: s, range: range, withTemplate: "$1")
        }

        return CGFloat(max(s.count, 3))
    }

    // MARK: - Inline Formatting (Pass 2)

    /// インライン書式を NSMutableAttributedString に適用
    private static func applyInlineFormatting(to attrString: NSMutableAttributedString, baseFont: NSFont, baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) {
        // 処理順序:
        // 1. エスケープシーケンスをプレースホルダーに置換
        // 2. HTML <br> タグを改行に変換
        // 3. 画像 → リンク → 参照リンク → 自動リンク → インラインコード → 太字斜体 → 太字 → 斜体 → 取り消し線
        // 4. プレースホルダーをリテラル文字に復元
        applyEscapes(to: attrString)
        applyHTMLBreaks(to: attrString)
        applyHTMLImages(to: attrString, baseURL: baseURL)
        applyImages(to: attrString, baseURL: baseURL)
        applyReferenceImages(to: attrString, referenceLinks: referenceLinks)
        applyLinks(to: attrString)
        applyReferenceLinks(to: attrString, referenceLinks: referenceLinks)
        applyAutoLinks(to: attrString)
        applyInlineCode(to: attrString)
        applyBoldItalic(to: attrString, baseFont: baseFont)
        applyBold(to: attrString, baseFont: baseFont)
        applyItalic(to: attrString, baseFont: baseFont)
        applyStrikethrough(to: attrString)
        restoreEscapes(in: attrString)
    }

    // MARK: - Inline: Escape Sequences

    /// バックスラッシュエスケープをプレースホルダーに置換
    private static func applyEscapes(to attrString: NSMutableAttributedString) {
        let text = attrString.string
        var result = ""
        var i = text.startIndex

        while i < text.endIndex {
            if text[i] == "\\" {
                let nextIndex = text.index(after: i)
                if nextIndex < text.endIndex {
                    let nextChar = String(text[nextIndex])
                    // エスケープ可能な文字か確認
                    if let mapping = escapableCharacters.first(where: { $0.character == nextChar }) {
                        result.append(mapping.placeholder)
                        i = text.index(after: nextIndex)
                        continue
                    }
                }
            }
            result.append(text[i])
            i = text.index(after: i)
        }

        if result != text {
            let range = NSRange(location: 0, length: attrString.length)
            attrString.replaceCharacters(in: range, with: result)
        }
    }

    /// プレースホルダーをリテラル文字に復元
    private static func restoreEscapes(in attrString: NSMutableAttributedString) {
        for mapping in escapableCharacters {
            let text = attrString.string as NSString
            var searchRange = NSRange(location: 0, length: text.length)
            while searchRange.location < text.length {
                let foundRange = text.range(of: mapping.placeholder, options: [], range: searchRange)
                if foundRange.location == NSNotFound { break }
                attrString.replaceCharacters(in: foundRange, with: mapping.character)
                searchRange = NSRange(
                    location: foundRange.location + 1,
                    length: (attrString.string as NSString).length - foundRange.location - 1
                )
            }
        }
    }

    // MARK: - Inline: HTML Breaks

    /// HTML <br>, <br/>, <br /> タグを改行に変換
    private static func applyHTMLBreaks(to attrString: NSMutableAttributedString) {
        let pattern = #"<br\s*/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            attrString.replaceCharacters(in: match.range, with: "\n")
        }
    }

    // MARK: - Inline: HTML Images

    /// HTML <img> タグを処理（ローカル・リモート画像を埋め込み表示）
    private static func applyHTMLImages(to attrString: NSMutableAttributedString, baseURL: URL?) {
        // <img ... /> または <img ...> パターン
        let pattern = #"<img\s+[^>]*?/?>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return }
        let srcPattern = #"src\s*=\s*"([^"]*)""#
        let altPattern = #"alt\s*=\s*"([^"]*)""#
        let heightPattern = #"height\s*=\s*"(\d+)""#
        let widthPattern = #"width\s*=\s*"(\d+)""#
        let srcRegex = try? NSRegularExpression(pattern: srcPattern, options: .caseInsensitive)
        let altRegex = try? NSRegularExpression(pattern: altPattern, options: .caseInsensitive)
        let heightRegex = try? NSRegularExpression(pattern: heightPattern, options: .caseInsensitive)
        let widthRegex = try? NSRegularExpression(pattern: widthPattern, options: .caseInsensitive)

        let text = attrString.string as NSString
        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))

        for match in matches.reversed() {
            let tagString = text.substring(with: match.range)
            let tagNS = tagString as NSString
            let tagRange = NSRange(location: 0, length: tagNS.length)

            // src属性を抽出
            var srcURL: String?
            if let srcMatch = srcRegex?.firstMatch(in: tagString, range: tagRange) {
                srcURL = tagNS.substring(with: srcMatch.range(at: 1))
            }

            // alt属性を抽出
            var altText: String?
            if let altMatch = altRegex?.firstMatch(in: tagString, range: tagRange) {
                altText = tagNS.substring(with: altMatch.range(at: 1))
            }

            // height/width属性を抽出
            var specifiedHeight: CGFloat?
            var specifiedWidth: CGFloat?
            if let hMatch = heightRegex?.firstMatch(in: tagString, range: tagRange) {
                specifiedHeight = CGFloat(Double(tagNS.substring(with: hMatch.range(at: 1))) ?? 0)
            }
            if let wMatch = widthRegex?.firstMatch(in: tagString, range: tagRange) {
                specifiedWidth = CGFloat(Double(tagNS.substring(with: wMatch.range(at: 1))) ?? 0)
            }

            // 画像を読み込み（ローカルファイル）
            var image: NSImage?
            var isRemote = false
            var remoteURL: URL?

            if let urlString = srcURL {
                // ローカルファイル
                if let baseURL = baseURL {
                    let imageURL = URL(fileURLWithPath: urlString, relativeTo: baseURL)
                    image = NSImage(contentsOf: imageURL)
                }
                if image == nil, let url = URL(string: urlString), url.isFileURL {
                    image = NSImage(contentsOf: url)
                }
                if image == nil, FileManager.default.fileExists(atPath: urlString) {
                    image = NSImage(contentsOfFile: urlString)
                }
                // リモートURLの判定
                if image == nil, let url = URL(string: urlString), let scheme = url.scheme,
                   (scheme == "http" || scheme == "https") {
                    remoteURL = url
                    isRemote = true
                    // キャッシュを確認
                    image = imageCache.object(forKey: url as NSURL)
                }
            }

            // 表示サイズを計算するヘルパー
            let calcDisplaySize: (NSSize) -> NSSize = { imageSize in
                if let h = specifiedHeight, let w = specifiedWidth {
                    return NSSize(width: w, height: h)
                } else if let h = specifiedHeight, imageSize.width > 0 && imageSize.height > 0 {
                    let scale = h / imageSize.height
                    return NSSize(width: imageSize.width * scale, height: h)
                } else if let w = specifiedWidth, imageSize.width > 0 && imageSize.height > 0 {
                    let scale = w / imageSize.width
                    return NSSize(width: w, height: imageSize.height * scale)
                } else {
                    let maxWidth: CGFloat = 600.0
                    if imageSize.width > maxWidth {
                        let scale = maxWidth / imageSize.width
                        return NSSize(width: maxWidth, height: imageSize.height * scale)
                    }
                    return imageSize
                }
            }

            // 元の<img>タグを逆変換用に保存
            let originalImgTag = text.substring(with: match.range)

            if let image = image {
                // 画像が利用可能（ローカルまたはキャッシュ済みリモート）
                let displaySize = calcDisplaySize(image.size)
                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(origin: .zero, size: displaySize)
                let cell = ResizableImageAttachmentCell(image: image, displaySize: displaySize)
                attachment.attachmentCell = cell
                let imgAttr = NSMutableAttributedString(attachment: attachment)
                imgAttr.addAttribute(imageSourceKey, value: originalImgTag, range: NSRange(location: 0, length: imgAttr.length))
                attrString.replaceCharacters(in: match.range, with: imgAttr)
            } else if isRemote, let url = remoteURL {
                // リモート画像: プレースホルダーを挿入し、後で非同期読み込み
                let placeholderSize = NSSize(
                    width: specifiedWidth ?? specifiedHeight ?? 20,
                    height: specifiedHeight ?? 20
                )
                let placeholderImage = NSImage(size: placeholderSize)
                placeholderImage.lockFocus()
                NSColor.separatorColor.withAlphaComponent(0.3).setFill()
                NSBezierPath(roundedRect: NSRect(origin: .zero, size: placeholderSize), xRadius: 2, yRadius: 2).fill()
                placeholderImage.unlockFocus()

                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(origin: .zero, size: placeholderSize)
                let cell = ResizableImageAttachmentCell(image: placeholderImage, displaySize: placeholderSize)
                attachment.attachmentCell = cell
                let imgAttr = NSMutableAttributedString(attachment: attachment)
                // リモートURL・サイズ情報をカスタム属性に保存
                let range = NSRange(location: 0, length: imgAttr.length)
                imgAttr.addAttribute(remoteImageURLKey, value: url, range: range)
                imgAttr.addAttribute(imageSourceKey, value: originalImgTag, range: range)
                if let h = specifiedHeight {
                    imgAttr.addAttribute(remoteImageSizeKey, value: NSValue(size: NSSize(width: specifiedWidth ?? 0, height: h)), range: range)
                }
                attrString.replaceCharacters(in: match.range, with: imgAttr)
            } else {
                // 読み込めない場合はプレースホルダー表示
                let placeholder = altText ?? {
                    if let src = srcURL, let url = URL(string: src) {
                        let filename = url.deletingPathExtension().lastPathComponent
                        if !filename.isEmpty { return filename }
                    }
                    return "img"
                }()
                let replacement = "[\(placeholder)]"
                attrString.replaceCharacters(in: match.range, with: replacement)
            }
        }
    }

    // MARK: - Remote Image Loading

    /// テキストストレージ内のリモート画像プレースホルダーを非同期で読み込み、実画像に差し替える
    /// completion: 全画像のダウンロード完了時に呼ばれる（メインスレッド）
    static func loadRemoteImages(in textStorage: NSTextStorage, completion: (() -> Void)? = nil) {
        // リモート画像のプレースホルダーを列挙
        var entries: [(location: Int, url: URL, specifiedSize: NSSize)] = []
        textStorage.enumerateAttribute(remoteImageURLKey, in: NSRange(location: 0, length: textStorage.length)) { value, range, _ in
            guard let url = value as? URL else { return }
            let sizeValue = (textStorage.attribute(remoteImageSizeKey, at: range.location, effectiveRange: nil) as? NSValue)?.sizeValue
            let specifiedSize = sizeValue ?? .zero
            entries.append((range.location, url, specifiedSize))
        }

        if entries.isEmpty {
            completion?()
            return
        }

        // 全画像ダウンロード完了を追跡
        let group = DispatchGroup()

        for entry in entries {
            group.enter()
            URLSession.shared.dataTask(with: entry.url) { data, _, _ in
                guard let data = data, let image = NSImage(data: data) else {
                    group.leave()
                    return
                }

                // キャッシュに保存
                imageCache.setObject(image, forKey: entry.url as NSURL)

                DispatchQueue.main.async {
                    defer { group.leave() }

                    // テキストストレージが変更されている可能性があるため位置を再検索
                    guard entry.location < textStorage.length else { return }
                    guard let storedURL = textStorage.attribute(remoteImageURLKey, at: entry.location, effectiveRange: nil) as? URL,
                          storedURL == entry.url else { return }

                    // 表示サイズを計算
                    let displaySize: NSSize
                    let specSize = entry.specifiedSize
                    if specSize.width > 0 && specSize.height > 0 {
                        displaySize = specSize
                    } else if specSize.height > 0 && image.size.height > 0 {
                        let scale = specSize.height / image.size.height
                        displaySize = NSSize(width: image.size.width * scale, height: specSize.height)
                    } else if specSize.width > 0 && image.size.width > 0 {
                        let scale = specSize.width / image.size.width
                        displaySize = NSSize(width: specSize.width, height: image.size.height * scale)
                    } else {
                        let maxWidth: CGFloat = 600.0
                        if image.size.width > maxWidth {
                            let scale = maxWidth / image.size.width
                            displaySize = NSSize(width: maxWidth, height: image.size.height * scale)
                        } else {
                            displaySize = image.size
                        }
                    }

                    // プレースホルダーを実画像に差し替え
                    // NSTextAttachment標準描画を使用（attachmentCellはboundsと二重計上されるため不使用）
                    let replaceRange = NSRange(location: entry.location, length: 1)
                    let newAttachment = NSTextAttachment()
                    newAttachment.image = image
                    newAttachment.bounds = CGRect(origin: .zero, size: displaySize)
                    let attachmentString = NSAttributedString(attachment: newAttachment)
                    textStorage.beginEditing()
                    textStorage.replaceCharacters(in: replaceRange, with: attachmentString)
                    textStorage.endEditing()
                }
            }.resume()
        }

        // 全画像ダウンロード完了後にcompletion呼び出し
        group.notify(queue: .main) {
            completion?()
        }
    }

    // MARK: - Inline: Images

    private static func applyImages(to attrString: NSMutableAttributedString, baseURL: URL?) {
        // ![alt](url) または ![alt](url "title") パターン
        let pattern = #"!\[([^\]]*)\]\(([^\s)]+)(?:\s+"([^"]*)")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        // 後方から処理（範囲のずれを防ぐ）
        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let altText = text.substring(with: match.range(at: 1))
            let urlString = text.substring(with: match.range(at: 2))
            var titleText: String?
            if match.range(at: 3).location != NSNotFound {
                titleText = text.substring(with: match.range(at: 3))
            }

            var image: NSImage?

            // ローカルファイルパスの場合
            if let baseURL = baseURL {
                let imageURL = URL(fileURLWithPath: urlString, relativeTo: baseURL)
                image = NSImage(contentsOf: imageURL)
            }
            if image == nil, let url = URL(string: urlString), url.isFileURL {
                image = NSImage(contentsOf: url)
            }
            if image == nil, FileManager.default.fileExists(atPath: urlString) {
                image = NSImage(contentsOfFile: urlString)
            }

            // 元のMarkdown画像ソースを保存（逆変換用）
            let originalMarkdown = text.substring(with: match.range)

            // リモートURLの場合はキャッシュをチェック
            if image == nil, let url = URL(string: urlString),
               (url.scheme == "http" || url.scheme == "https") {
                if let cached = imageCache.object(forKey: url as NSURL) {
                    image = cached
                }
            }

            if let image = image {
                let attachment = NSTextAttachment()
                // 画像サイズを制限（幅最大600pt）
                let maxWidth: CGFloat = 600.0
                let imageSize = image.size
                let displaySize: NSSize
                if imageSize.width > maxWidth {
                    let scale = maxWidth / imageSize.width
                    displaySize = NSSize(width: maxWidth, height: imageSize.height * scale)
                } else {
                    displaySize = imageSize
                }
                // ResizableImageAttachmentCellで統一（グレー枠を防止）
                attachment.bounds = CGRect(origin: .zero, size: displaySize)
                let cell = ResizableImageAttachmentCell(image: image, displaySize: displaySize)
                attachment.attachmentCell = cell
                let imageString = NSMutableAttributedString(attachment: attachment)
                if let titleText = titleText {
                    imageString.addAttribute(.toolTip, value: titleText, range: NSRange(location: 0, length: imageString.length))
                }
                imageString.addAttribute(imageSourceKey, value: originalMarkdown, range: NSRange(location: 0, length: imageString.length))
                attrString.replaceCharacters(in: match.range, with: imageString)
            } else if let url = URL(string: urlString),
                      (url.scheme == "http" || url.scheme == "https") {
                // リモート画像: プレースホルダーを挿入し、後で非同期読み込み
                let placeholderSize = NSSize(width: 20, height: 20)
                let placeholderImage = NSImage(size: placeholderSize)
                placeholderImage.lockFocus()
                NSColor.tertiaryLabelColor.setFill()
                NSBezierPath(roundedRect: NSRect(origin: .zero, size: placeholderSize),
                             xRadius: 2, yRadius: 2).fill()
                placeholderImage.unlockFocus()

                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(origin: .zero, size: placeholderSize)
                let placeholderCell = ResizableImageAttachmentCell(image: placeholderImage, displaySize: placeholderSize)
                attachment.attachmentCell = placeholderCell
                let imgAttr = NSMutableAttributedString(attachment: attachment)
                let range = NSRange(location: 0, length: imgAttr.length)
                imgAttr.addAttribute(remoteImageURLKey, value: url, range: range)
                imgAttr.addAttribute(imageSourceKey, value: originalMarkdown, range: range)
                // ![alt](url) にはサイズ指定がないので、サイズは 0x0（loadRemoteImagesで自然サイズを使用）
                if let titleText = titleText {
                    imgAttr.addAttribute(.toolTip, value: titleText, range: range)
                }
                attrString.replaceCharacters(in: match.range, with: imgAttr)
            } else {
                // ローカルファイルが見つからない場合: リンクとして表示
                let displayText = altText.isEmpty ? urlString : altText
                let linkString = NSMutableAttributedString(string: "[\(displayText)]", attributes: [
                    .font: baseFont,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ])
                if let url = URL(string: urlString) {
                    linkString.addAttribute(.link, value: url, range: NSRange(location: 0, length: linkString.length))
                }
                if let titleText = titleText {
                    linkString.addAttribute(.toolTip, value: titleText, range: NSRange(location: 0, length: linkString.length))
                }
                linkString.addAttribute(imageSourceKey, value: originalMarkdown, range: NSRange(location: 0, length: linkString.length))
                attrString.replaceCharacters(in: match.range, with: linkString)
            }
        }
    }

    // MARK: - Inline: Reference Images

    /// 参照画像 ![alt][id] を処理（参照リンク定義から画像URLを取得し、非同期読み込み）
    private static func applyReferenceImages(to attrString: NSMutableAttributedString, referenceLinks: [String: ReferenceLinkDefinition]) {
        guard !referenceLinks.isEmpty else { return }

        // ![alt][id] パターン
        let pattern = #"!\[([^\]]*)\]\[([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let altText = text.substring(with: match.range(at: 1))
            let idText = text.substring(with: match.range(at: 2))
            let lookupId = idText.lowercased()

            guard let definition = referenceLinks[lookupId] else { continue }
            let urlString = definition.url
            let titleText = definition.title

            // 元のMarkdownソースを保存
            let originalMarkdown = text.substring(with: match.range)

            var image: NSImage?
            // キャッシュチェック
            if let url = URL(string: urlString),
               (url.scheme == "http" || url.scheme == "https") {
                image = imageCache.object(forKey: url as NSURL)
            }

            if let image = image {
                // キャッシュ済み: 即座に表示
                let maxWidth: CGFloat = 600.0
                let imageSize = image.size
                let displaySize: NSSize
                if imageSize.width > maxWidth {
                    let scale = maxWidth / imageSize.width
                    displaySize = NSSize(width: maxWidth, height: imageSize.height * scale)
                } else {
                    displaySize = imageSize
                }
                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(origin: .zero, size: displaySize)
                let cell = ResizableImageAttachmentCell(image: image, displaySize: displaySize)
                attachment.attachmentCell = cell
                let imageString = NSMutableAttributedString(attachment: attachment)
                let range = NSRange(location: 0, length: imageString.length)
                imageString.addAttribute(imageSourceKey, value: originalMarkdown, range: range)
                if let titleText = titleText {
                    imageString.addAttribute(.toolTip, value: titleText, range: range)
                }
                attrString.replaceCharacters(in: match.range, with: imageString)
            } else if let url = URL(string: urlString),
                      (url.scheme == "http" || url.scheme == "https") {
                // リモート画像: プレースホルダーを挿入
                let placeholderSize = NSSize(width: 20, height: 20)
                let placeholderImage = NSImage(size: placeholderSize)
                placeholderImage.lockFocus()
                NSColor.tertiaryLabelColor.setFill()
                NSBezierPath(roundedRect: NSRect(origin: .zero, size: placeholderSize),
                             xRadius: 2, yRadius: 2).fill()
                placeholderImage.unlockFocus()

                let attachment = NSTextAttachment()
                attachment.bounds = CGRect(origin: .zero, size: placeholderSize)
                let placeholderCell = ResizableImageAttachmentCell(image: placeholderImage, displaySize: placeholderSize)
                attachment.attachmentCell = placeholderCell
                let imgAttr = NSMutableAttributedString(attachment: attachment)
                let range = NSRange(location: 0, length: imgAttr.length)
                imgAttr.addAttribute(remoteImageURLKey, value: url, range: range)
                imgAttr.addAttribute(imageSourceKey, value: originalMarkdown, range: range)
                if let titleText = titleText {
                    imgAttr.addAttribute(.toolTip, value: titleText, range: range)
                }
                attrString.replaceCharacters(in: match.range, with: imgAttr)
            }
            // ローカルファイル参照画像はリンクとして残す（applyReferenceLinksが処理）
        }
    }

    // MARK: - Inline: Links

    private static func applyLinks(to attrString: NSMutableAttributedString) {
        // [text](url) または [text](url "title") パターン
        let pattern = #"\[([^\]]+)\]\(([^\s)]+)(?:\s+"([^"]*)")?\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let linkText = text.substring(with: match.range(at: 1))
            let urlString = text.substring(with: match.range(at: 2))
            var titleText: String?
            if match.range(at: 3).location != NSNotFound {
                titleText = text.substring(with: match.range(at: 3))
            }

            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]

            let linkString = NSMutableAttributedString(string: linkText, attributes: linkAttrs)
            if let url = URL(string: urlString) {
                linkString.addAttribute(.link, value: url, range: NSRange(location: 0, length: linkString.length))
            }
            if let titleText = titleText {
                linkString.addAttribute(.toolTip, value: titleText, range: NSRange(location: 0, length: linkString.length))
            }
            attrString.replaceCharacters(in: match.range, with: linkString)
        }
    }

    // MARK: - Inline: Reference Links

    /// 参照リンク [text][id] または [text][] を処理
    private static func applyReferenceLinks(to attrString: NSMutableAttributedString, referenceLinks: [String: ReferenceLinkDefinition]) {
        guard !referenceLinks.isEmpty else { return }

        // [text][id] パターン
        let pattern = #"\[([^\]]+)\]\[([^\]]*)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let linkText = text.substring(with: match.range(at: 1))
            let idText = text.substring(with: match.range(at: 2))

            // id が空の場合は linkText 自身をidとして使用
            let lookupId = (idText.isEmpty ? linkText : idText).lowercased()

            guard let definition = referenceLinks[lookupId] else { continue }

            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]

            let linkString = NSMutableAttributedString(string: linkText, attributes: linkAttrs)
            if let url = URL(string: definition.url) {
                linkString.addAttribute(.link, value: url, range: NSRange(location: 0, length: linkString.length))
            }
            if let title = definition.title {
                linkString.addAttribute(.toolTip, value: title, range: NSRange(location: 0, length: linkString.length))
            }
            attrString.replaceCharacters(in: match.range, with: linkString)
        }
    }

    // MARK: - Inline: Auto-Links

    /// 自動リンク <url>、<email>、および裸のURL を処理
    private static func applyAutoLinks(to attrString: NSMutableAttributedString) {
        // 1. 角括弧自動リンク <url> パターン
        applyAngleBracketAutoLinks(to: attrString)

        // 2. 裸のURL（http:// https://）パターン
        applyBareURLs(to: attrString)
    }

    /// <url> および <email> パターンの自動リンク
    private static func applyAngleBracketAutoLinks(to attrString: NSMutableAttributedString) {
        // <url> パターン（http://, https://, ftp://）
        let urlPattern = #"<((?:https?|ftp)://[^\s>]+)>"#
        if let regex = try? NSRegularExpression(pattern: urlPattern) {
            let text = attrString.string as NSString
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
            for match in matches.reversed() {
                let urlString = text.substring(with: match.range(at: 1))
                let linkAttrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                let linkString = NSMutableAttributedString(string: urlString, attributes: linkAttrs)
                if let url = URL(string: urlString) {
                    linkString.addAttribute(.link, value: url, range: NSRange(location: 0, length: linkString.length))
                }
                attrString.replaceCharacters(in: match.range, with: linkString)
            }
        }

        // <email> パターン
        let emailPattern = #"<([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>"#
        if let regex = try? NSRegularExpression(pattern: emailPattern) {
            let text = attrString.string as NSString
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
            for match in matches.reversed() {
                let email = text.substring(with: match.range(at: 1))
                let linkAttrs: [NSAttributedString.Key: Any] = [
                    .font: baseFont,
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
                let linkString = NSMutableAttributedString(string: email, attributes: linkAttrs)
                if let url = URL(string: "mailto:\(email)") {
                    linkString.addAttribute(.link, value: url, range: NSRange(location: 0, length: linkString.length))
                }
                attrString.replaceCharacters(in: match.range, with: linkString)
            }
        }
    }

    /// 裸のURL（http:// https://）を自動リンクに変換
    private static func applyBareURLs(to attrString: NSMutableAttributedString) {
        // 既に .link 属性が付いていない部分のみ対象
        let pattern = #"(?<![<"\(])(?:https?://)[^\s<>\[\]"'\)]+[^\s<>\[\]"'\)\.,;:!?]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            // 既にリンク属性があるか確認
            let existingLink = attrString.attribute(.link, at: match.range.location, effectiveRange: nil)
            if existingLink != nil { continue }

            let urlString = text.substring(with: match.range)
            guard let url = URL(string: urlString) else { continue }

            let linkAttrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .link: url
            ]
            let linkString = NSAttributedString(string: urlString, attributes: linkAttrs)
            attrString.replaceCharacters(in: match.range, with: linkString)
        }
    }

    // MARK: - Inline: Code

    private static func applyInlineCode(to attrString: NSMutableAttributedString) {
        // ダブルバッククォート `` code `` を先に処理
        let doublePattern = #"``(.+?)``"#
        if let regex = try? NSRegularExpression(pattern: doublePattern) {
            let text = attrString.string as NSString
            let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
            for match in matches.reversed() {
                let codeText = text.substring(with: match.range(at: 1))
                    .trimmingCharacters(in: .whitespaces)  // ダブルバッククォート内の前後スペースを除去
                let codeAttrs: [NSAttributedString.Key: Any] = [
                    .font: codeFont,
                    inlineCodeBackgroundKey: codeBackgroundColor,
                    .foregroundColor: NSColor.textColor
                ]
                let codeString = NSAttributedString(string: codeText, attributes: codeAttrs)
                attrString.replaceCharacters(in: match.range, with: codeString)
            }
        }

        // シングルバッククォート `code`
        let pattern = #"`([^`]+)`"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let codeText = text.substring(with: match.range(at: 1))
            let codeAttrs: [NSAttributedString.Key: Any] = [
                .font: codeFont,
                inlineCodeBackgroundKey: codeBackgroundColor,
                .foregroundColor: NSColor.textColor
            ]
            let codeString = NSAttributedString(string: codeText, attributes: codeAttrs)
            attrString.replaceCharacters(in: match.range, with: codeString)
        }
    }

    // MARK: - Inline: Bold + Italic

    private static func applyBoldItalic(to attrString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = #"\*{3}(.+?)\*{3}|_{3}(.+?)_{3}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        var text = attrString.string as NSString
        var matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))

        for match in matches.reversed() {
            let group1 = match.range(at: 1)
            let group2 = match.range(at: 2)
            let contentRange = group1.location != NSNotFound ? group1 : group2

            // 既存の属性を保持しつつ、マークアップ記号を除去してフォントを太字斜体に変更
            let existingAttr = attrString.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString
            let font = fontWithTraits(baseFont: baseFont, traits: [.boldFontMask, .italicFontMask])
            existingAttr.addAttribute(.font, value: font, range: NSRange(location: 0, length: existingAttr.length))
            attrString.replaceCharacters(in: match.range, with: existingAttr)

            text = attrString.string as NSString
            matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        }
    }

    // MARK: - Inline: Bold

    private static func applyBold(to attrString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = #"\*{2}(.+?)\*{2}|_{2}(.+?)_{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        var text = attrString.string as NSString
        var matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))

        for match in matches.reversed() {
            let group1 = match.range(at: 1)
            let group2 = match.range(at: 2)
            let contentRange = group1.location != NSNotFound ? group1 : group2

            // 既存の属性を保持しつつ、マークアップ記号を除去してフォントを太字に変更
            let existingAttr = attrString.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString
            let font = fontWithTraits(baseFont: baseFont, traits: [.boldFontMask])
            existingAttr.addAttribute(.font, value: font, range: NSRange(location: 0, length: existingAttr.length))
            attrString.replaceCharacters(in: match.range, with: existingAttr)

            text = attrString.string as NSString
            matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        }
    }

    // MARK: - Inline: Italic

    private static func applyItalic(to attrString: NSMutableAttributedString, baseFont: NSFont) {
        let pattern = #"\*(.+?)\*|(?<![a-zA-Z0-9])_(.+?)_(?![a-zA-Z0-9])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        var text = attrString.string as NSString
        var matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))

        for match in matches.reversed() {
            let group1 = match.range(at: 1)
            let group2 = match.range(at: 2)
            let contentRange = group1.location != NSNotFound ? group1 : group2
            guard contentRange.location != NSNotFound else { continue }

            // 既存の属性を保持しつつ、マークアップ記号を除去してフォントを斜体に変更
            let existingAttr = attrString.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString
            let font = fontWithTraits(baseFont: baseFont, traits: [.italicFontMask])
            existingAttr.addAttribute(.font, value: font, range: NSRange(location: 0, length: existingAttr.length))
            attrString.replaceCharacters(in: match.range, with: existingAttr)

            text = attrString.string as NSString
            matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        }
    }

    // MARK: - Inline: Strikethrough

    private static func applyStrikethrough(to attrString: NSMutableAttributedString) {
        let pattern = #"~~(.+?)~~"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let text = attrString.string as NSString

        let matches = regex.matches(in: attrString.string, range: NSRange(location: 0, length: text.length))
        for match in matches.reversed() {
            let contentRange = match.range(at: 1)
            // 既存の属性を保持しつつ、マークアップ記号を除去して取り消し線を追加
            let existingAttr = attrString.attributedSubstring(from: contentRange).mutableCopy() as! NSMutableAttributedString
            existingAttr.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: existingAttr.length))
            attrString.replaceCharacters(in: match.range, with: existingAttr)
        }
    }

    // MARK: - Font Helpers

    private static func fontWithTraits(baseFont: NSFont, traits: NSFontTraitMask) -> NSFont {
        let fontManager = NSFontManager.shared
        if let modified = fontManager.convert(baseFont, toHaveTrait: traits) as NSFont? {
            return modified
        }
        return baseFont
    }

    // MARK: - Reverse Conversion: NSAttributedString → Markdown

    /// NSAttributedString を Markdown テキストに変換（逆変換）
    /// - Parameter attributedString: 変換元の NSAttributedString
    /// - Returns: Markdown テキスト
    /// リスト行のインデント情報（ドキュメント全体のリスト行から計算）
    private struct ListIndentInfo {
        /// リスト行の最小 headIndent（level 0 の基準値）
        let minHeadIndent: CGFloat
        /// リスト行の1段あたりのインデント幅（level 間の差）
        let indentStep: CGFloat
    }

    /// ドキュメント全体のリスト行を走査し、インデント情報を収集する
    private static func collectListIndentInfo(from attributedString: NSAttributedString) -> ListIndentInfo {
        let nsText = attributedString.string as NSString
        var listIndents: Set<CGFloat> = []
        var currentIndex = 0

        while currentIndex < nsText.length {
            let remainingRange = NSRange(location: currentIndex, length: nsText.length - currentIndex)
            let newlineRange = nsText.range(of: "\n", options: [], range: remainingRange)
            let lineEnd = newlineRange.location != NSNotFound ? newlineRange.location : nsText.length
            let lineRange = NSRange(location: currentIndex, length: lineEnd - currentIndex)

            if lineRange.length > 0 {
                let lineText = nsText.substring(with: lineRange)
                let attrs = attributedString.attributes(at: currentIndex, effectiveRange: nil)
                // リスト行かどうかを判定（テキストパターンまたは NSTextList 属性）
                let isListByText = detectListPrefix(lineText) != nil
                let isListByAttr: Bool
                if let ps = attrs[.paragraphStyle] as? NSParagraphStyle {
                    isListByAttr = !ps.textLists.isEmpty
                } else {
                    isListByAttr = false
                }
                if isListByText || isListByAttr {
                    if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, ps.headIndent > 0 {
                        listIndents.insert(ps.headIndent)
                    }
                }
            }
            currentIndex = lineEnd + 1
        }

        guard !listIndents.isEmpty else {
            return ListIndentInfo(minHeadIndent: listIndent, indentStep: listIndent)
        }

        let sorted = listIndents.sorted()
        let minIndent = sorted[0]

        // 異なるインデントレベルが2つ以上あれば、最小の差分をステップとする
        var step: CGFloat = listIndent  // デフォルト
        if sorted.count >= 2 {
            var minStep: CGFloat = .greatestFiniteMagnitude
            for i in 1..<sorted.count {
                let diff = sorted[i] - sorted[i - 1]
                if diff > 0.5 && diff < minStep {
                    minStep = diff
                }
            }
            if minStep < .greatestFiniteMagnitude {
                step = minStep
            }
        }

        return ListIndentInfo(minHeadIndent: minIndent, indentStep: step)
    }

    static func markdownString(from attributedString: NSAttributedString) -> String {
        let fullText = attributedString.string
        let nsText = fullText as NSString

        // リスト行のインデント情報を事前に収集
        let listInfo = collectListIndentInfo(from: attributedString)

        // 段落（\n 区切り）ごとに処理
        var paragraphs: [String] = []
        var currentIndex = 0
        var inCodeBlock = false
        var inTable = false
        var pendingTableCells: [NSAttributedString] = []
        var pendingTableIsHeader = false
        var currentTable: NSTextTable?  // テーブル境界の検出用

        while currentIndex < nsText.length {
            // 次の改行を探す
            let remainingRange = NSRange(location: currentIndex, length: nsText.length - currentIndex)
            let newlineRange = nsText.range(of: "\n", options: [], range: remainingRange)
            let lineEnd: Int
            if newlineRange.location != NSNotFound {
                lineEnd = newlineRange.location
            } else {
                lineEnd = nsText.length
            }

            let lineRange = NSRange(location: currentIndex, length: lineEnd - currentIndex)

            if lineRange.length == 0 {
                // 空行
                if inCodeBlock {
                    paragraphs.append("```")
                    inCodeBlock = false
                }
                if inTable {
                    inTable = false
                }
                paragraphs.append("")
                currentIndex = lineEnd + 1
                continue
            }

            let lineAttr = attributedString.attributedSubstring(from: lineRange)
            let firstAttrs = lineAttr.attributes(at: 0, effectiveRange: nil)
            let blockType = firstAttrs[markdownBlockTypeKey] as? String

            // カスタム属性によるコードブロック判定（優先）
            let isCode = blockType == MarkdownBlockValue.codeBlock || (blockType == nil && isCodeBlockLine(lineAttr))

            if isCode {
                if inTable { inTable = false }
                if !inCodeBlock {
                    paragraphs.append("```")
                    inCodeBlock = true
                }
                paragraphs.append(lineAttr.string)
            } else {
                if inCodeBlock {
                    paragraphs.append("```")
                    inCodeBlock = false
                }

                // テーブルセパレーター行はスキップ（旧形式の互換性）
                if blockType == MarkdownBlockValue.tableSeparator {
                    currentIndex = lineEnd + 1
                    continue
                }

                // NSTextTable セルの処理（セル単位の段落を行に集約）
                if blockType == MarkdownBlockValue.tableHeader || blockType == MarkdownBlockValue.tableRow {
                    if let ps = firstAttrs[.paragraphStyle] as? NSParagraphStyle,
                       let tableBlock = ps.textBlocks.first as? NSTextTableBlock {
                        // テーブルが変わったら未完了のセルを破棄してリセット
                        if tableBlock.table !== currentTable {
                            pendingTableCells.removeAll()
                            currentTable = tableBlock.table
                            if inTable {
                                // 前のテーブルとの間に空行
                                paragraphs.append("")
                            }
                        }
                        let totalCols = tableBlock.table.numberOfColumns
                        pendingTableCells.append(lineAttr)
                        pendingTableIsHeader = (blockType == MarkdownBlockValue.tableHeader)

                        if pendingTableCells.count >= totalCols {
                            // 行が完成 → Markdown行を出力
                            let cellMarkdowns = pendingTableCells.map { cellAttr -> String in
                                convertInlineToMarkdown(cellAttr).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            let row = "| " + cellMarkdowns.joined(separator: " | ") + " |"
                            paragraphs.append(row)

                            if pendingTableIsHeader {
                                let separator = "| " + cellMarkdowns.map {
                                    String(repeating: "-", count: max($0.count, 3))
                                }.joined(separator: " | ") + " |"
                                paragraphs.append(separator)
                            }
                            pendingTableCells.removeAll()
                            inTable = true
                        }
                        currentIndex = lineEnd + 1
                        continue
                    }

                    // 旧形式（スペースパディング）のフォールバック
                    inTable = true
                    let markdownLine = convertLineToMarkdown(lineAttr, listInfo: listInfo)
                    paragraphs.append(markdownLine)
                    if blockType == MarkdownBlockValue.tableHeader {
                        let cells = parseTableCellsFromRendered(lineAttr.string)
                        let separator = "| " + cells.map { String(repeating: "-", count: max($0.trimmingCharacters(in: .whitespaces).count, 3)) }.joined(separator: " | ") + " |"
                        paragraphs.append(separator)
                    }
                } else {
                    if inTable { inTable = false }
                    let markdownLine = convertLineToMarkdown(lineAttr, listInfo: listInfo)
                    if !markdownLine.isEmpty {
                        paragraphs.append(markdownLine)
                    }
                }
            }

            currentIndex = lineEnd + 1
        }

        // 末尾でコードブロックが開いたままなら閉じる
        if inCodeBlock {
            paragraphs.append("```")
        }

        return paragraphs.joined(separator: "\n")
    }

    /// 1行分の NSAttributedString を Markdown 行に変換
    private static func convertLineToMarkdown(_ lineAttr: NSAttributedString, listInfo: ListIndentInfo) -> String {
        let text = lineAttr.string
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        guard fullRange.length > 0 else { return "" }

        // カスタム属性でブロックタイプを判定（最優先）
        let firstAttrs = lineAttr.attributes(at: 0, effectiveRange: nil)
        if let blockType = firstAttrs[markdownBlockTypeKey] as? String {
            switch blockType {
            case MarkdownBlockValue.horizontalRule:
                return "---"
            case MarkdownBlockValue.codeBlock:
                return text  // コードブロック行（呼び出し側で ``` を付ける）
            case MarkdownBlockValue.heading1, MarkdownBlockValue.heading2,
                 MarkdownBlockValue.heading3, MarkdownBlockValue.heading4,
                 MarkdownBlockValue.heading5, MarkdownBlockValue.heading6:
                let level = Int(String(blockType.last!))!
                let prefix = String(repeating: "#", count: level) + " "
                let inlineMarkdown = convertInlineToMarkdown(lineAttr, baseIsBold: true)
                return prefix + inlineMarkdown
            case MarkdownBlockValue.blockquote:
                let inlineMarkdown = convertInlineToMarkdown(lineAttr)
                return "> " + inlineMarkdown
            case MarkdownBlockValue.unorderedList, MarkdownBlockValue.orderedList:
                return convertListLineToMarkdown(lineAttr, text: text, nsText: nsText, attrs: firstAttrs, listInfo: listInfo)
            case MarkdownBlockValue.tableHeader, MarkdownBlockValue.tableRow:
                return convertTableLineToMarkdown(lineAttr, isHeader: blockType == MarkdownBlockValue.tableHeader)
            case MarkdownBlockValue.tableSeparator:
                return ""  // テーブルセパレーターは tableHeader の後に自動挿入
            case MarkdownBlockValue.paragraph:
                return convertInlineToMarkdown(lineAttr)
            default:
                return convertInlineToMarkdown(lineAttr)
            }
        }

        // カスタム属性がない場合のフォールバック（ユーザーが編集した行等）

        // 水平線の検出（─の繰り返し）
        if isHorizontalRuleLine(text) {
            return "---"
        }

        // コードブロックの検出（全体が monospaced + backgroundColor）
        if isCodeBlockLine(lineAttr) {
            return text
        }

        // 見出しの検出
        if let headingLevel = detectHeadingLevel(firstAttrs) {
            let prefix = String(repeating: "#", count: headingLevel) + " "
            // RTF でリスト内に見出しがある場合、テキスト先頭にリストマーカー（\t•\t 等）が
            // 含まれている可能性がある。見出しとして出力する際はリストマーカーを除去する。
            let effectiveLineAttr: NSAttributedString
            if let listPrefixResult = detectListPrefix(text) {
                let restRange = NSRange(location: listPrefixResult.contentStartIndex, length: nsText.length - listPrefixResult.contentStartIndex)
                effectiveLineAttr = restRange.length > 0 ? lineAttr.attributedSubstring(from: restRange) : lineAttr
            } else {
                // テキストパターンにマッチしなくても、先頭のタブやリストマーカー文字をストリップ
                let stripped = stripListMarkerText(text)
                if stripped.count < text.count {
                    let startIndex = text.count - stripped.count
                    let restRange = NSRange(location: startIndex, length: nsText.length - startIndex)
                    effectiveLineAttr = restRange.length > 0 ? lineAttr.attributedSubstring(from: restRange) : lineAttr
                } else {
                    effectiveLineAttr = lineAttr
                }
            }
            let inlineMarkdown = convertInlineToMarkdown(effectiveLineAttr, baseIsBold: true)
            return prefix + inlineMarkdown
        }

        // 引用の検出（foregroundColor が secondaryLabelColor）
        if let color = firstAttrs[.foregroundColor] as? NSColor,
           isBlockquoteColor(color) {
            let inlineMarkdown = convertInlineToMarkdown(lineAttr)
            return "> " + inlineMarkdown
        }

        // リストの検出（bullet • / チェックボックス / 番号付き）
        if detectListPrefix(text) != nil {
            return convertListLineToMarkdown(lineAttr, text: text, nsText: nsText, attrs: firstAttrs, listInfo: listInfo)
        }

        // NSTextList による検出（テキスト内にリストマーカーがない場合のフォールバック）
        // Cocoa の RTF リーダーは NSTextList を段落スタイルの textLists に格納する
        // テキスト本文にリストマーカーが含まれない場合でもリスト行として検出できる
        if let paragraphStyle = firstAttrs[.paragraphStyle] as? NSParagraphStyle,
           !paragraphStyle.textLists.isEmpty {
            return convertNSTextListLineToMarkdown(lineAttr, text: text, nsText: nsText, attrs: firstAttrs, listInfo: listInfo)
        }

        // 通常の段落（インライン書式のみ）
        return convertInlineToMarkdown(lineAttr)
    }

    /// Markdown インラインスタイルの種類（フォントファミリに依存しない論理的なスタイル）
    private enum InlineStyle: Equatable {
        case plain
        case bold
        case italic
        case boldItalic
        case code
        case strikethrough
        case boldStrikethrough
        case link(url: String, title: String?)
        case image(name: String)
        case rawMarkdown  // 元のMarkdown/HTMLをそのまま出力
    }

    /// インラインスタイルのセグメント（同じスタイルの連続テキストをマージ用）
    private struct InlineSegment {
        var text: String
        let style: InlineStyle
    }

    /// リスト行を Markdown に変換（テキスト内のリストマーカーを使用、インデントレベル付き）
    private static func convertListLineToMarkdown(_ lineAttr: NSAttributedString, text: String, nsText: NSString, attrs: [NSAttributedString.Key: Any], listInfo: ListIndentInfo) -> String {
        guard let listPrefix = detectListPrefix(text) else {
            return convertInlineToMarkdown(lineAttr)
        }
        let indentLevel = detectListIndentLevel(attrs, listInfo: listInfo)
        let indent = String(repeating: "  ", count: indentLevel)
        let restStart = listPrefix.contentStartIndex
        let restRange = NSRange(location: restStart, length: nsText.length - restStart)
        if restRange.length > 0 {
            let restAttr = lineAttr.attributedSubstring(from: restRange)
            let inlineMarkdown = convertInlineToMarkdown(restAttr)
            return indent + listPrefix.markdownPrefix + inlineMarkdown
        }
        return indent + listPrefix.markdownPrefix
    }

    /// NSTextList による検出でリスト行を Markdown に変換
    /// テキスト内にリストマーカー文字がない場合（Cocoa がリストマーカーをテキスト本文に含めない場合）に使用
    /// NSTextList の markerFormat と textLists の数からリストタイプとネストレベルを判定
    private static func convertNSTextListLineToMarkdown(_ lineAttr: NSAttributedString, text: String, nsText: NSString, attrs: [NSAttributedString.Key: Any], listInfo: ListIndentInfo) -> String {
        guard let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle,
              !paragraphStyle.textLists.isEmpty else {
            return convertInlineToMarkdown(lineAttr)
        }

        // ネストレベル: textLists の数 - 1（最も深いリストが現在のレベル）
        let indentLevel = detectListIndentLevel(attrs, listInfo: listInfo)

        // リストタイプを判定（最も深いリストの markerFormat を確認）
        let currentList = paragraphStyle.textLists.last!
        let markerFormat = currentList.markerFormat
        let isOrdered = markerFormat == .decimal || markerFormat == .lowercaseAlpha ||
                        markerFormat == .uppercaseAlpha || markerFormat == .lowercaseRoman ||
                        markerFormat == .uppercaseRoman

        let indent = String(repeating: "  ", count: indentLevel)
        let prefix = isOrdered ? "1. " : "- "

        // テキスト本文からリストマーカー部分（\t...\t）を除去してコンテンツを取得
        let content = stripListMarkerText(text)
        let contentStartIndex = text.count - content.count

        if contentStartIndex > 0 && contentStartIndex < nsText.length {
            let restRange = NSRange(location: contentStartIndex, length: nsText.length - contentStartIndex)
            let restAttr = lineAttr.attributedSubstring(from: restRange)
            let inlineMarkdown = convertInlineToMarkdown(restAttr)
            return indent + prefix + inlineMarkdown
        }

        let inlineMarkdown = convertInlineToMarkdown(lineAttr)
        return indent + prefix + inlineMarkdown
    }

    /// テキストからリストマーカー部分を除去する
    /// Cocoa RTF リーダーが挿入する "\t•\t" や "\t1.\t" のパターンを除去
    /// 注意: 先頭にタブがない場合はリストマーカーテキストではないのでそのまま返す
    private static func stripListMarkerText(_ text: String) -> String {
        var i = text.startIndex

        // 先頭のタブが必須（RTF リストマーカーは必ずタブで始まる）
        guard i < text.endIndex && text[i] == "\t" else {
            return text
        }

        // 先頭のタブをスキップ
        while i < text.endIndex && text[i] == "\t" {
            i = text.index(after: i)
        }

        // マーカー文字（bullet, checkbox, 数字+ドット）をスキップ
        if i < text.endIndex {
            let ch = text[i]
            if ch == "\u{2022}" || ch == "\u{2611}" || ch == "\u{2610}" {
                // bullet / checkbox
                i = text.index(after: i)
            } else if ch.isASCII && ch.isNumber {
                // 番号付き: ASCII 数字 + ドット（ドットが必須）
                // isNumber は漢数字にも true を返すため、isASCII を併用する
                _ = i  // numStart (unused)
                while i < text.endIndex && text[i].isASCII && text[i].isNumber {
                    i = text.index(after: i)
                }
                if i < text.endIndex && text[i] == "." {
                    i = text.index(after: i)
                } else {
                    // ドットがない → リストマーカーではない（例: "14:00" の先頭数字）
                    return text
                }
            } else {
                // マーカーが見つからなければそのまま返す
                return text
            }
        }

        // オプショナルなスペース
        if i < text.endIndex && text[i] == " " {
            i = text.index(after: i)
        }

        // 後続のタブ
        if i < text.endIndex && text[i] == "\t" {
            i = text.index(after: i)
        }

        return String(text[i...])
    }

    /// インライン書式を Markdown テキストに変換
    /// - Parameter baseIsBold: true の場合、基準フォントが太字（見出し等）なので太字マーキングをスキップ
    private static func convertInlineToMarkdown(_ attrString: NSAttributedString, baseIsBold: Bool = false) -> String {
        let nsText = attrString.string as NSString
        guard nsText.length > 0 else { return "" }

        // Phase 1: attribute run をスタイル付きセグメントに変換
        var segments: [InlineSegment] = []
        var i = 0

        while i < nsText.length {
            var effectiveRange = NSRange()
            let attrs = attrString.attributes(at: i, effectiveRange: &effectiveRange)
            let segmentText = nsText.substring(with: effectiveRange)

            // NSTextAttachment（画像）の検出
            if attrs[.attachment] is NSTextAttachment {
                // 元ソース情報があればそのまま使用（<img>タグ or ![alt](url)）
                if let source = attrs[imageSourceKey] as? String {
                    segments.append(InlineSegment(text: source, style: .rawMarkdown))
                } else {
                    let imageName = "image"
                    segments.append(InlineSegment(text: imageName, style: .image(name: imageName)))
                }
                i = NSMaxRange(effectiveRange)
                continue
            }

            // リンクの検出
            if let link = attrs[.link] {
                let urlString: String
                if let url = link as? URL {
                    urlString = url.absoluteString
                } else {
                    urlString = "\(link)"
                }
                let title = attrs[.toolTip] as? String
                segments.append(InlineSegment(text: segmentText, style: .link(url: urlString, title: title)))
                i = NSMaxRange(effectiveRange)
                continue
            }

            // フォント属性の解析
            let font = attrs[.font] as? NSFont
            let isBold = font.map { isFontBold($0) } ?? false
            let isItalic = font.map { isFontItalic($0) } ?? false
            let isMonospaced = font.map { isFontMonospaced($0) } ?? false
            let hasCodeBackground = attrs[.backgroundColor] as? NSColor != nil && isMonospaced
            let hasStrikethrough = (attrs[.strikethroughStyle] as? Int ?? 0) != 0

            let effectiveBold = isBold && !baseIsBold

            let style: InlineStyle
            if hasCodeBackground {
                style = .code
            } else if hasStrikethrough {
                style = effectiveBold ? .boldStrikethrough : .strikethrough
            } else if effectiveBold && isItalic {
                style = .boldItalic
            } else if effectiveBold {
                style = .bold
            } else if isItalic {
                style = .italic
            } else {
                style = .plain
            }

            segments.append(InlineSegment(text: segmentText, style: style))
            i = NSMaxRange(effectiveRange)
        }

        // Phase 2: 同一スタイルの隣接セグメントをマージ
        // （フォントファミリが異なるだけで同じ bold/italic の場合に `****` を防ぐ）
        var merged: [InlineSegment] = []
        for seg in segments {
            if let last = merged.last, last.style == seg.style {
                merged[merged.count - 1].text += seg.text
            } else {
                merged.append(seg)
            }
        }

        // Phase 3: マージ済みセグメントを Markdown 記法に変換
        var result = ""
        for seg in merged {
            switch seg.style {
            case .image(let name):
                result += "![\(name)]()"
            case .rawMarkdown:
                result += seg.text
            case .link(let url, let title):
                if let title = title, !title.isEmpty {
                    result += "[\(seg.text)](\(url) \"\(title)\")"
                } else {
                    result += "[\(seg.text)](\(url))"
                }
            case .code:
                result += "`\(seg.text)`"
            case .boldItalic:
                result += "***\(seg.text)***"
            case .bold:
                result += "**\(seg.text)**"
            case .italic:
                result += "*\(seg.text)*"
            case .strikethrough:
                result += "~~\(seg.text)~~"
            case .boldStrikethrough:
                result += "~~**\(seg.text)**~~"
            case .plain:
                result += seg.text
            }
        }

        return result
    }

    // MARK: - Reverse Conversion Helpers

    /// 水平線の検出
    private static func isHorizontalRuleLine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy({ $0 == "\u{2500}" })
    }

    /// コードブロック行の検出（全体が monospaced + backgroundColor）
    private static func isCodeBlockLine(_ attrString: NSAttributedString) -> Bool {
        let fullRange = NSRange(location: 0, length: attrString.length)
        guard fullRange.length > 0 else { return false }

        var isCode = true
        attrString.enumerateAttributes(in: fullRange, options: []) { attrs, _, stop in
            guard let font = attrs[.font] as? NSFont else {
                isCode = false
                stop.pointee = true
                return
            }
            if !isFontMonospaced(font) || attrs[.backgroundColor] == nil {
                // 見出しレベルのフォントではないことも確認
                isCode = false
                stop.pointee = true
            }
        }
        return isCode
    }

    /// 見出しレベルの検出（フォントサイズから判定）
    /// Markdown 由来の属性がない場合（RTF等）は、ベースフォントサイズより大きいボールドフォントを
    /// サイズの範囲に基づいて見出しとして検出する
    private static func detectHeadingLevel(_ attrs: [NSAttributedString.Key: Any]) -> Int? {
        guard let font = attrs[.font] as? NSFont else { return nil }
        let size = font.pointSize
        let fontManager = NSFontManager.shared
        let traits = fontManager.traits(of: font)
        guard traits.contains(.boldFontMask) else { return nil }

        // まず Markdown パーサー由来の正確なサイズでマッチを試みる
        // headingFontSizes = [28, 24, 20, 17, 15, 13] に対応
        for (index, headingSize) in headingFontSizes.enumerated() {
            if abs(size - headingSize) < 0.5 {
                return index + 1  // H1=1, H2=2, ...
            }
        }

        // RTF 等のフォールバック: ベースフォントサイズより明確に大きいボールドは見出しとみなす
        // サイズ範囲で判定（一般的な RTF フォントサイズにも対応）
        if size >= 26 { return 1 }       // H1: 26pt 以上
        if size >= 22 { return 2 }       // H2: 22-25pt
        if size >= 18 { return 3 }       // H3: 18-21pt（RTF \fs36 = 18pt など）
        if size >= 15.5 { return 4 }     // H4: 15.5-17pt
        if size >= 13.5 { return 5 }     // H5: 13.5-15pt（RTF \fs28 = 14pt など）

        // ベースフォントサイズ（baseFontSize = 14pt）以下のボールドは見出しとしない
        return nil
    }

    /// 引用の色かどうか
    private static func isBlockquoteColor(_ color: NSColor) -> Bool {
        // secondaryLabelColor と比較（RGB + alpha）
        guard let converted = color.usingColorSpace(.deviceRGB),
              let secondary = NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB) else {
            return false
        }
        return abs(converted.redComponent - secondary.redComponent) < 0.05 &&
               abs(converted.greenComponent - secondary.greenComponent) < 0.05 &&
               abs(converted.blueComponent - secondary.blueComponent) < 0.05 &&
               abs(converted.alphaComponent - secondary.alphaComponent) < 0.05
    }

    /// 段落スタイルからリストのネストレベルを検出する
    /// 1. headIndent + ドキュメント全体のインデント情報から相対的に計算
    /// 2. NSTextList の textLists.count から計算（フォールバック）
    private static func detectListIndentLevel(_ attrs: [NSAttributedString.Key: Any], listInfo: ListIndentInfo) -> Int {
        guard let paragraphStyle = attrs[.paragraphStyle] as? NSParagraphStyle else {
            return 0
        }

        // 方法1: headIndent からの相対計算
        let headIndent = paragraphStyle.headIndent
        if headIndent >= 1 {
            let diff = headIndent - listInfo.minHeadIndent
            if diff < listInfo.indentStep * 0.3 {
                return 0
            }
            let level = Int(round(diff / listInfo.indentStep))
            return max(0, level)
        }

        // 方法2: NSTextList の数からの計算（headIndent が 0 の場合のフォールバック）
        if !paragraphStyle.textLists.isEmpty {
            return max(0, paragraphStyle.textLists.count - 1)
        }

        return 0
    }

    /// リストプレフィックスの検出結果
    private struct ListPrefixResult {
        let markdownPrefix: String
        let contentStartIndex: Int
    }

    /// リストプレフィックスの検出
    /// Markdown パーサー由来のリストマーカー（"• ", "☑ ", "☐ ", "1. "）に加え、
    /// Cocoa RTF リーダー由来のタブ付きリストマーカー（"\t•\t"）にも対応する
    private static func detectListPrefix(_ text: String) -> ListPrefixResult? {
        // --- Markdown パーサー由来のフォーマット ---

        // タスクリスト（チェック済み ☑）
        if text.hasPrefix("\u{2611} ") {
            return ListPrefixResult(markdownPrefix: "- [x] ", contentStartIndex: 2)
        }
        // タスクリスト（未チェック ☐）
        if text.hasPrefix("\u{2610} ") {
            return ListPrefixResult(markdownPrefix: "- [ ] ", contentStartIndex: 2)
        }
        // 箇条書き（bullet •）+ スペース
        if text.hasPrefix("\u{2022} ") {
            return ListPrefixResult(markdownPrefix: "- ", contentStartIndex: 2)
        }

        // --- Cocoa RTF リーダー由来のフォーマット ---
        // {\\listtext \t• \t} → テキスト本文に "\t•\t" または "\t• \t" が挿入される
        // タブ + bullet + タブ のパターン
        if let bulletRange = findRTFListMarker(text, marker: "\u{2022}") {
            return ListPrefixResult(markdownPrefix: "- ", contentStartIndex: bulletRange)
        }
        // タブ + チェック済み + タブ
        if let bulletRange = findRTFListMarker(text, marker: "\u{2611}") {
            return ListPrefixResult(markdownPrefix: "- [x] ", contentStartIndex: bulletRange)
        }
        // タブ + 未チェック + タブ
        if let bulletRange = findRTFListMarker(text, marker: "\u{2610}") {
            return ListPrefixResult(markdownPrefix: "- [ ] ", contentStartIndex: bulletRange)
        }

        // --- 番号付きリスト ---
        // "1. " 形式（Markdown 由来）
        if let result = detectNumberedListPrefix(text) {
            return result
        }
        // "\t1.\t" 形式（RTF 由来）
        if let result = detectRTFNumberedListPrefix(text) {
            return result
        }

        return nil
    }

    /// RTF リーダー由来のリストマーカー（\t + marker + [\s] + \t）を検索し、
    /// コンテンツの開始インデックスを返す
    private static func findRTFListMarker(_ text: String, marker: Character) -> Int? {
        // パターン: 先頭付近の \t + marker + (オプショナルなスペース) + \t の後
        var i = text.startIndex

        // 先頭のタブをスキップ
        while i < text.endIndex && text[i] == "\t" {
            i = text.index(after: i)
        }

        // マーカー文字を確認
        guard i < text.endIndex && text[i] == marker else { return nil }
        i = text.index(after: i)

        // オプショナルなスペース
        if i < text.endIndex && text[i] == " " {
            i = text.index(after: i)
        }

        // タブまたは行末
        if i < text.endIndex && text[i] == "\t" {
            i = text.index(after: i)
        }

        return text.distance(from: text.startIndex, to: i)
    }

    /// Markdown 由来の番号付きリスト検出（"1. " 形式）
    private static func detectNumberedListPrefix(_ text: String) -> ListPrefixResult? {
        guard let dotIndex = text.firstIndex(of: ".") else { return nil }
        let prefix = text[text.startIndex..<dotIndex]
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let afterDot = text.index(after: dotIndex)
        guard afterDot < text.endIndex && text[afterDot] == " " else { return nil }
        let mdPrefix = "\(prefix). "
        let startIndex = text.distance(from: text.startIndex, to: text.index(after: afterDot))
        return ListPrefixResult(markdownPrefix: mdPrefix, contentStartIndex: startIndex)
    }

    /// RTF 由来の番号付きリスト検出（"\t1.\t" 形式）
    private static func detectRTFNumberedListPrefix(_ text: String) -> ListPrefixResult? {
        var i = text.startIndex
        // 先頭のタブをスキップ
        while i < text.endIndex && text[i] == "\t" {
            i = text.index(after: i)
        }
        // ASCII 数字を読み取る（漢数字を誤認しないため isASCII を併用）
        let numStart = i
        while i < text.endIndex && text[i].isASCII && text[i].isNumber {
            i = text.index(after: i)
        }
        guard i > numStart else { return nil }
        // ドットを確認
        guard i < text.endIndex && text[i] == "." else { return nil }
        i = text.index(after: i)
        // オプショナルなスペース
        if i < text.endIndex && text[i] == " " {
            i = text.index(after: i)
        }
        // タブ
        if i < text.endIndex && text[i] == "\t" {
            i = text.index(after: i)
        }
        let contentStart = text.distance(from: text.startIndex, to: i)
        let numStr = String(text[numStart..<i].prefix(while: { $0.isASCII && $0.isNumber }))
        return ListPrefixResult(markdownPrefix: "\(numStr). ", contentStartIndex: contentStart)
    }

    /// フォントが太字かどうか
    private static func isFontBold(_ font: NSFont) -> Bool {
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.boldFontMask)
    }

    /// フォントが斜体かどうか
    private static func isFontItalic(_ font: NSFont) -> Bool {
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.italicFontMask)
    }

    /// フォントが等幅（monospaced）かどうか
    private static func isFontMonospaced(_ font: NSFont) -> Bool {
        let traits = NSFontManager.shared.traits(of: font)
        return traits.contains(.fixedPitchFontMask)
    }

    // MARK: - Table Reverse Conversion

    /// テーブル行（ヘッダーまたはデータ行）を Markdown テーブル行に変換
    /// レンダリング時にスペースパディングされたテキストを | 区切りに変換
    private static func convertTableLineToMarkdown(_ lineAttr: NSAttributedString, isHeader: Bool) -> String {
        let cellAttrs = parseTableCellAttrsFromRendered(lineAttr)
        if cellAttrs.isEmpty { return convertInlineToMarkdown(lineAttr) }
        let cellMarkdowns = cellAttrs.map { cellAttr -> String in
            convertInlineToMarkdown(cellAttr).trimmingCharacters(in: .whitespaces)
        }
        return "| " + cellMarkdowns.joined(separator: " | ") + " |"
    }

    /// レンダリングされたテーブル行テキストからセルを分割（プレーンテキスト版）
    /// renderTable で各セルは columnWidth にパディングされ、2スペースで区切られている
    private static func parseTableCellsFromRendered(_ text: String) -> [String] {
        // 2つ以上のスペースをセパレーターとして分割
        let pattern = "  +"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let nsText = text as NSString
        var cells: [String] = []
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let cellRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            cells.append(nsText.substring(with: cellRange))
            lastEnd = NSMaxRange(match.range)
        }
        // 最後のセル
        if lastEnd < nsText.length {
            cells.append(nsText.substring(from: lastEnd))
        }
        return cells
    }

    /// レンダリングされたテーブル行から属性付きセルを分割
    private static func parseTableCellAttrsFromRendered(_ lineAttr: NSAttributedString) -> [NSAttributedString] {
        let text = lineAttr.string
        let pattern = "  +"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [lineAttr]
        }
        let nsText = text as NSString
        var cells: [NSAttributedString] = []
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            let cellRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            cells.append(lineAttr.attributedSubstring(from: cellRange))
            lastEnd = NSMaxRange(match.range)
        }
        // 最後のセル
        if lastEnd < nsText.length {
            let cellRange = NSRange(location: lastEnd, length: nsText.length - lastEnd)
            cells.append(lineAttr.attributedSubstring(from: cellRange))
        }
        return cells
    }
}
