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
                showInvisibles: .default
            )
        }
    }

    // MARK: - FormatData

    struct FormatData: Codable, Equatable {
        var newDocNameType: NewDocNameType
        var richText: Bool
        var textEncoding: String.Encoding.RawValue
        var lineEndingType: LineEndingType
        var bom: Bool
        var editingDirection: EditingDirection
        var tabWidthPoints: CGFloat  // タブ幅（ポイント単位で内部保存）
        var tabWidthUnit: TabWidthUnit  // タブ幅の表示単位
        var interLineSpacing: CGFloat
        var paragraphSpacingBefore: CGFloat
        var paragraphSpacingAfter: CGFloat
        var autoIndent: Bool
        var wrappedLineIndent: CGFloat
        var wordWrappingType: WordWrappingType
        var targetSize: Int
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
            case noWrap = 0
            case wrapAtWindow = 1
            case wrapAtCharacters = 2
        }

        enum TabWidthUnit: Int, Codable {
            case points = 0
            case spaces = 1
        }

        static var `default`: FormatData {
            FormatData(
                newDocNameType: .untitled,
                richText: true,
                textEncoding: String.Encoding.utf8.rawValue,
                lineEndingType: .lf,
                bom: false,
                editingDirection: .leftToRight,
                tabWidthPoints: 28.0,  // 約4スペース分（7pt/スペース × 4）
                tabWidthUnit: .points,
                interLineSpacing: 0,
                paragraphSpacingBefore: 0,
                paragraphSpacingAfter: 0,
                autoIndent: true,
                wrappedLineIndent: 0,
                wordWrappingType: .wrapAtWindow,
                targetSize: 80,
                minTargetSize: 40,
                maxTargetSize: 200
            )
        }

        static var plainText: FormatData {
            var data = FormatData.default
            data.richText = false
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
        var topMargin: CGFloat
        var leftMargin: CGFloat
        var rightMargin: CGFloat
        var bottomMargin: CGFloat
        var marginUnit: MarginUnit
        var printScale: CGFloat

        enum MarginUnit: Int, Codable {
            case centimeter = 0
            case inch = 1
            case point = 2
        }

        static var `default`: PageLayoutData {
            PageLayoutData(
                topMargin: 2.0,
                leftMargin: 2.0,
                rightMargin: 2.0,
                bottomMargin: 2.0,
                marginUnit: .centimeter,
                printScale: 1.0
            )
        }
    }

    // MARK: - HeaderFooterData

    struct HeaderFooterData: Codable, Equatable {
        var headerText: String
        var footerText: String

        static var `default`: HeaderFooterData {
            HeaderFooterData(
                headerText: "",
                footerText: ""
            )
        }
    }

    // MARK: - PropertiesData

    struct PropertiesData: Codable, Equatable {
        var author: String
        var company: String
        var copyright: String

        static var `default`: PropertiesData {
            PropertiesData(
                author: "",
                company: "",
                copyright: ""
            )
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
            properties: .default
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

    init(_ color: NSColor) {
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
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}
