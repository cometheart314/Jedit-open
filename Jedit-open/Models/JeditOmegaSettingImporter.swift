//
//  JeditOmegaSettingImporter.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/17.
//

import Cocoa

/// JeditΩ の拡張属性 "jp.co.artman21.omega.settingData" を読み込み、
/// NewDocData に変換するインポーター。
/// JeditΩ で保存されたファイルを Jedit-open で開く際に、
/// Jedit-open 独自の拡張属性がない場合にフォールバックとして使用する。
class JeditOmegaSettingImporter {

    // MARK: - Constants

    /// JeditΩ の拡張属性キー
    nonisolated static let xattrKey = "jp.co.artman21.omega.settingData"

    /// 外部 plist のキー
    private nonisolated static let newDocSettingDicKey = "newDocSettingDic"

    // MARK: - JO Key Constants

    // View
    private nonisolated static let kWindowWidth       = "JOWindowWidth"
    private nonisolated static let kWindowHeight      = "JOWindowHeight"
    private nonisolated static let kWindowLocX        = "JOWindowLocX"
    private nonisolated static let kWindowLocY        = "JOWindowLocY"
    private nonisolated static let kViewScaleValue    = "JOViewSacleValue"   // JeditΩ 側のタイプミス
    private nonisolated static let kLineNumberStyle   = "JOLineNumberStyle"
    private nonisolated static let kRulerType         = "JORulerType"
    private nonisolated static let kShowInspectorBar  = "JOShowInspectorBar"
    private nonisolated static let kShowToolbar       = "JOShowToolbar"
    private nonisolated static let kPageStyle         = "JOPageStyle"
    private nonisolated static let kDocWidthStyle     = "JODocWidthStyle"
    private nonisolated static let kFixedDocWidth     = "JOFixedDocWidth"
    private nonisolated static let kReadOnly          = "JOReadOnly"

    // Format
    private nonisolated static let kEditingDirection     = "JOEditingDirection"
    private nonisolated static let kTabWidth             = "JOTabWidth"
    private nonisolated static let kInterLineSpace       = "JOInterLineSapce"     // JeditΩ 側のタイプミス
    private nonisolated static let kParaBeforeSpace      = "JOParaBeforeSapce"    // JeditΩ 側のタイプミス
    private nonisolated static let kParaAfterSpace       = "JOParaAfterSapce"     // JeditΩ 側のタイプミス
    private nonisolated static let kAutoIndentForNewLine = "JOAutoIndentForNewLine"
    private nonisolated static let kWrappedLineIndent    = "JOWrappedLineIndent"
    private nonisolated static let kWordWrappedMethod    = "JOWordWrappedMethod"
    private nonisolated static let kNewDocEncoding       = "JONewDocEncoding"
    private nonisolated static let kNewDocLineEnding     = "JONewDocLineEnding"
    private nonisolated static let kNewDocBom            = "JONewDocBom"
    private nonisolated static let kTextStyle            = "JOTextStyle"

    // Font
    private nonisolated static let kBaseFontName = "JOBaseFontName"
    private nonisolated static let kBaseFontSize = "JOBaseFontSize"

    // Colors
    private nonisolated static let kCharacterColor       = "JOCharacterColor"
    private nonisolated static let kBackgroundColor      = "JOBackgroundColor"
    private nonisolated static let kInvisibleColor       = "JOInvisibleColor"
    private nonisolated static let kCaretColor           = "JOCaretColor"
    private nonisolated static let kHighlightColor       = "JOHighlightColor"
    private nonisolated static let kLineNumColor         = "JOLineNumColor"
    private nonisolated static let kLineNumBackColor     = "JOLineNumBackColor"
    private nonisolated static let kHeaderColor          = "JOHeaderColor"
    private nonisolated static let kFooterColor          = "JOFooterColor"

    // Page Layout
    private nonisolated static let kPrintScale       = "JOPrintScale"
    private nonisolated static let kPrintOrientation = "JOPrintOrientation"
    private nonisolated static let kTopMargin        = "JOTopMargin"
    private nonisolated static let kLeftMargin       = "JOLeftMargin"
    private nonisolated static let kRightMargin      = "JORightMarin"    // JeditΩ 側のタイプミス
    private nonisolated static let kBottomMargin     = "JOBottomMargin"

    // Header/Footer
    private nonisolated static let kHeaderString = "JOHeaderString"
    private nonisolated static let kFooterString = "JOFooterString"

    // Properties
    private nonisolated static let kAuthorProperty    = "JOAuthorProperty"
    private nonisolated static let kCompanyProperty   = "JOCompanyProperty"
    private nonisolated static let kCopyrightProperty = "JOCopyrightProperty"
    private nonisolated static let kTitleProperty     = "JOTitleProperty"
    private nonisolated static let kSubjectProperty   = "JOSubjectProperty"
    private nonisolated static let kCommentProperty   = "JOCommentProperty"
    private nonisolated static let kKeywordsProperty  = "JOKeywordsProperty"

    // MARK: - Public Interface

    /// ファイルの URL から JeditΩ 設定を読み込み NewDocData を返す
    /// - Parameter url: ファイルの URL
    /// - Returns: 変換された NewDocData、失敗時は nil
    nonisolated static func importSettings(from url: URL) -> NewDocData? {
        // Step 1: 拡張属性を読み込む
        guard let xattrData = readXattr(at: url) else { return nil }

        // Step 2: 外部 plist をパースして newDocSettingDic の NSData を取得
        guard let settingData = extractNewDocSettingData(from: xattrData) else { return nil }

        // Step 3: NSArchiver でアーカイブされた NSDictionary をデコード
        guard let settingDict = unarchiveDictionary(from: settingData) else { return nil }

        // Step 4: NSDictionary から NewDocData を構築
        let result = mapToNewDocData(from: settingDict)

        #if DEBUG
        Swift.print("JeditOmegaSettingImporter: Successfully imported settings from \(url.lastPathComponent)")
        #endif

        return result
    }

    /// JeditΩ の印刷設定（orientation, margins, scale）を既存の NSPrintInfo に直接適用する。
    /// paperSize は変更しない（ドキュメントの RTF document attributes から設定された値を維持する）。
    /// - Parameters:
    ///   - url: ファイルの URL
    ///   - printInfo: 適用先の NSPrintInfo（通常は document.printInfo）
    nonisolated static func applyPrintSettings(from url: URL, to printInfo: NSPrintInfo) {
        guard let xattrData = readXattr(at: url),
              let settingData = extractNewDocSettingData(from: xattrData),
              let dict = unarchiveDictionary(from: settingData) else { return }

        // Page Orientation: portrait(0) / landscape(1)
        if let v = intValue(dict, kPrintOrientation),
           let orientation = NSPrintInfo.PaperOrientation(rawValue: v) {
            printInfo.orientation = orientation
        }

        // Margins
        if let v = floatValue(dict, kTopMargin)    { printInfo.topMargin = v }
        if let v = floatValue(dict, kLeftMargin)   { printInfo.leftMargin = v }
        if let v = floatValue(dict, kRightMargin)  { printInfo.rightMargin = v }
        if let v = floatValue(dict, kBottomMargin) { printInfo.bottomMargin = v }

        // Scale
        if let v = floatValue(dict, kPrintScale)   { printInfo.scalingFactor = v }
    }

    // MARK: - Private: Xattr Reading

    /// 拡張属性を読み込む
    private nonisolated static func readXattr(at url: URL) -> Data? {
        let size = getxattr(url.path, xattrKey, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buffer -> ssize_t in
            getxattr(url.path, xattrKey, buffer.baseAddress, size, 0, 0)
        }
        guard result > 0 else { return nil }
        return data
    }

    // MARK: - Private: Outer Plist Parsing

    /// 外部 plist を解析し newDocSettingDic の NSData を取り出す
    private nonisolated static func extractNewDocSettingData(from xattrData: Data) -> Data? {
        guard let plist = try? PropertyListSerialization.propertyList(
            from: xattrData, options: [], format: nil
        ) as? [String: Any] else {
            #if DEBUG
            Swift.print("JeditOmegaSettingImporter: Failed to parse outer plist")
            #endif
            return nil
        }
        return plist[newDocSettingDicKey] as? Data
    }

    // MARK: - Private: NSUnarchiver Decoding

    /// NSArchiver でアーカイブされた NSData を NSDictionary にデコード
    /// NSUnarchiver はレガシー NSArchiver 形式のデコードに必須（代替なし）
    private nonisolated static func unarchiveDictionary(from data: Data) -> NSDictionary? {
        // NSUnarchiver は deprecated だが、レガシー NSArchiver 形式のデコードには必須
        let result = NSUnarchiver.unarchiveObject(with: data) as? NSDictionary
        #if DEBUG
        if result == nil {
            Swift.print("JeditOmegaSettingImporter: Failed to unarchive NSDictionary")
        }
        #endif
        return result
    }

    /// NSArchiver でアーカイブされた NSColor をデコード
    private nonisolated static func unarchiveColor(from data: Data) -> NSColor? {
        return NSUnarchiver.unarchiveObject(with: data) as? NSColor
    }

    // MARK: - Private: Mapping

    /// NSDictionary から NewDocData を構築
    private nonisolated static func mapToNewDocData(from dict: NSDictionary) -> NewDocData {
        var data = NewDocData.default

        // View
        data.view = mapViewData(from: dict)

        // Format
        data.format = mapFormatData(from: dict)

        // Font & Colors
        data.fontAndColors = mapFontAndColorsData(from: dict)

        // Page Layout
        data.pageLayout = mapPageLayoutData(from: dict)

        // Header/Footer
        data.headerFooter = mapHeaderFooterData(from: dict)

        // Properties
        data.properties = mapPropertiesData(from: dict)

        // PrintInfo（orientation, margins, scale）は presetData に含めない。
        // Document.swift 側で document.printInfo に直接適用する。
        // （PrintInfoData.default の paperSize がドキュメントの実際の paperSize を
        //   上書きしてしまい、ページ表示や縦書きが壊れるため）

        // preventEditing は ViewData に格納
        if let readOnly = boolValue(dict, kReadOnly) {
            data.view.preventEditing = readOnly
        }

        return data
    }

    // MARK: - Private: Sub-mapping

    private nonisolated static func mapViewData(from dict: NSDictionary) -> NewDocData.ViewData {
        var view = NewDocData.ViewData.default

        if let v = floatValue(dict, kWindowWidth)  { view.windowWidth = v }
        if let v = floatValue(dict, kWindowHeight) { view.windowHeight = v }
        if let v = floatValue(dict, kWindowLocX)   { view.windowX = v }
        if let v = floatValue(dict, kWindowLocY)   { view.windowY = v }
        if let v = floatValue(dict, kViewScaleValue), v > 0 { view.scale = v }

        if let v = intValue(dict, kLineNumberStyle),
           let lineNumType = NewDocData.ViewData.LineNumberType(rawValue: v) {
            view.lineNumberType = lineNumType
        }
        if let v = intValue(dict, kRulerType),
           let rulerType = NewDocData.ViewData.RulerType(rawValue: v) {
            view.rulerType = rulerType
        }
        if let v = boolValue(dict, kShowInspectorBar) { view.showInspectorBar = v }
        if let v = boolValue(dict, kShowToolbar)      { view.showToolBar = v }
        if let v = intValue(dict, kPageStyle)         { view.pageMode = (v != 0) }
        if let v = intValue(dict, kDocWidthStyle),
           let docWidthType = NewDocData.ViewData.DocWidthType(rawValue: v) {
            view.docWidthType = docWidthType
        }
        if let v = intValue(dict, kFixedDocWidth) { view.fixedDocWidth = v }

        // JOShowInvisiblesFlag: 形式不明のためスキップ（デフォルト値を使用）

        return view
    }

    private nonisolated static func mapFormatData(from dict: NSDictionary) -> NewDocData.FormatData {
        var format = NewDocData.FormatData.default

        if let v = intValue(dict, kEditingDirection),
           let dir = NewDocData.FormatData.EditingDirection(rawValue: v) {
            format.editingDirection = dir
        }
        if let v = floatValue(dict, kTabWidth)        { format.tabWidthPoints = v }
        if let v = floatValue(dict, kInterLineSpace)  { format.interLineSpacing = v }
        if let v = floatValue(dict, kParaBeforeSpace)  { format.paragraphSpacingBefore = v }
        if let v = floatValue(dict, kParaAfterSpace)   { format.paragraphSpacingAfter = v }
        if let v = boolValue(dict, kAutoIndentForNewLine) { format.autoIndent = v }
        if let v = floatValue(dict, kWrappedLineIndent)   { format.wrappedLineIndent = v }
        if let v = intValue(dict, kWordWrappedMethod),
           let wrapType = NewDocData.FormatData.WordWrappingType(rawValue: v) {
            format.wordWrappingType = wrapType
        }

        // Encoding: NSStringEncoding rawValue と String.Encoding.rawValue は同一
        if let encNum = dict[kNewDocEncoding] as? NSNumber {
            format.textEncoding = UInt(encNum.uintValue)
        }

        // Line ending
        if let v = intValue(dict, kNewDocLineEnding),
           let le = NewDocData.FormatData.LineEndingType(rawValue: v) {
            format.lineEndingType = le
        }

        if let v = boolValue(dict, kNewDocBom) { format.bom = v }

        // Text style: 0 = plain, 非0 = rich
        if let textStyle = intValue(dict, kTextStyle) {
            format.richText = (textStyle != 0)
            format.fileExtension = (textStyle != 0) ? "" : "txt"
        }

        return format
    }

    private nonisolated static func mapFontAndColorsData(from dict: NSDictionary) -> NewDocData.FontAndColorsData {
        var fac = NewDocData.FontAndColorsData.default

        if let name = stringValue(dict, kBaseFontName) { fac.baseFontName = name }
        if let size = floatValue(dict, kBaseFontSize)  { fac.baseFontSize = size }

        if let c = codableColor(dict, kCharacterColor)  { fac.colors.character = c }
        if let c = codableColor(dict, kBackgroundColor)  { fac.colors.background = c }
        if let c = codableColor(dict, kInvisibleColor)   { fac.colors.invisible = c }
        if let c = codableColor(dict, kCaretColor)       { fac.colors.caret = c }
        if let c = codableColor(dict, kHighlightColor)   { fac.colors.highlight = c }
        if let c = codableColor(dict, kLineNumColor)     { fac.colors.lineNumber = c }
        if let c = codableColor(dict, kLineNumBackColor) { fac.colors.lineNumberBackground = c }
        if let c = codableColor(dict, kHeaderColor)      { fac.colors.header = c }
        if let c = codableColor(dict, kFooterColor)      { fac.colors.footer = c }

        return fac
    }

    private nonisolated static func mapPageLayoutData(from dict: NSDictionary) -> NewDocData.PageLayoutData {
        var layout = NewDocData.PageLayoutData.default

        if let v = floatValue(dict, kPrintScale)   { layout.printScale = v }
        if let v = floatValue(dict, kTopMargin)    { layout.topMarginPoints = v }
        if let v = floatValue(dict, kLeftMargin)   { layout.leftMarginPoints = v }
        if let v = floatValue(dict, kRightMargin)  { layout.rightMarginPoints = v }
        if let v = floatValue(dict, kBottomMargin) { layout.bottomMarginPoints = v }

        return layout
    }

    private nonisolated static func mapHeaderFooterData(from dict: NSDictionary) -> NewDocData.HeaderFooterData {
        var hf = NewDocData.HeaderFooterData.default

        // JeditΩ はヘッダー/フッターをプレーン文字列で保存
        // RTF Data に変換して格納
        if let headerStr = stringValue(dict, kHeaderString), !headerStr.isEmpty {
            let attrStr = NSAttributedString(
                string: headerStr,
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            hf.headerRTFData = NewDocData.HeaderFooterData.rtfData(from: attrStr)
        }
        if let footerStr = stringValue(dict, kFooterString), !footerStr.isEmpty {
            let attrStr = NSAttributedString(
                string: footerStr,
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            hf.footerRTFData = NewDocData.HeaderFooterData.rtfData(from: attrStr)
        }

        return hf
    }

    private nonisolated static func mapPropertiesData(from dict: NSDictionary) -> NewDocData.PropertiesData {
        var props = NewDocData.PropertiesData.default

        if let v = stringValue(dict, kAuthorProperty)    { props.author = v }
        if let v = stringValue(dict, kCompanyProperty)   { props.company = v }
        if let v = stringValue(dict, kCopyrightProperty) { props.copyright = v }
        if let v = stringValue(dict, kTitleProperty)     { props.title = v }
        if let v = stringValue(dict, kSubjectProperty)   { props.subject = v }
        if let v = stringValue(dict, kCommentProperty)   { props.comment = v }
        if let v = stringValue(dict, kKeywordsProperty)  { props.keywords = v }

        return props
    }

    // MARK: - Private: Value Extractors

    private nonisolated static func floatValue(_ dict: NSDictionary, _ key: String) -> CGFloat? {
        guard let num = dict[key] as? NSNumber else { return nil }
        return CGFloat(num.doubleValue)
    }

    private nonisolated static func intValue(_ dict: NSDictionary, _ key: String) -> Int? {
        guard let num = dict[key] as? NSNumber else { return nil }
        return num.intValue
    }

    private nonisolated static func boolValue(_ dict: NSDictionary, _ key: String) -> Bool? {
        guard let num = dict[key] as? NSNumber else { return nil }
        return num.boolValue
    }

    private nonisolated static func stringValue(_ dict: NSDictionary, _ key: String) -> String? {
        return dict[key] as? String
    }

    /// NSArchiver でアーカイブされた NSColor データを CodableColor に変換
    private nonisolated static func codableColor(_ dict: NSDictionary, _ key: String) -> CodableColor? {
        guard let colorData = dict[key] as? Data else { return nil }
        guard let color = unarchiveColor(from: colorData) else {
            #if DEBUG
            Swift.print("JeditOmegaSettingImporter: Failed to unarchive color for key: \(key)")
            #endif
            return nil
        }
        return CodableColor(color)
    }
}
