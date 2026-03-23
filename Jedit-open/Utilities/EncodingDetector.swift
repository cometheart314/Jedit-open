//
//  EncodingDetector.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/02.
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

import Foundation

/// エンコーディング検出結果
struct EncodingDetectionResult: Sendable {
    /// 検出されたエンコーディング
    let encoding: String.Encoding
    /// エンコーディング名
    let name: String
    /// 信頼度 (0-100)
    let confidence: Int32
    /// ロスのある変換が発生したか
    let usedLossyConversion: Bool

    nonisolated init(encoding: String.Encoding, name: String? = nil, confidence: Int32, usedLossyConversion: Bool = false) {
        self.encoding = encoding
        self.name = name ?? String.localizedName(of: encoding)
        self.confidence = confidence
        self.usedLossyConversion = usedLossyConversion
    }
}

/// エンコーディング検出の結果型
enum EncodingDetectionOutcome: Sendable {
    /// 自動判定成功
    case success(encoding: String.Encoding, string: String)
    /// 信頼度が低いため候補リストを返す（ユーザーに選択を求める）
    case needsUserSelection(candidates: [EncodingDetectionResult])
    /// 判定失敗
    case failure
}

/// テキストファイルのエンコーディングを自動判定するクラス
/// Sendableとしてマークし、任意のスレッドから呼び出し可能
final class EncodingDetector: Sendable {

    // MARK: - Singleton

    nonisolated static let shared = EncodingDetector()

    private init() {}

    // MARK: - Constants

    /// 信頼度の閾値（これ以下の場合はユーザーに選択を求める）
    nonisolated static let confidenceThreshold: Int32 = 50

    // MARK: - Extended Attribute Key

    /// テキストエンコーディングを保存する拡張属性のキー
    nonisolated static let textEncodingXattrKey = "com.apple.TextEncoding"

    // MARK: - Public Methods

    /// データからエンコーディングを判定する
    /// - Parameters:
    ///   - data: 判定対象のデータ
    ///   - fileURL: ファイルURL（拡張属性取得用、オプション）
    ///   - suggestedEncodings: 候補となるエンコーディングのリスト（nilの場合はEncodingManagerから取得）
    /// - Returns: 検出結果の配列（信頼度順）
    nonisolated func detectEncodings(from data: Data, fileURL: URL? = nil, suggestedEncodings: [String.Encoding]? = nil) -> [EncodingDetectionResult] {
        // 空データの場合
        guard !data.isEmpty else {
            return [EncodingDetectionResult(encoding: .utf8, confidence: 100)]
        }

        var results: [EncodingDetectionResult] = []

        // 1. BOMによる判定を最優先
        if let bomResult = detectEncodingFromBOM(data) {
            results.append(bomResult)
            // BOMが見つかった場合は確定
            return results
        }

        // 2. 拡張属性（com.apple.TextEncoding）による判定
        if let url = fileURL,
           let xattrResult = detectEncodingFromExtendedAttribute(url, data: data) {
            results.append(xattrResult)
            // 拡張属性でデコード成功した場合は確定
            return results
        }

        // 3. NSString.stringEncoding で候補を取得
        let nsStringResults = detectWithNSString(data, suggestedEncodings: suggestedEncodings)
        results.append(contentsOf: nsStringResults)

        // 4. 候補エンコーディングを順に試行して補完
        let encs = suggestedEncodings ?? getJapanesePrioritizedEncodings()
        let trialResults = detectByTrial(data, encodings: encs)

        // 既存結果にないものを追加
        for result in trialResults {
            if !results.contains(where: { $0.encoding == result.encoding }) {
                results.append(result)
            }
        }

        // 信頼度でソート
        results.sort { $0.confidence > $1.confidence }

        return results
    }

    /// データからエンコーディングを判定し、デコード結果も返す
    /// - Parameters:
    ///   - data: 判定対象のデータ
    ///   - fileURL: ファイルURL（拡張属性取得用、オプション）
    ///   - suggestedEncodings: 候補となるエンコーディングのリスト
    ///   - allowUserSelection: 信頼度が低い場合にユーザーに選択を求めるかどうか（デフォルト: true）
    /// - Returns: 判定結果
    nonisolated func detectAndDecode(from data: Data, fileURL: URL? = nil, suggestedEncodings: [String.Encoding]? = nil, allowUserSelection: Bool = true, precomputedResults: [EncodingDetectionResult]? = nil) -> EncodingDetectionOutcome {
        let results = precomputedResults ?? detectEncodings(from: data, fileURL: fileURL, suggestedEncodings: suggestedEncodings)

        guard let bestResult = results.first else {
            // フォールバック: ISO Latin-1
            if let string = String(data: data, encoding: .isoLatin1) {
                return .success(encoding: .isoLatin1, string: string)
            }
            return .failure
        }

        // 信頼度が閾値以上の場合、または ユーザー選択を許可しない場合は自動判定
        if bestResult.confidence >= Self.confidenceThreshold || !allowUserSelection {
            if let string = decodeData(data, with: bestResult.encoding) {
                return .success(encoding: bestResult.encoding, string: string)
            }
        }

        // 信頼度が低く、ユーザー選択を許可する場合は候補リストを返す
        return .needsUserSelection(candidates: results)
    }

    // MARK: - BOM Detection

    /// データにBOM（Byte Order Mark）が含まれているかどうかを判定
    /// - Parameter data: 判定対象のデータ
    /// - Returns: BOMが含まれている場合はtrue
    nonisolated func hasBOM(_ data: Data) -> Bool {
        return detectEncodingFromBOM(data) != nil
    }

    /// BOM（Byte Order Mark）からエンコーディングを判定
    private nonisolated func detectEncodingFromBOM(_ data: Data) -> EncodingDetectionResult? {
        guard data.count >= 2 else { return nil }

        let bytes = [UInt8](data.prefix(4))

        // UTF-32 BE BOM: 00 00 FE FF
        if bytes.count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF {
            return EncodingDetectionResult(encoding: .utf32BigEndian, name: "UTF-32BE (BOM)", confidence: 100)
        }

        // UTF-32 LE BOM: FF FE 00 00
        if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00 {
            return EncodingDetectionResult(encoding: .utf32LittleEndian, name: "UTF-32LE (BOM)", confidence: 100)
        }

        // UTF-8 BOM: EF BB BF
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return EncodingDetectionResult(encoding: .utf8, name: "UTF-8 (BOM)", confidence: 100)
        }

        // UTF-16 BE BOM: FE FF
        if bytes[0] == 0xFE && bytes[1] == 0xFF {
            return EncodingDetectionResult(encoding: .utf16BigEndian, name: "UTF-16BE (BOM)", confidence: 100)
        }

        // UTF-16 LE BOM: FF FE
        if bytes[0] == 0xFF && bytes[1] == 0xFE {
            return EncodingDetectionResult(encoding: .utf16LittleEndian, name: "UTF-16LE (BOM)", confidence: 100)
        }

        return nil
    }

    // MARK: - Extended Attribute Detection

    /// 拡張属性（com.apple.TextEncoding）からエンコーディングを判定
    /// - Parameters:
    ///   - url: ファイルURL
    ///   - data: データ（デコード確認用）
    /// - Returns: 検出結果（デコード成功時のみ）
    private nonisolated func detectEncodingFromExtendedAttribute(_ url: URL, data: Data) -> EncodingDetectionResult? {
        // 拡張属性を読み取る
        guard let encoding = readTextEncodingFromExtendedAttribute(url) else {
            return nil
        }

        // 実際にデコードできるか確認
        guard String(data: data, encoding: encoding) != nil else {
            return nil
        }

        return EncodingDetectionResult(
            encoding: encoding,
            name: "\(String.localizedName(of: encoding)) (xattr)",
            confidence: 98  // 拡張属性による判定は非常に高い信頼度
        )
    }

    /// 拡張属性からテキストエンコーディングを読み取る
    /// - Parameter url: ファイルURL
    /// - Returns: エンコーディング（取得できない場合はnil）
    nonisolated func readTextEncodingFromExtendedAttribute(_ url: URL) -> String.Encoding? {
        let path = url.path
        let name = Self.textEncodingXattrKey

        // 拡張属性のサイズを取得
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else {
            return nil
        }

        // 拡張属性の値を読み取る
        var buffer = [UInt8](repeating: 0, count: size)
        let readSize = getxattr(path, name, &buffer, size, 0, 0)
        guard readSize > 0 else {
            return nil
        }

        // 拡張属性の形式: "ENCODING_NAME;CFSTRING_ENCODING_VALUE"
        // 例: "UTF-8;134217984" または "MACINTOSH;0"
        guard let xattrString = String(bytes: buffer, encoding: .utf8) else {
            return nil
        }

        let components = xattrString.split(separator: ";")

        // CFStringEncoding値が含まれている場合はそれを使用
        if components.count >= 2,
           let cfEncodingValue = UInt32(components[1]) {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(cfEncodingValue))
            if nsEncoding != UInt(kCFStringEncodingInvalidId) {
                return String.Encoding(rawValue: nsEncoding)
            }
        }

        // エンコーディング名から判定
        if let encodingName = components.first {
            return encodingFromIANAName(String(encodingName))
        }

        return nil
    }

    /// ファイルにテキストエンコーディングの拡張属性を書き込む
    /// - Parameters:
    ///   - encoding: エンコーディング
    ///   - url: ファイルURL
    /// - Returns: 成功したかどうか
    @discardableResult
    nonisolated func writeTextEncodingToExtendedAttribute(_ encoding: String.Encoding, to url: URL) -> Bool {
        let path = url.path
        let name = Self.textEncodingXattrKey

        // CFStringEncodingを取得
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding.rawValue)
        let ianaName = CFStringConvertEncodingToIANACharSetName(cfEncoding) as String? ?? "UTF-8"

        // 拡張属性の値を作成: "ENCODING_NAME;CFSTRING_ENCODING_VALUE"
        let value = "\(ianaName);\(cfEncoding)"
        guard let data = value.data(using: .utf8) else {
            return false
        }

        // 拡張属性を書き込む
        let result = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Int32 in
            setxattr(path, name, bytes.baseAddress, data.count, 0, 0)
        }

        return result == 0
    }

    /// IANA文字セット名からエンコーディングを取得
    private nonisolated func encodingFromIANAName(_ name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else {
            return nil
        }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    // MARK: - NSString Detection

    /// NSString.stringEncoding を使用してエンコーディングを検出
    private nonisolated func detectWithNSString(_ data: Data, suggestedEncodings: [String.Encoding]?) -> [EncodingDetectionResult] {
        var results: [EncodingDetectionResult] = []

        // 候補エンコーディングを取得（日本語系を優先）
        let encodings = suggestedEncodings ?? getJapanesePrioritizedEncodings()

        // NSString.StringEncodingDetectionOptionsを設定
        var options: [StringEncodingDetectionOptionsKey: Any] = [:]

        // suggestedEncodingsから候補リストを作成
        let encodingNumbers = encodings.map { NSNumber(value: $0.rawValue) }

        // 日本語系エンコーディングを追加で指定
        let japaneseEncodings: [String.Encoding] = [
            .japaneseEUC,
            .shiftJIS,
            String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)))
        ]
        let japaneseEncodingNumbers = japaneseEncodings.map { NSNumber(value: $0.rawValue) }
        options[.suggestedEncodingsKey] = encodingNumbers + japaneseEncodingNumbers

        // ロスのある変換を許可
        options[.allowLossyKey] = true

        // 候補のみを使用しない（他のエンコーディングも検出可能にする）
        options[.useOnlySuggestedEncodingsKey] = false

        var usedLossyConversion: ObjCBool = false
        var convertedString: NSString?

        let detectedEncoding = NSString.stringEncoding(
            for: data,
            encodingOptions: options,
            convertedString: &convertedString,
            usedLossyConversion: &usedLossyConversion
        )

        if detectedEncoding != 0 {
            let encoding = String.Encoding(rawValue: detectedEncoding)
            // ロスのない変換は高い信頼度、ロスのある変換は低い信頼度
            let confidence: Int32 = usedLossyConversion.boolValue ? 40 : 80
            results.append(EncodingDetectionResult(
                encoding: encoding,
                confidence: confidence,
                usedLossyConversion: usedLossyConversion.boolValue
            ))
        }

        return results
    }

    // MARK: - Trial Detection

    /// 候補エンコーディングを順に試行して検出
    private nonisolated func detectByTrial(_ data: Data, encodings: [String.Encoding]) -> [EncodingDetectionResult] {
        var results: [EncodingDetectionResult] = []

        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                let confidence = calculateConfidence(string: string, data: data, encoding: encoding)
                if confidence > 0 {
                    results.append(EncodingDetectionResult(
                        encoding: encoding,
                        confidence: confidence
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Helper Methods

    /// 日本語系エンコーディングを優先したリストを取得
    private nonisolated func getJapanesePrioritizedEncodings() -> [String.Encoding] {
        var encodings: [String.Encoding] = []

        // UTF-8を最優先
        encodings.append(.utf8)

        // 日本語エンコーディング
        encodings.append(.japaneseEUC)
        encodings.append(.shiftJIS)

        // ISO-2022-JP
        let iso2022jp = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.ISO_2022_JP.rawValue)))
        encodings.append(iso2022jp)

        // UTF-16
        encodings.append(.utf16)
        encodings.append(.utf16BigEndian)
        encodings.append(.utf16LittleEndian)

        // その他一般的なエンコーディング
        encodings.append(.ascii)
        encodings.append(.isoLatin1)
        encodings.append(.windowsCP1252)

        // UserDefaultsから有効化されているエンコーディングを追加（スレッドセーフ）
        if let savedEncodings = UserDefaults.standard.array(forKey: "Encodings") as? [UInt] {
            for rawValue in savedEncodings {
                let enc = String.Encoding(rawValue: rawValue)
                if !encodings.contains(enc) {
                    encodings.append(enc)
                }
            }
        }

        return encodings
    }

    /// デコード結果の信頼度を計算
    /// - Parameters:
    ///   - string: デコードされた文字列
    ///   - data: 元のデータ
    ///   - encoding: 使用したエンコーディング
    /// - Returns: 信頼度 (0-100)
    nonisolated func calculateConfidence(string: String, data: Data, encoding: String.Encoding) -> Int32 {
        guard !string.isEmpty else {
            return 100 // 空文字列は常に有効
        }

        var score: Int32 = 50 // 基本スコア

        // 1回のループで置換文字と制御文字の両方をカウント（string.filterによる配列生成を回避）
        var replacementCount = 0
        var invalidControlCount = 0
        var totalLength = 0
        for scalar in string.unicodeScalars {
            totalLength += 1
            if scalar == "\u{FFFD}" {
                replacementCount += 1
            } else if scalar.value < 32 && scalar != "\n" && scalar != "\r" && scalar != "\t" && scalar != "\u{0C}" {
                invalidControlCount += 1
            }
        }

        if replacementCount > 0 {
            let ratio = Double(replacementCount) / Double(totalLength)
            if ratio > 0.1 {
                return 0 // 10%以上の置換文字は不正
            }
            score -= Int32(ratio * 100)
        }

        if invalidControlCount > 0 {
            let ratio = Double(invalidControlCount) / Double(totalLength)
            if ratio > 0.05 {
                return 0 // 5%以上の無効な制御文字は不正
            }
            score -= Int32(ratio * 100)
        }

        // 再エンコードテスト
        // UTF-8の場合はBOMを除いたデータサイズとUTF-8バイト数の比較で簡略化
        if encoding == .utf8 {
            let utf8Count = string.utf8.count
            let dataSize = data.count - (hasBOM(data) ? 3 : 0)
            if utf8Count == dataSize {
                score += 30
            }
        } else if let reencoded = string.data(using: encoding) {
            if reencoded == data {
                score += 30 // 完全一致でボーナス
            } else if reencoded.count == data.count {
                score += 10 // サイズ一致でボーナス
            }
        }

        // UTF-8は追加ボーナス（最も一般的）
        if encoding == .utf8 {
            score += 10
        }

        return min(100, max(0, score))
    }

    /// BOMを除去してデータをデコード
    nonisolated func decodeData(_ data: Data, with encoding: String.Encoding) -> String? {
        var dataToUse = data

        // BOMを除去
        let bytes = [UInt8](data.prefix(4))

        switch encoding {
        case .utf32BigEndian:
            if bytes.count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF {
                dataToUse = data.dropFirst(4)
            }
        case .utf32LittleEndian:
            if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00 {
                dataToUse = data.dropFirst(4)
            }
        case .utf8:
            if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
                dataToUse = data.dropFirst(3)
            }
        case .utf16BigEndian:
            if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
                dataToUse = data.dropFirst(2)
            }
        case .utf16LittleEndian:
            if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
                dataToUse = data.dropFirst(2)
            }
        case .utf16:
            // UTF-16はBE/LEどちらかのBOMがある場合がある
            if bytes.count >= 2 {
                if bytes[0] == 0xFE && bytes[1] == 0xFF {
                    dataToUse = data.dropFirst(2)
                } else if bytes[0] == 0xFF && bytes[1] == 0xFE {
                    dataToUse = data.dropFirst(2)
                }
            }
        default:
            break
        }

        return String(data: Data(dataToUse), encoding: encoding)
    }
}

