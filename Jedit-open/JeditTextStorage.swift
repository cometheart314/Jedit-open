//
//  JeditTextStorage.swift
//  Jedit-open
//
//  Based on JOTextStorage.m from Jedit Omega
//

import Cocoa

/// カスタム行折り返し処理をサポートするNSTextStorageサブクラス
/// Jedit Ωの JOTextStorage.m を参考に実装
class JeditTextStorage: NSTextStorage {

    // MARK: - Properties

    /// 内部ストレージ
    private let storage = NSMutableAttributedString()

    /// 行折り返しタイプ (0: システムデフォルト, 1: 日本語禁則, 2: 折り返しなし)
    var lineBreakingType: Int = 0

    /// editing のネスト管理用カウンター
    private var editingCount: Int = 0

    /// 禁則文字セット
    private var topKinsokuChars: CharacterSet = CharacterSet()
    private var endKinsokuChars: CharacterSet = CharacterSet()
    private var burasagariChars: CharacterSet = CharacterSet()
    private var bunriKinshiChars: CharacterSet = CharacterSet()

    /// Latin文字の最大コードポイント
    private let latinMax: unichar = 0x0600

    // MARK: - Initialization

    override init() {
        super.init()
        loadKinsokuCharacters()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        loadKinsokuCharacters()
    }

    required init?(pasteboardPropertyList: Any, ofType type: NSPasteboard.PasteboardType) {
        fatalError("init(pasteboardPropertyList:ofType:) has not been implemented")
    }

    // MARK: - NSTextStorage Required Overrides

    override var string: String {
        return storage.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key : Any] {
        var loc = location
        let len = storage.length

        if loc > 0 && loc >= len {
            if loc > len {
                print("JeditTextStorage: index exceeds text length!! location \(loc) len = \(len)")
            }
            loc = len - 1
        }

        if len == 0 {
            return [:]
        }

        return storage.attributes(at: loc, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        var adjustedRange = range
        let len = storage.length

        if NSMaxRange(range) > len {
            print("JeditTextStorage: range exceeds text length!!")
            if range.location >= len {
                adjustedRange = NSRange(location: max(0, len - 1), length: 0)
            } else {
                adjustedRange.length = len - range.location
            }
        }

        storage.replaceCharacters(in: adjustedRange, with: str)

        // NSStringのlengthを使用（UTF-16コードユニット数）
        let delta = (str as NSString).length - adjustedRange.length
        edited(.editedCharacters, range: adjustedRange, changeInLength: delta)
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key : Any]?, range: NSRange) {
        var adjustedRange = range
        let len = storage.length

        if NSMaxRange(range) > len {
            print("JeditTextStorage: range exceeds text length!!")
            if range.location >= len {
                adjustedRange = NSRange(location: max(0, len - 1), length: 0)
            } else {
                adjustedRange.length = len - range.location
            }
        }

        storage.setAttributes(attrs, range: adjustedRange)
        edited(.editedAttributes, range: adjustedRange, changeInLength: 0)
    }

    // MARK: - Editing Management (ネスト対応)

    override func beginEditing() {
        editingCount += 1
        if editingCount == 1 {
            super.beginEditing()
        }
    }

    override func endEditing() {
        if editingCount < 0 {
            print("*** JeditTextStorage: too many endEditing ****")
            editingCount = 0
        } else {
            if editingCount == 1 {
                super.endEditing()
            }
            editingCount -= 1
        }
    }

    var isEditing: Bool {
        return editingCount > 0
    }

    // MARK: - Line Breaking Override

    override func lineBreak(before location: Int, within aRange: NSRange) -> Int {
        if lineBreakingType == 1 {
            // Burasagari Kinsoku
            return burasagariKinsokuLineBreak(before: location, within: aRange)
        } else if lineBreakingType == 2 {
            // No word wrapping
            return NSMaxRange(aRange) - 1
        } else {
            // System Default
            return super.lineBreak(before: location, within: aRange)
        }
    }

    private func burasagariKinsokuLineBreak(before location: Int, within aRange: NSRange) -> Int {
        let defaultBreak = super.lineBreak(before: location, within: aRange)
        let delta = NSMaxRange(aRange) - defaultBreak

        var maxIndex = NSMaxRange(aRange) - 1
        if maxIndex < defaultBreak {
            maxIndex = defaultBreak
        }

        let nsString = string as NSString
        let len = nsString.length

        // 範囲チェック
        guard defaultBreak < len, maxIndex >= 1, maxIndex - 1 < len else {
            return defaultBreak
        }

        let charD = nsString.character(at: defaultBreak)

        if charD < latinMax && delta > 0 {
            return defaultBreak
        }

        let charC = nsString.character(at: maxIndex - 1)

        // ぶら下げ文字チェック
        if let scalar = Unicode.Scalar(charC), burasagariChars.contains(scalar) {
            return maxIndex
        }

        // 全角・半角スペース
        if charC == 0x3000 || charC == 0x0020 {
            return maxIndex
        }

        // Latin文字
        if charC < latinMax {
            var ret = maxIndex
            var currentChar = charC
            while currentChar == 0x005F /* _ */ || isAlphanumeric(currentChar) {
                ret -= 1
                if ret < 1 { break }
                currentChar = nsString.character(at: ret - 1)
            }
            return ret
        }

        // 行頭禁則文字
        if let scalar = Unicode.Scalar(charC), topKinsokuChars.contains(scalar) {
            return maxIndex - 2
        }

        // maxIndex - 2 の範囲チェック
        guard maxIndex >= 2, maxIndex - 2 < len else {
            return maxIndex - 1
        }

        let charB = nsString.character(at: maxIndex - 2)

        // 行末禁則
        if let scalarB = Unicode.Scalar(charB), endKinsokuChars.contains(scalarB) {
            return maxIndex - 2
        }

        // 分離禁止
        if let scalarB = Unicode.Scalar(charB),
           let scalarC = Unicode.Scalar(charC),
           bunriKinshiChars.contains(scalarB) && bunriKinshiChars.contains(scalarC) {
            return maxIndex - 2
        }

        return maxIndex - 1
    }

    // MARK: - Helper Methods

    private func isAlphanumeric(_ char: unichar) -> Bool {
        return (char >= 0x30 && char <= 0x39) ||  // 0-9
               (char >= 0x41 && char <= 0x5A) ||  // A-Z
               (char >= 0x61 && char <= 0x7A)     // a-z
    }

    /// UserDefaultsから禁則文字を読み込み
    func loadKinsokuCharacters() {
        let defaults = UserDefaults.standard

        if let topChars = defaults.string(forKey: UserDefaults.Keys.cantBeTopChars), !topChars.isEmpty {
            topKinsokuChars = CharacterSet(charactersIn: topChars)
        }
        if let endChars = defaults.string(forKey: UserDefaults.Keys.cantBeEndChars), !endChars.isEmpty {
            endKinsokuChars = CharacterSet(charactersIn: endChars)
        }
        if let burasagari = defaults.string(forKey: UserDefaults.Keys.burasagariChars), !burasagari.isEmpty {
            burasagariChars = CharacterSet(charactersIn: burasagari)
        }
        if let bunriKinshi = defaults.string(forKey: UserDefaults.Keys.cantSeparateChars), !bunriKinshi.isEmpty {
            bunriKinshiChars = CharacterSet(charactersIn: bunriKinshi)
        }
    }

    /// 禁則文字を更新
    func updateKinsokuCharacters() {
        loadKinsokuCharacters()
    }

    /// レイアウトの再計算を要求
    func invalidateLayout() {
        let fullRange = NSRange(location: 0, length: length)
        for layoutManager in layoutManagers {
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        }
    }
}
