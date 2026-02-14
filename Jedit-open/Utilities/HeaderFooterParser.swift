//
//  HeaderFooterParser.swift
//  Jedit-open
//
//  ヘッダー・フッター文字列のパーサー
//  %page, %total, %date, %time などの変数を実際の値に置換する
//

import Cocoa

/// ヘッダー・フッター文字列のパーサー
class HeaderFooterParser {

    // MARK: - Header/Footer Variables

    /// ヘッダー・フッターで使用可能な変数
    private static let headerVariables: [String] = [
        "%page",           // 0: ページ番号（%page+1, %page-1 のようにオフセット指定可能）
        "%total",          // 1: 総ページ数（%total+1, %total-1 のようにオフセット指定可能）
        "%date",           // 2: 現在の日付（Preferencesの日付フォーマット）
        "%time",           // 3: 現在の時刻（Preferencesの時刻フォーマット）
        "%name",           // 4: ドキュメント名（displayName）
        "%path",           // 5: ファイルパス
        "%user",           // 6: ユーザー名（フルネーム）
        "%moddate",        // 7: ファイル更新日（yyyy-MM-dd形式）
        "%modtime",        // 8: ファイル更新時刻（HH:mm形式）
        "%author",         // 9: ドキュメントプロパティ - Author
        "%company",        // 10: ドキュメントプロパティ - Company
        "%copyright",      // 11: ドキュメントプロパティ - Copyright
        "%title",          // 12: ドキュメントプロパティ - Title
        "%subject",        // 13: ドキュメントプロパティ - Subject
        "%keywords",       // 14: ドキュメントプロパティ - Keywords
        "%comment"         // 15: ドキュメントプロパティ - Comment
    ]

    // MARK: - Context for Parsing

    /// パース時に必要な情報を保持する構造体
    struct Context {
        /// 現在のページ番号（0始まり）
        let pageNumber: Int
        /// 総ページ数
        let totalPages: Int
        /// ドキュメント名
        let documentName: String
        /// ファイルパス（nilの場合は空文字列を返す）
        let filePath: String?
        /// ファイル更新日（nilの場合は現在日時を使用）
        let dateModified: Date?
        /// ドキュメントプロパティ
        let properties: NewDocData.PropertiesData?

        init(pageNumber: Int, totalPages: Int, documentName: String,
             filePath: String? = nil, dateModified: Date? = nil,
             properties: NewDocData.PropertiesData? = nil) {
            self.pageNumber = pageNumber
            self.totalPages = totalPages
            self.documentName = documentName
            self.filePath = filePath
            self.dateModified = dateModified
            self.properties = properties
        }
    }

    // MARK: - Parsing

    /// ヘッダー・フッターの文字列をパースして変数を置換
    /// - Parameters:
    ///   - attributedString: 入力となるNSAttributedString
    ///   - context: パースに必要なコンテキスト情報
    /// - Returns: 変数が置換されたNSMutableAttributedString
    static func parse(_ attributedString: NSAttributedString, with context: Context) -> NSMutableAttributedString {
        let result = NSMutableAttributedString(attributedString: attributedString)

        for (index, variable) in headerVariables.enumerated() {
            var searchStart = 0

            while searchStart < result.length {
                let searchRange = NSRange(location: searchStart, length: result.length - searchStart)
                let range = (result.string as NSString).range(of: variable, options: .caseInsensitive, range: searchRange)

                guard range.location != NSNotFound else {
                    break
                }

                // 置換する文字列を決定
                let replacement: String

                switch index {
                case 0, 1:
                    // %page または %total（オフセット付き）
                    let (finalRange, value) = parsePageVariable(
                        in: result.string,
                        at: range,
                        baseValue: index == 0 ? context.pageNumber + 1 : context.totalPages
                    )
                    replacement = String(value)

                    // 属性を保持して置換
                    let attributes = result.attributes(at: range.location, effectiveRange: nil)
                    result.replaceCharacters(in: finalRange, with: NSAttributedString(string: replacement, attributes: attributes))
                    searchStart = finalRange.location + replacement.count
                    continue

                case 2:
                    // %date
                    let dateType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.dateFormatType)
                    replacement = CalendarDateHelper.descriptionOfDateType(dateType)

                case 3:
                    // %time
                    let timeType = UserDefaults.standard.integer(forKey: UserDefaults.Keys.timeFormatType)
                    replacement = CalendarDateHelper.descriptionOfTimeType(timeType)

                case 4:
                    // %name
                    replacement = context.documentName

                case 5:
                    // %path
                    replacement = context.filePath ?? ""

                case 6:
                    // %user
                    replacement = NSFullUserName()

                case 7:
                    // %moddate
                    let date = context.dateModified ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd"
                    replacement = formatter.string(from: date)

                case 8:
                    // %modtime
                    let date = context.dateModified ?? Date()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "HH:mm"
                    replacement = formatter.string(from: date)

                case 9:
                    // %author
                    replacement = context.properties?.author ?? ""

                case 10:
                    // %company
                    replacement = context.properties?.company ?? ""

                case 11:
                    // %copyright
                    replacement = context.properties?.copyright ?? ""

                case 12:
                    // %title
                    replacement = context.properties?.title ?? ""

                case 13:
                    // %subject
                    replacement = context.properties?.subject ?? ""

                case 14:
                    // %keywords
                    replacement = context.properties?.keywords ?? ""

                case 15:
                    // %comment
                    replacement = context.properties?.comment ?? ""

                default:
                    replacement = "?"
                }

                // 属性を保持して置換
                let attributes = result.attributes(at: range.location, effectiveRange: nil)
                result.replaceCharacters(in: range, with: NSAttributedString(string: replacement, attributes: attributes))
                searchStart = range.location + replacement.count
            }
        }

        return result
    }

    /// 単純な文字列に対するパース（NSAttributedStringを使わない場合）
    /// - Parameters:
    ///   - string: 入力文字列
    ///   - context: パースに必要なコンテキスト情報
    /// - Returns: 変数が置換された文字列
    static func parse(_ string: String, with context: Context) -> String {
        let attributedString = NSAttributedString(string: string)
        return parse(attributedString, with: context).string
    }

    // MARK: - Drawing

    /// ヘッダー・フッター描画に必要な情報
    struct DrawingInfo {
        let headerAttributedString: NSAttributedString?
        let footerAttributedString: NSAttributedString?
        let headerColor: NSColor?
        let footerColor: NSColor?
        let defaultColor: NSColor
        let defaultFont: NSFont
        let documentName: String
        let filePath: String?
        let dateModified: Date?
        let documentProperties: NewDocData.PropertiesData?
        let totalPages: Int
    }

    /// ヘッダーを描画
    /// - Parameters:
    ///   - info: 描画情報
    ///   - pageNumber: ページ番号（0始まり）
    ///   - pageRect: ページ全体の矩形
    ///   - docRect: ドキュメント領域の矩形（マージン内）
    static func drawHeader(info: DrawingInfo, forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        if let headerAttrString = info.headerAttributedString, headerAttrString.length > 0 {
            let context = Context(
                pageNumber: pageNumber,
                totalPages: info.totalPages,
                documentName: info.documentName,
                filePath: info.filePath,
                dateModified: info.dateModified,
                properties: info.documentProperties
            )
            let parsedHeader = parse(headerAttrString, with: context)

            // 色を適用
            let color = info.headerColor ?? info.defaultColor
            parsedHeader.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: parsedHeader.length))

            // ヘッダーはページ上部マージン内に描画
            let headerY = pageRect.minY + 20

            // パラグラフスタイルからアラインメントを取得
            let alignment: NSTextAlignment
            if let paragraphStyle = parsedHeader.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                alignment = paragraphStyle.alignment
            } else {
                alignment = .left
            }

            // アラインメントに応じてX位置を計算
            let headerSize = parsedHeader.size()
            let headerX: CGFloat
            switch alignment {
            case .center:
                headerX = pageRect.midX - headerSize.width / 2
            case .right:
                headerX = docRect.maxX - headerSize.width
            default:
                headerX = docRect.minX
            }

            parsedHeader.draw(at: NSPoint(x: headerX, y: headerY))
        } else {
            // 従来の単純な描画（後方互換性）
            let attributes: [NSAttributedString.Key: Any] = [
                .font: info.defaultFont,
                .foregroundColor: info.headerColor ?? info.defaultColor
            ]

            let headerString = info.documentName as NSString
            let headerY = pageRect.minY + 20
            let headerX = docRect.minX

            headerString.draw(at: NSPoint(x: headerX, y: headerY), withAttributes: attributes)
        }
    }

    /// フッターを描画
    /// - Parameters:
    ///   - info: 描画情報
    ///   - pageNumber: ページ番号（0始まり）
    ///   - pageRect: ページ全体の矩形
    ///   - docRect: ドキュメント領域の矩形（マージン内）
    static func drawFooter(info: DrawingInfo, forPageNumber pageNumber: Int, in pageRect: NSRect, docRect: NSRect) {
        if let footerAttrString = info.footerAttributedString, footerAttrString.length > 0 {
            let context = Context(
                pageNumber: pageNumber,
                totalPages: info.totalPages,
                documentName: info.documentName,
                filePath: info.filePath,
                dateModified: info.dateModified,
                properties: info.documentProperties
            )
            let parsedFooter = parse(footerAttrString, with: context)

            // 色を適用
            let color = info.footerColor ?? info.defaultColor
            parsedFooter.addAttribute(.foregroundColor, value: color, range: NSRange(location: 0, length: parsedFooter.length))

            // パラグラフスタイルからアラインメントを取得
            let alignment: NSTextAlignment
            if let paragraphStyle = parsedFooter.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle {
                alignment = paragraphStyle.alignment
            } else {
                alignment = .center
            }

            let footerSize = parsedFooter.size()
            let footerY = pageRect.maxY - footerSize.height - 20

            let footerX: CGFloat
            switch alignment {
            case .left:
                footerX = docRect.minX
            case .right:
                footerX = docRect.maxX - footerSize.width
            default:
                footerX = pageRect.midX - footerSize.width / 2
            }

            parsedFooter.draw(at: NSPoint(x: footerX, y: footerY))
        } else {
            // 従来の単純な描画（後方互換性：ページ番号を表示）
            let attributes: [NSAttributedString.Key: Any] = [
                .font: info.defaultFont,
                .foregroundColor: info.footerColor ?? info.defaultColor
            ]

            let footerText = "\(pageNumber + 1) / \(info.totalPages)"
            let footerString = footerText as NSString
            let footerSize = footerString.size(withAttributes: attributes)

            let footerY = pageRect.maxY - footerSize.height - 20
            let footerX = pageRect.midX - footerSize.width / 2

            footerString.draw(at: NSPoint(x: footerX, y: footerY), withAttributes: attributes)
        }
    }

    // MARK: - Private Helpers

    /// %page, %total のオフセット付き変数をパース
    /// - Parameters:
    ///   - string: 検索対象の文字列
    ///   - range: 変数が見つかった範囲
    ///   - baseValue: 基本値（ページ番号または総ページ数）
    /// - Returns: 最終的な範囲と計算された値のタプル
    private static func parsePageVariable(in string: String, at range: NSRange, baseValue: Int) -> (NSRange, Int) {
        let nsString = string as NSString
        var finalRange = range
        var offset = 0
        var sign: Character = " "

        var j = NSMaxRange(range)

        // オフセット記号をチェック（+ または -）
        if j < nsString.length {
            let char = Character(UnicodeScalar(nsString.character(at: j))!)
            if char == "+" || char == "-" {
                sign = char
                j += 1
                finalRange.length += 1

                // 数字を読み取る
                while j < nsString.length {
                    let digitChar = nsString.character(at: j)
                    if let digit = Int(String(UnicodeScalar(digitChar)!)), digit >= 0 && digit <= 9 {
                        offset = offset * 10 + digit
                        j += 1
                        finalRange.length += 1
                    } else {
                        break
                    }
                }
            }
        }

        // 値を計算
        let value: Int
        if sign == "+" {
            value = baseValue + offset
        } else if sign == "-" {
            value = baseValue - offset
        } else {
            value = baseValue
        }

        return (finalRange, value)
    }
}
