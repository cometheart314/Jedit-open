//
//  NewDocData.swift
//  Jedit-open
//
//  Created by Claude on 2025/01/15.
//

import Cocoa

// MARK: - NewDocData

struct NewDocData: Codable, Equatable {
    var view: ViewData
    var format: FormatData
    var fontAndColors: FontAndColorsData
    var pageLayout: PageLayoutData
    var headerFooter: HeaderFooterData
    var properties: PropertiesData
    var printInfo: PrintInfoData?

    // MARK: - ViewData

    struct ViewData: Codable, Equatable {
        var windowWidth: CGFloat
        var windowHeight: CGFloat
        var windowX: CGFloat
        var windowY: CGFloat
        var scale: CGFloat
        var lineNumberType: LineNumberType
        var rulerType: RulerType
        var showInspectorBar: Bool
        var showToolBar: Bool
        var pageMode: Bool
        var docWidthType: DocWidthType
        var fixedDocWidth: Int  // Fixed Width の文字数
        var showInvisibles: ShowInvisibles
        // 選択範囲とスクロール位置（ウィンドウを閉じる時に保存、開く時に復元）
        var selectedRangeLocation: Int?
        var selectedRangeLength: Int?
        var scrollPositionX: CGFloat?
        var scrollPositionY: CGFloat?
        // ツールバー項目のカスタマイズ状態
        var toolbarItemIdentifiers: [String]?
        // ツールバー表示モード（0: iconAndLabel, 1: iconOnly, 2: labelOnly）
        var toolbarDisplayMode: Int?

        enum LineNumberType: Int, Codable {
            case none = 0
            case logical = 1
            case physical = 2
        }

        enum RulerType: Int, Codable {
            case none = 0
            case point = 1
            case centimeter = 2
            case inch = 3
            case character = 4
        }

        enum DocWidthType: Int, Codable {
            case paperWidth = 0       // Follows Paper Width
            case windowWidth = 1      // Follows Window Width
            case noWrap = 2           // Don't Wrap Line
            case fixedWidth = 3       // Fixed Width (xx chars.)
        }

        struct ShowInvisibles: Codable, Equatable {
            var space: Bool
            var nonBreakingSpace: Bool
            var kanjiSpace: Bool
            var tab: Bool
            var lineSeparator: Bool
            var paragraphBreak: Bool
            var pageBreak: Bool
            var verticalTab: Bool

            /// メンバーワイズイニシャライザ
            init(space: Bool, nonBreakingSpace: Bool, kanjiSpace: Bool, tab: Bool,
                 lineSeparator: Bool, paragraphBreak: Bool, pageBreak: Bool, verticalTab: Bool) {
                self.space = space
                self.nonBreakingSpace = nonBreakingSpace
                self.kanjiSpace = kanjiSpace
                self.tab = tab
                self.lineSeparator = lineSeparator
                self.paragraphBreak = paragraphBreak
                self.pageBreak = pageBreak
                self.verticalTab = verticalTab
            }

            static var `default`: ShowInvisibles {
                ShowInvisibles(
                    space: false,
                    nonBreakingSpace: false,
                    kanjiSpace: false,
                    tab: false,
                    lineSeparator: false,
                    paragraphBreak: false,
                    pageBreak: false,
                    verticalTab: false
                )
            }

            /// 全ての不可視文字を表示する設定
            static var all: ShowInvisibles {
                ShowInvisibles(
                    space: true,
                    nonBreakingSpace: true,
                    kanjiSpace: true,
                    tab: true,
                    lineSeparator: true,
                    paragraphBreak: true,
                    pageBreak: true,
                    verticalTab: true
                )
            }

            /// 全ての不可視文字を非表示にする設定
            static var none: ShowInvisibles {
                ShowInvisibles(
                    space: false,
                    nonBreakingSpace: false,
                    kanjiSpace: false,
                    tab: false,
                    lineSeparator: false,
                    paragraphBreak: false,
                    pageBreak: false,
                    verticalTab: false
                )
            }

            /// InvisibleCharacterOptionsへの変換
            func toInvisibleCharacterOptions() -> InvisibleCharacterOptions {
                var options: InvisibleCharacterOptions = []
                if space { options.insert(.spaceCharacter) }
                if nonBreakingSpace { options.insert(.nonBreakingSpace) }
                if kanjiSpace { options.insert(.fullWidthSpaceCharacter) }
                if tab { options.insert(.tabCharacter) }
                if lineSeparator { options.insert(.lineSeparator) }
                if paragraphBreak { options.insert(.returnCharacter) }
                if pageBreak { options.insert(.pageBreak) }
                if verticalTab { options.insert(.verticalTab) }
                return options
            }

            /// InvisibleCharacterOptionsからの変換
            init(from options: InvisibleCharacterOptions) {
                self.space = options.contains(.spaceCharacter)
                self.nonBreakingSpace = options.contains(.nonBreakingSpace)
                self.kanjiSpace = options.contains(.fullWidthSpaceCharacter)
                self.tab = options.contains(.tabCharacter)
                self.lineSeparator = options.contains(.lineSeparator)
                self.paragraphBreak = options.contains(.returnCharacter)
                self.pageBreak = options.contains(.pageBreak)
                self.verticalTab = options.contains(.verticalTab)
            }
        }

        static var `default`: ViewData {
            ViewData(
                windowWidth: 800,
                windowHeight: 600,
                windowX: 100,
                windowY: 100,
                scale: 1.0,
                lineNumberType: .logical,
                rulerType: .character,
                showInspectorBar: true,
                showToolBar: true,
                pageMode: false,
                docWidthType: .windowWidth,
                fixedDocWidth: 80,
                showInvisibles: .default,
                selectedRangeLocation: nil,
                selectedRangeLength: nil,
                scrollPositionX: nil,
                scrollPositionY: nil
            )
        }
    }

    // MARK: - FormatData

    struct FormatData: Codable, Equatable {
        var newDocNameType: NewDocNameType
        var richText: Bool
        var fileExtension: String  // ファイル拡張子（plain text: "txt", rich text: ""）
        var textEncoding: String.Encoding.RawValue
        var lineEndingType: LineEndingType
        var bom: Bool
        var editingDirection: EditingDirection
        var tabWidthPoints: CGFloat  // タブ幅（ポイント単位で内部保存）
        var tabWidthUnit: TabWidthUnit  // タブ幅の表示単位
        var lineHeightMultiple: CGFloat  // 行の高さの倍率（times）
        var lineHeightMinimum: CGFloat  // 最小行高（points）
        var lineHeightMaximum: CGFloat  // 最大行高（points）
        var interLineSpacing: CGFloat
        var paragraphSpacingBefore: CGFloat
        var paragraphSpacingAfter: CGFloat
        var autoIndent: Bool
        var indentWrappedLines: Bool  // Indent wrapped lines of Plain Text チェックボックス
        var wrappedLineIndent: CGFloat
        var wordWrappingType: WordWrappingType
        var targetSizeType: TargetSizeType  // Target Size の種類
        var minTargetSize: Int
        var maxTargetSize: Int

        enum NewDocNameType: Int, Codable {
            case untitled = 0             // Untitled #
            case dateTime = 1             // YYYY-MM-DD hhmmss
            case dateWithSerial = 2       // YYYY-MM-DD-###
            case systemShortDate = 3      // System Short Date #
            case systemLongDate = 4       // System Long Date #
            case preferencesDate = 5      // Preferences General Date #
        }

        enum LineEndingType: Int, Codable {
            case lf = 0      // Unix/macOS
            case cr = 1      // Classic Mac
            case crlf = 2    // Windows
        }

        enum EditingDirection: Int, Codable {
            case leftToRight = 0
            case rightToLeft = 1
        }

        enum WordWrappingType: Int, Codable {
            case systemDefault = 0
            case japaneseWordwrap = 1
            case dontWordwrap = 2
        }

        enum TabWidthUnit: Int, Codable {
            case points = 0
            case spaces = 1
        }

        enum TargetSizeType: Int, Codable {
            case none = 0
            case characters = 1
            case visibleChars = 2
            case words = 3
            case rows = 4
            case paragraphs = 5
        }

        // MARK: - Custom Decoder（後方互換性のため）

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            newDocNameType = try container.decode(NewDocNameType.self, forKey: .newDocNameType)
            richText = try container.decode(Bool.self, forKey: .richText)
            fileExtension = try container.decode(String.self, forKey: .fileExtension)
            textEncoding = try container.decode(String.Encoding.RawValue.self, forKey: .textEncoding)
            lineEndingType = try container.decode(LineEndingType.self, forKey: .lineEndingType)
            bom = try container.decode(Bool.self, forKey: .bom)
            editingDirection = try container.decode(EditingDirection.self, forKey: .editingDirection)
            tabWidthPoints = try container.decode(CGFloat.self, forKey: .tabWidthPoints)
            tabWidthUnit = try container.decode(TabWidthUnit.self, forKey: .tabWidthUnit)

            // 新しいプロパティ（古いデータにはないのでデフォルト値を使用）
            lineHeightMultiple = try container.decodeIfPresent(CGFloat.self, forKey: .lineHeightMultiple) ?? 1.0
            lineHeightMinimum = try container.decodeIfPresent(CGFloat.self, forKey: .lineHeightMinimum) ?? 0
            lineHeightMaximum = try container.decodeIfPresent(CGFloat.self, forKey: .lineHeightMaximum) ?? 0

            interLineSpacing = try container.decode(CGFloat.self, forKey: .interLineSpacing)
            paragraphSpacingBefore = try container.decode(CGFloat.self, forKey: .paragraphSpacingBefore)
            paragraphSpacingAfter = try container.decode(CGFloat.self, forKey: .paragraphSpacingAfter)
            autoIndent = try container.decode(Bool.self, forKey: .autoIndent)
            indentWrappedLines = try container.decode(Bool.self, forKey: .indentWrappedLines)
            wrappedLineIndent = try container.decode(CGFloat.self, forKey: .wrappedLineIndent)
            wordWrappingType = try container.decode(WordWrappingType.self, forKey: .wordWrappingType)
            targetSizeType = try container.decode(TargetSizeType.self, forKey: .targetSizeType)
            minTargetSize = try container.decode(Int.self, forKey: .minTargetSize)
            maxTargetSize = try container.decode(Int.self, forKey: .maxTargetSize)
        }

        private enum CodingKeys: String, CodingKey {
            case newDocNameType, richText, fileExtension, textEncoding, lineEndingType, bom
            case editingDirection, tabWidthPoints, tabWidthUnit
            case lineHeightMultiple, lineHeightMinimum, lineHeightMaximum
            case interLineSpacing, paragraphSpacingBefore, paragraphSpacingAfter
            case autoIndent, indentWrappedLines, wrappedLineIndent, wordWrappingType
            case targetSizeType, minTargetSize, maxTargetSize
        }

        // MARK: - Memberwise Initializer

        init(
            newDocNameType: NewDocNameType,
            richText: Bool,
            fileExtension: String,
            textEncoding: String.Encoding.RawValue,
            lineEndingType: LineEndingType,
            bom: Bool,
            editingDirection: EditingDirection,
            tabWidthPoints: CGFloat,
            tabWidthUnit: TabWidthUnit,
            lineHeightMultiple: CGFloat,
            lineHeightMinimum: CGFloat,
            lineHeightMaximum: CGFloat,
            interLineSpacing: CGFloat,
            paragraphSpacingBefore: CGFloat,
            paragraphSpacingAfter: CGFloat,
            autoIndent: Bool,
            indentWrappedLines: Bool,
            wrappedLineIndent: CGFloat,
            wordWrappingType: WordWrappingType,
            targetSizeType: TargetSizeType,
            minTargetSize: Int,
            maxTargetSize: Int
        ) {
            self.newDocNameType = newDocNameType
            self.richText = richText
            self.fileExtension = fileExtension
            self.textEncoding = textEncoding
            self.lineEndingType = lineEndingType
            self.bom = bom
            self.editingDirection = editingDirection
            self.tabWidthPoints = tabWidthPoints
            self.tabWidthUnit = tabWidthUnit
            self.lineHeightMultiple = lineHeightMultiple
            self.lineHeightMinimum = lineHeightMinimum
            self.lineHeightMaximum = lineHeightMaximum
            self.interLineSpacing = interLineSpacing
            self.paragraphSpacingBefore = paragraphSpacingBefore
            self.paragraphSpacingAfter = paragraphSpacingAfter
            self.autoIndent = autoIndent
            self.indentWrappedLines = indentWrappedLines
            self.wrappedLineIndent = wrappedLineIndent
            self.wordWrappingType = wordWrappingType
            self.targetSizeType = targetSizeType
            self.minTargetSize = minTargetSize
            self.maxTargetSize = maxTargetSize
        }

        static var `default`: FormatData {
            FormatData(
                newDocNameType: .untitled,
                richText: true,
                fileExtension: "",
                textEncoding: String.Encoding.utf8.rawValue,
                lineEndingType: .lf,
                bom: false,
                editingDirection: .leftToRight,
                tabWidthPoints: 32.0,  // 約4スペース分（8pt/スペース × 4）
                tabWidthUnit: .points,
                lineHeightMultiple: 1.0,
                lineHeightMinimum: 0,
                lineHeightMaximum: 0,
                interLineSpacing: 0,
                paragraphSpacingBefore: 0,
                paragraphSpacingAfter: 0,
                autoIndent: true,
                indentWrappedLines: false,
                wrappedLineIndent: 0,
                wordWrappingType: .systemDefault,
                targetSizeType: .none,
                minTargetSize: 0,
                maxTargetSize: 1000
            )
        }

        static var plainText: FormatData {
            var data = FormatData.default
            data.richText = false
            data.fileExtension = "txt"
            return data
        }
    }

    // MARK: - FontAndColorsData

    struct FontAndColorsData: Codable, Equatable {
        var baseFontSize: CGFloat
        var baseFontName: String
        var colors: Colors

        struct Colors: Codable, Equatable {
            var character: CodableColor
            var background: CodableColor
            var invisible: CodableColor
            var caret: CodableColor
            var highlight: CodableColor
            var lineNumber: CodableColor
            var lineNumberBackground: CodableColor
            var header: CodableColor
            var footer: CodableColor

            static var `default`: Colors {
                Colors(
                    character: CodableColor(.textColor),
                    background: CodableColor(.textBackgroundColor),
                    invisible: CodableColor(.tertiaryLabelColor),
                    caret: CodableColor(.textColor),
                    highlight: CodableColor(.selectedTextBackgroundColor),
                    lineNumber: CodableColor(.secondaryLabelColor),
                    lineNumberBackground: CodableColor(.controlBackgroundColor),
                    header: CodableColor(.textColor),
                    footer: CodableColor(.textColor)
                )
            }
        }

        static var `default`: FontAndColorsData {
            FontAndColorsData(
                baseFontSize: 14.0,
                baseFontName: NSFont.systemFont(ofSize: 14).fontName,
                colors: .default
            )
        }
    }

    // MARK: - PageLayoutData

    struct PageLayoutData: Codable, Equatable {
        /// 上マージン（ポイント単位で保持）
        var topMarginPoints: CGFloat
        /// 左マージン（ポイント単位で保持）
        var leftMarginPoints: CGFloat
        /// 右マージン（ポイント単位で保持）
        var rightMarginPoints: CGFloat
        /// 下マージン（ポイント単位で保持）
        var bottomMarginPoints: CGFloat
        /// 印刷スケール（100% = 1.0）
        var printScale: CGFloat

        /// 表示用のマージン単位（保存されない、UI表示用のみ）
        enum MarginUnit: Int {
            case centimeter = 0
            case inch = 1
            case point = 2

            /// ポイントから指定単位に変換
            func fromPoints(_ points: CGFloat) -> CGFloat {
                switch self {
                case .centimeter:
                    return points / 28.3465  // 1cm = 28.3465pt
                case .inch:
                    return points / 72.0     // 1inch = 72pt
                case .point:
                    return points
                }
            }

            /// 指定単位からポイントに変換
            func toPoints(_ value: CGFloat) -> CGFloat {
                switch self {
                case .centimeter:
                    return value * 28.3465
                case .inch:
                    return value * 72.0
                case .point:
                    return value
                }
            }
        }

        static var `default`: PageLayoutData {
            PageLayoutData(
                topMarginPoints: 90.0,      // 上下マージン 90pt
                leftMarginPoints: 72.0,     // 左右マージン 72pt
                rightMarginPoints: 72.0,
                bottomMarginPoints: 90.0,
                printScale: 1.0             // 100%
            )
        }
    }

    // MARK: - HeaderFooterData

    struct HeaderFooterData: Codable, Equatable {
        /// ヘッダーのRTFデータ（attributedStringを保存）
        var headerRTFData: Data?
        /// フッターのRTFデータ（attributedStringを保存）
        var footerRTFData: Data?

        static var `default`: HeaderFooterData {
            HeaderFooterData(
                headerRTFData: defaultHeaderRTFData(),
                footerRTFData: defaultFooterRTFData()
            )
        }

        /// デフォルトのヘッダー: "%name" 左寄せ
        private static func defaultHeaderRTFData() -> Data? {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .left
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .paragraphStyle: paragraphStyle
            ]
            let attrString = NSAttributedString(string: "%name", attributes: attributes)
            return rtfData(from: attrString)
        }

        /// デフォルトのフッター: "%page/%total" 中央寄せ
        private static func defaultFooterRTFData() -> Data? {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12),
                .paragraphStyle: paragraphStyle
            ]
            let attrString = NSAttributedString(string: "%page/%total", attributes: attributes)
            return rtfData(from: attrString)
        }

        /// NSAttributedStringからRTFDataを作成
        static func rtfData(from attributedString: NSAttributedString) -> Data? {
            let range = NSRange(location: 0, length: attributedString.length)
            return try? attributedString.data(
                from: range,
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        }

        /// RTFDataからNSAttributedStringを作成
        static func attributedString(from rtfData: Data?) -> NSAttributedString {
            guard let data = rtfData else {
                return NSAttributedString()
            }
            return (try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )) ?? NSAttributedString()
        }
    }

    // MARK: - PropertiesData

    struct PropertiesData: Codable, Equatable {
        var author: String
        var company: String
        var copyright: String
        var title: String
        var subject: String
        var keywords: String
        var comment: String

        static var `default`: PropertiesData {
            PropertiesData(
                author: "",
                company: "",
                copyright: "",
                title: "",
                subject: "",
                keywords: "",
                comment: ""
            )
        }
    }

    // MARK: - PrintInfoData

    /// NSPrintInfo の設定を保存するためのデータ構造
    struct PrintInfoData: Codable, Equatable {
        /// 用紙サイズの幅（ポイント）
        var paperWidth: CGFloat
        /// 用紙サイズの高さ（ポイント）
        var paperHeight: CGFloat
        /// 用紙の向き（0: portrait, 1: landscape）
        var orientation: Int
        /// 上マージン（ポイント）
        var topMargin: CGFloat
        /// 左マージン（ポイント）
        var leftMargin: CGFloat
        /// 右マージン（ポイント）
        var rightMargin: CGFloat
        /// 下マージン（ポイント）
        var bottomMargin: CGFloat
        /// スケーリング係数（1.0 = 100%）
        var scalingFactor: CGFloat
        /// 水平方向のセンタリング
        var horizontallyCentered: Bool
        /// 垂直方向のセンタリング
        var verticallyCentered: Bool
        /// 用紙名（例: "A4", "Letter"）
        var paperName: String?
        /// プリンター名
        var printerName: String?

        /// NSPrintInfo から PrintInfoData を作成
        init(from printInfo: NSPrintInfo) {
            self.paperWidth = printInfo.paperSize.width
            self.paperHeight = printInfo.paperSize.height
            self.orientation = printInfo.orientation.rawValue
            self.topMargin = printInfo.topMargin
            self.leftMargin = printInfo.leftMargin
            self.rightMargin = printInfo.rightMargin
            self.bottomMargin = printInfo.bottomMargin
            self.scalingFactor = printInfo.scalingFactor
            self.horizontallyCentered = printInfo.isHorizontallyCentered
            self.verticallyCentered = printInfo.isVerticallyCentered
            self.paperName = printInfo.paperName?.rawValue
            self.printerName = printInfo.printer.name
        }

        /// メンバーワイズイニシャライザ
        init(
            paperWidth: CGFloat,
            paperHeight: CGFloat,
            orientation: Int,
            topMargin: CGFloat,
            leftMargin: CGFloat,
            rightMargin: CGFloat,
            bottomMargin: CGFloat,
            scalingFactor: CGFloat,
            horizontallyCentered: Bool,
            verticallyCentered: Bool,
            paperName: String?,
            printerName: String?
        ) {
            self.paperWidth = paperWidth
            self.paperHeight = paperHeight
            self.orientation = orientation
            self.topMargin = topMargin
            self.leftMargin = leftMargin
            self.rightMargin = rightMargin
            self.bottomMargin = bottomMargin
            self.scalingFactor = scalingFactor
            self.horizontallyCentered = horizontallyCentered
            self.verticallyCentered = verticallyCentered
            self.paperName = paperName
            self.printerName = printerName
        }

        /// PrintInfoData を NSPrintInfo に適用
        func apply(to printInfo: NSPrintInfo) {
            printInfo.paperSize = NSSize(width: paperWidth, height: paperHeight)
            if let orientation = NSPrintInfo.PaperOrientation(rawValue: orientation) {
                printInfo.orientation = orientation
            }
            printInfo.topMargin = topMargin
            printInfo.leftMargin = leftMargin
            printInfo.rightMargin = rightMargin
            printInfo.bottomMargin = bottomMargin
            printInfo.scalingFactor = scalingFactor
            printInfo.isHorizontallyCentered = horizontallyCentered
            printInfo.isVerticallyCentered = verticallyCentered
            if let paperName = paperName {
                printInfo.paperName = NSPrinter.PaperName(rawValue: paperName)
            }
            // プリンターの設定はセキュリティ上の理由と可用性のため、復元しない
            // （プリンターが存在しない場合にエラーになる可能性がある）
        }

        static var `default`: PrintInfoData {
            // システムのデフォルト PrintInfo から作成
            PrintInfoData(from: NSPrintInfo.shared)
        }
    }

    // MARK: - Default Instances

    static var `default`: NewDocData {
        NewDocData(
            view: .default,
            format: .default,
            fontAndColors: .default,
            pageLayout: .default,
            headerFooter: .default,
            properties: .default,
            printInfo: nil  // 新規ドキュメントはシステムのデフォルトを使用
        )
    }

    static var plainText: NewDocData {
        var data = NewDocData.default
        data.format = .plainText
        data.view.showToolBar = false
        data.view.showInspectorBar = false
        data.view.docWidthType = .windowWidth
        return data
    }

    static var richText: NewDocData {
        NewDocData.default
    }
}

// MARK: - CodableColor

struct CodableColor: Codable, Equatable {
    var red: CGFloat
    var green: CGFloat
    var blue: CGFloat
    var alpha: CGFloat
    /// システムカラー名（動的カラー対応用）
    var systemColorName: String?

    /// サポートするシステムカラーのマッピング
    private static let systemColors: [String: NSColor] = [
        "textColor": .textColor,
        "textBackgroundColor": .textBackgroundColor,
        "labelColor": .labelColor,
        "secondaryLabelColor": .secondaryLabelColor,
        "tertiaryLabelColor": .tertiaryLabelColor,
        "quaternaryLabelColor": .quaternaryLabelColor,
        "controlBackgroundColor": .controlBackgroundColor,
        "selectedTextBackgroundColor": .selectedTextBackgroundColor,
        "windowBackgroundColor": .windowBackgroundColor
    ]

    init(_ color: NSColor) {
        // システムカラーかどうかチェック
        self.systemColorName = Self.systemColors.first { $0.value == color }?.key

        let converted = color.usingColorSpace(.sRGB) ?? color
        self.red = converted.redComponent
        self.green = converted.greenComponent
        self.blue = converted.blueComponent
        self.alpha = converted.alphaComponent
    }

    init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
        self.systemColorName = nil
    }

    var nsColor: NSColor {
        // システムカラー名が保存されていれば動的カラーを返す
        if let name = systemColorName, let systemColor = Self.systemColors[name] {
            return systemColor
        }
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// 動的カラーかどうか
    var isDynamic: Bool {
        systemColorName != nil
    }
}
