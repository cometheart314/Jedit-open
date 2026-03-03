//
//  TextStyle.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/26.
//

import Cocoa

// MARK: - FontWeight

enum FontWeight: String, Codable, CaseIterable {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black

    var nsFontWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    var displayName: String {
        switch self {
        case .ultraLight: return "Ultra Light".localized
        case .thin: return "Thin".localized
        case .light: return "Light".localized
        case .regular: return "Regular".localized
        case .medium: return "Medium".localized
        case .semibold: return "Semibold".localized
        case .bold: return "Bold".localized
        case .heavy: return "Heavy".localized
        case .black: return "Black".localized
        }
    }
}

// MARK: - UnderlineStyle

enum UnderlineStyle: Int, Codable, CaseIterable {
    case none = 0
    case single = 1       // NSUnderlineStyle.single
    case thick = 2        // NSUnderlineStyle.thick
    case double = 9       // NSUnderlineStyle.double

    var nsUnderlineStyle: NSUnderlineStyle {
        switch self {
        case .none: return []
        case .single: return .single
        case .thick: return .thick
        case .double: return .double
        }
    }

    var displayName: String {
        switch self {
        case .none: return "None".localized
        case .single: return "Single".localized
        case .thick: return "Thick".localized
        case .double: return "Double".localized
        }
    }
}

// MARK: - TextAlignment

enum TextAlignment: String, Codable, CaseIterable {
    case left
    case center
    case right
    case justified
    case natural

    var nsAlignment: NSTextAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .justified: return .justified
        case .natural: return .natural
        }
    }

    var displayName: String {
        switch self {
        case .left: return "Left".localized
        case .center: return "Center".localized
        case .right: return "Right".localized
        case .justified: return "Justified".localized
        case .natural: return "Natural".localized
        }
    }
}

// MARK: - TextStyle

struct TextStyle: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var keyEquivalent: String?          // ショートカットキー（オプション）
    var keyEquivalentModifierRawValue: UInt?  // 修飾キーマスク（NSEvent.ModifierFlags.rawValue）
    var isBuiltIn: Bool

    /// ビルトインスタイルはローカライズされた名前を返す
    var displayName: String {
        return isBuiltIn ? name.localized : name
    }

    /// 修飾キーの取得・設定（Codable非対応のNSEvent.ModifierFlagsをラップ）
    var keyEquivalentModifierMask: NSEvent.ModifierFlags {
        get {
            if let raw = keyEquivalentModifierRawValue {
                return NSEvent.ModifierFlags(rawValue: raw)
            }
            return [.command]  // デフォルトは⌘
        }
        set {
            keyEquivalentModifierRawValue = newValue.rawValue
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, keyEquivalent, keyEquivalentModifierRawValue, isBuiltIn
        case fontFamily, fontSize, fontWeight, isItalic
        case foregroundColor, backgroundColor
        case underlineStyle, underlineColor, strikethroughStyle, strikethroughColor
        case baselineOffset, kern, superscript, ligature
        case alignment, lineSpacing, paragraphSpacing, paragraphSpacingBefore
        case headIndent, tailIndent, firstLineHeadIndent, lineHeightMultiple, hyphenationFactor
    }

    // MARK: - 文字属性（Character Attributes）

    var fontFamily: String?             // nil = 適用しない
    var fontSize: CGFloat?
    var fontWeight: FontWeight?         // thin, regular, bold, etc.
    var isItalic: Bool?

    var foregroundColor: CodableColor?
    var backgroundColor: CodableColor?

    var underlineStyle: UnderlineStyle?
    var underlineColor: CodableColor?
    var strikethroughStyle: UnderlineStyle?
    var strikethroughColor: CodableColor?

    var baselineOffset: CGFloat?
    var kern: CGFloat?                  // 文字間隔

    var superscript: Int?               // 1=上付き, -1=下付き
    var ligature: Int?                  // 0=無効, 1=デフォルト

    // MARK: - 段落属性（Paragraph Attributes）

    var alignment: TextAlignment?
    var lineSpacing: CGFloat?
    var paragraphSpacing: CGFloat?
    var paragraphSpacingBefore: CGFloat?
    var headIndent: CGFloat?
    var tailIndent: CGFloat?
    var firstLineHeadIndent: CGFloat?
    var lineHeightMultiple: CGFloat?
    var hyphenationFactor: Float?

    // MARK: - Initializer

    init(id: UUID = UUID(), name: String, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
    }

    // MARK: - 段落属性の有無チェック

    var hasParagraphAttributes: Bool {
        alignment != nil ||
        lineSpacing != nil ||
        paragraphSpacing != nil ||
        paragraphSpacingBefore != nil ||
        headIndent != nil ||
        tailIndent != nil ||
        firstLineHeadIndent != nil ||
        lineHeightMultiple != nil ||
        hyphenationFactor != nil
    }

    // MARK: - 属性の生成

    /// スタイルに設定された属性のみを辞書として返す（nilの属性はスキップ）
    func attributes() -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [:]

        // フォント構築（family, size, weight, italic のいずれかが指定されていれば）
        if fontFamily != nil || fontSize != nil || fontWeight != nil || isItalic != nil {
            var traits = NSFontDescriptor.SymbolicTraits()
            if let weight = fontWeight, weight == .bold || weight == .heavy || weight == .black {
                traits.insert(.bold)
            }
            if isItalic == true {
                traits.insert(.italic)
            }

            let family = fontFamily ?? "Helvetica"
            var descriptor = NSFontDescriptor()
                .withFamily(family)
            if !traits.isEmpty {
                descriptor = descriptor.withSymbolicTraits(traits)
            }
            // Weight を trait attribute として追加
            if let weight = fontWeight {
                let weightTrait: [NSFontDescriptor.TraitKey: Any] = [.weight: weight.nsFontWeight]
                descriptor = descriptor.addingAttributes([.traits: weightTrait])
            }

            let size = fontSize ?? NSFont.systemFontSize
            if let font = NSFont(descriptor: descriptor, size: size) {
                attrs[.font] = font
            }
        }

        if let color = foregroundColor {
            attrs[.foregroundColor] = color.nsColor
        }
        if let color = backgroundColor {
            attrs[.backgroundColor] = color.nsColor
        }

        if let style = underlineStyle {
            attrs[.underlineStyle] = style.nsUnderlineStyle.rawValue
        }
        if let color = underlineColor {
            attrs[.underlineColor] = color.nsColor
        }
        if let style = strikethroughStyle {
            attrs[.strikethroughStyle] = style.nsUnderlineStyle.rawValue
        }
        if let color = strikethroughColor {
            attrs[.strikethroughColor] = color.nsColor
        }

        if let offset = baselineOffset {
            attrs[.baselineOffset] = offset
        }
        if let k = kern {
            attrs[.kern] = k
        }
        if let sup = superscript {
            attrs[.superscript] = sup
        }
        if let lig = ligature {
            attrs[.ligature] = lig
        }

        // 段落属性
        if hasParagraphAttributes {
            let para = NSMutableParagraphStyle()
            if let a = alignment { para.alignment = a.nsAlignment }
            if let s = lineSpacing { para.lineSpacing = s }
            if let s = paragraphSpacing { para.paragraphSpacing = s }
            if let s = paragraphSpacingBefore { para.paragraphSpacingBefore = s }
            if let i = headIndent { para.headIndent = i }
            if let i = tailIndent { para.tailIndent = i }
            if let i = firstLineHeadIndent { para.firstLineHeadIndent = i }
            if let m = lineHeightMultiple { para.lineHeightMultiple = m }
            if let h = hyphenationFactor { para.hyphenationFactor = h }
            attrs[.paragraphStyle] = para
        }

        return attrs
    }

    /// 既存属性とマージして適用（nilの属性は既存値を保持）
    func mergedAttributes(with existing: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var result = existing
        for (key, value) in attributes() {
            if key == .paragraphStyle,
               let newPara = value as? NSParagraphStyle,
               let existingPara = existing[.paragraphStyle] as? NSMutableParagraphStyle {
                result[key] = Self.mergeParagraphStyles(existing: existingPara, new: newPara)
            } else if key == .font,
                      let newFont = value as? NSFont,
                      let existingFont = existing[.font] as? NSFont {
                result[key] = Self.mergeFonts(existing: existingFont, new: newFont, style: self)
            } else {
                result[key] = value
            }
        }
        return result
    }

    // MARK: - Private Merge Helpers

    /// 段落スタイルのマージ: スタイルで指定された属性のみ上書き
    private static func mergeParagraphStyles(existing: NSParagraphStyle, new: NSParagraphStyle) -> NSParagraphStyle {
        let merged = existing.mutableCopy() as! NSMutableParagraphStyle
        // new で設定されている値を上書き（デフォルト値でなければ）
        if new.alignment != .natural { merged.alignment = new.alignment }
        if new.lineSpacing != 0 { merged.lineSpacing = new.lineSpacing }
        if new.paragraphSpacing != 0 { merged.paragraphSpacing = new.paragraphSpacing }
        if new.paragraphSpacingBefore != 0 { merged.paragraphSpacingBefore = new.paragraphSpacingBefore }
        if new.headIndent != 0 { merged.headIndent = new.headIndent }
        if new.tailIndent != 0 { merged.tailIndent = new.tailIndent }
        if new.firstLineHeadIndent != 0 { merged.firstLineHeadIndent = new.firstLineHeadIndent }
        if new.lineHeightMultiple != 0 { merged.lineHeightMultiple = new.lineHeightMultiple }
        if new.hyphenationFactor != 0 { merged.hyphenationFactor = new.hyphenationFactor }
        return merged
    }

    /// フォントのマージ: スタイルで指定された属性のみ上書き
    private static func mergeFonts(existing: NSFont, new: NSFont, style: TextStyle) -> NSFont {
        let family = style.fontFamily ?? existing.familyName ?? existing.fontName
        let size = style.fontSize ?? existing.pointSize

        var descriptor = NSFontDescriptor().withFamily(family)

        // 既存のtraitを保持しつつ、指定されたものだけ上書き
        var traits = existing.fontDescriptor.symbolicTraits
        if let weight = style.fontWeight {
            if weight == .bold || weight == .heavy || weight == .black {
                traits.insert(.bold)
            } else {
                traits.remove(.bold)
            }
        }
        if let italic = style.isItalic {
            if italic {
                traits.insert(.italic)
            } else {
                traits.remove(.italic)
            }
        }
        descriptor = descriptor.withSymbolicTraits(traits)

        if let weight = style.fontWeight {
            let weightTrait: [NSFontDescriptor.TraitKey: Any] = [.weight: weight.nsFontWeight]
            descriptor = descriptor.addingAttributes([.traits: weightTrait])
        }

        return NSFont(descriptor: descriptor, size: size) ?? existing
    }

    // MARK: - Built-in Styles

    static var builtInHeading1: TextStyle {
        var style = TextStyle(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
            name: "Heading 1",
            isBuiltIn: true
        )
        style.fontSize = 28
        style.fontWeight = .bold
        return style
    }

    static var builtInHeading2: TextStyle {
        var style = TextStyle(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
            name: "Heading 2",
            isBuiltIn: true
        )
        style.fontSize = 22
        style.fontWeight = .bold
        return style
    }

    static var builtInHeading3: TextStyle {
        var style = TextStyle(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000003")!,
            name: "Heading 3",
            isBuiltIn: true
        )
        style.fontSize = 18
        style.fontWeight = .semibold
        return style
    }

    static var builtInEmphasis: TextStyle {
        var style = TextStyle(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
            name: "Emphasis",
            isBuiltIn: true
        )
        style.isItalic = true
        return style
    }

    static var builtInStrong: TextStyle {
        var style = TextStyle(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
            name: "Strong",
            isBuiltIn: true
        )
        style.fontWeight = .bold
        return style
    }

    static var builtInCode: TextStyle {
        var style = TextStyle(
            id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
            name: "Code",
            isBuiltIn: true
        )
        style.fontFamily = "Menlo"
        style.fontSize = 12
        style.backgroundColor = CodableColor(red: 0.95, green: 0.95, blue: 0.95)
        return style
    }

    static var builtInStyles: [TextStyle] {
        [builtInHeading1, builtInHeading2, builtInHeading3, builtInEmphasis, builtInStrong, builtInCode]
    }
}

// MARK: - StyleCollection

struct StyleCollection: Codable {
    var version: Int = 1
    var styles: [TextStyle]

    init(styles: [TextStyle] = TextStyle.builtInStyles) {
        self.styles = styles
    }
}
