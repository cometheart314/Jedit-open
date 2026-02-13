//
//  MarkdownParser.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/13.
//

import Cocoa

/// Markdown テキストを NSAttributedString に変換するパーサー
enum MarkdownParser {

    // MARK: - Styling Constants

    private static let baseFontSize: CGFloat = 14.0
    private static let headingFontSizes: [CGFloat] = [28, 24, 20, 17, 15, 13]  // H1-H6
    private static let codeFontSize: CGFloat = 12.0
    private static let listIndent: CGFloat = 24.0
    private static let blockquoteIndent: CGFloat = 20.0
    private static let lineHeightMultiple: CGFloat = 1.8

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
        let indentLevel = countLeadingSpaces(line) / 2
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
        let indentLevel = countLeadingSpaces(line) / 2
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
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
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
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]

        let result = NSMutableAttributedString(string: text, attributes: attributes)
        applyInlineFormatting(to: result, baseFont: baseFont, baseURL: baseURL, referenceLinks: referenceLinks)
        return result
    }

    private static func renderCodeBlock(lines: [String]) -> NSAttributedString {
        let text = lines.joined(separator: "\n")
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = 12.0
        paragraphStyle.firstLineHeadIndent = 12.0
        paragraphStyle.tailIndent = -12.0
        paragraphStyle.paragraphSpacingBefore = 6.0
        paragraphStyle.paragraphSpacing = 6.0
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let attributes: [NSAttributedString.Key: Any] = [
            .font: codeFont,
            .foregroundColor: NSColor.textColor,
            .backgroundColor: codeBackgroundColor,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: text, attributes: attributes)
    }

    private static func renderBlockquote(level: Int, lines: [String], baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        let text = lines.joined(separator: " ")
        let indent = blockquoteIndent * CGFloat(level)

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.headIndent = indent
        paragraphStyle.firstLineHeadIndent = indent
        paragraphStyle.paragraphSpacing = baseFontSize * 0.3
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let attributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: blockquoteColor,
            .paragraphStyle: paragraphStyle
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
            paragraphStyle.lineHeightMultiple = lineHeightMultiple

            // マーカー
            let marker: String
            if item.isTask {
                marker = item.isChecked ? "\u{2611} " : "\u{2610} "
            } else if item.isOrdered {
                marker = "\(item.number). "
            } else {
                marker = "\u{2022} "  // bullet
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: NSColor.textColor,
                .paragraphStyle: paragraphStyle
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
        paragraphStyle.lineHeightMultiple = lineHeightMultiple

        let ruleText = String(repeating: "\u{2500}", count: 40)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: horizontalRuleColor,
            .paragraphStyle: paragraphStyle
        ]

        return NSAttributedString(string: ruleText, attributes: attributes)
    }

    private static func renderTable(rows: [[String]], hasHeader: Bool, baseURL: URL?, referenceLinks: [String: ReferenceLinkDefinition] = [:]) -> NSAttributedString {
        guard !rows.isEmpty else { return NSAttributedString() }
        let result = NSMutableAttributedString()
        let tableFont = NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .regular)

        // 各列の最大幅を計算
        var columnWidths: [Int] = []
        for row in rows {
            for (colIndex, cell) in row.enumerated() {
                if colIndex >= columnWidths.count {
                    columnWidths.append(cell.count)
                } else {
                    columnWidths[colIndex] = max(columnWidths[colIndex], cell.count)
                }
            }
        }

        for (rowIndex, row) in rows.enumerated() {
            if rowIndex > 0 {
                result.append(NSAttributedString(string: "\n"))
            }

            var lineText = ""
            for (colIndex, cell) in row.enumerated() {
                if colIndex > 0 { lineText += "  " }
                let width = colIndex < columnWidths.count ? columnWidths[colIndex] : cell.count
                lineText += cell.padding(toLength: width, withPad: " ", startingAt: 0)
            }

            let font = (hasHeader && rowIndex == 0) ?
                NSFont.monospacedSystemFont(ofSize: codeFontSize, weight: .bold) : tableFont

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.textColor
            ]

            let line = NSMutableAttributedString(string: lineText, attributes: attributes)
            applyInlineFormatting(to: line, baseFont: font, baseURL: baseURL, referenceLinks: referenceLinks)
            result.append(line)

            // ヘッダー行の後にセパレーターを挿入
            if hasHeader && rowIndex == 0 {
                var separator = ""
                for (colIndex, width) in columnWidths.enumerated() {
                    if colIndex > 0 { separator += "  " }
                    separator += String(repeating: "\u{2500}", count: width)
                }
                let sepAttrs: [NSAttributedString.Key: Any] = [
                    .font: tableFont,
                    .foregroundColor: horizontalRuleColor
                ]
                result.append(NSAttributedString(string: "\n"))
                result.append(NSAttributedString(string: separator, attributes: sepAttrs))
            }
        }

        return result
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
        applyImages(to: attrString, baseURL: baseURL)
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

            if let image = image {
                let attachment = NSTextAttachment()
                attachment.image = image
                // 画像サイズを制限（幅最大600pt）
                let maxWidth: CGFloat = 600.0
                let imageSize = image.size
                if imageSize.width > maxWidth {
                    let scale = maxWidth / imageSize.width
                    attachment.bounds = CGRect(x: 0, y: 0, width: maxWidth, height: imageSize.height * scale)
                }
                let imageString = NSMutableAttributedString(attachment: attachment)
                if let titleText = titleText {
                    imageString.addAttribute(.toolTip, value: titleText, range: NSRange(location: 0, length: imageString.length))
                }
                attrString.replaceCharacters(in: match.range, with: imageString)
            } else {
                // リモートURL等: リンクとして表示
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
                attrString.replaceCharacters(in: match.range, with: linkString)
            }
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
                    .backgroundColor: codeBackgroundColor,
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
                .backgroundColor: codeBackgroundColor,
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
            let content = text.substring(with: contentRange)

            let font = fontWithTraits(baseFont: baseFont, traits: [.boldFontMask, .italicFontMask])
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let styled = NSAttributedString(string: content, attributes: attrs)
            attrString.replaceCharacters(in: match.range, with: styled)

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
            let content = text.substring(with: contentRange)

            let font = fontWithTraits(baseFont: baseFont, traits: [.boldFontMask])
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let styled = NSAttributedString(string: content, attributes: attrs)
            attrString.replaceCharacters(in: match.range, with: styled)

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
            let content = text.substring(with: contentRange)

            let font = fontWithTraits(baseFont: baseFont, traits: [.italicFontMask])
            let attrs: [NSAttributedString.Key: Any] = [.font: font]
            let styled = NSAttributedString(string: content, attributes: attrs)
            attrString.replaceCharacters(in: match.range, with: styled)

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
            let content = text.substring(with: match.range(at: 1))
            let attrs: [NSAttributedString.Key: Any] = [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue
            ]
            let styled = NSMutableAttributedString(string: content)
            // 既存の属性を保持しつつ取り消し線を追加
            styled.addAttributes(attrs, range: NSRange(location: 0, length: styled.length))
            attrString.replaceCharacters(in: match.range, with: styled)
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
}
