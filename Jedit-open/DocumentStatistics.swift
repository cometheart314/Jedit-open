//
//  DocumentStatistics.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/10.
//

import Foundation

/// ドキュメント統計情報を保持する値型
/// EditorWindowController がバックグラウンドで計算し、Document のプロパティとして保持する
struct DocumentStatistics {

    // MARK: - Whole Document

    var totalCharacters: Int = 0
    var totalVisibleChars: Double = 0
    var totalWords: Int = 0
    var totalParagraphs: Int = 0
    var totalRows: Int = 0          // 表示行数（lineNumberMode 依存）
    var totalPages: Int = 0         // ページモード時のみ

    // MARK: - Selection（最初の selection）

    var selectionLocation: Int = 0       // キャレット位置（文字インデックス）
    var selectionLength: Int = 0         // 選択範囲の長さ

    // 選択位置（selection 開始点までの値）
    var locationVisibleChars: Int = 0    // 選択開始点までの可視文字数
    var locationWords: Int = 0           // 選択開始点までの単語数
    var locationParagraphs: Int = 0      // 選択開始点までの段落数
    var locationRows: Int = 0            // 選択開始点までの行数
    var locationPages: Int = 0           // 選択開始点のページ番号

    // 選択範囲のサイズ
    var selectionCharacters: Int = 0     // 選択範囲の文字数
    var selectionVisibleChars: Double = 0
    var selectionWords: Int = 0
    var selectionParagraphs: Int = 0
    var selectionRows: Int = 0           // 選択範囲の行数
    var selectionPages: Int = 0          // 選択範囲のページ数

    var charCode: String = ""            // キャレット位置の Unicode コードポイント表示

    // MARK: - Display Mode Flags

    var showRows: Bool = false           // 行番号モードが有効か
    var showPages: Bool = false          // ページモードか

    // MARK: - Formatting Helpers

    /// 数値をカンマ区切り文字列に変換
    nonisolated static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter
    }()

    /// 整数をカンマ区切り文字列に変換
    nonisolated static func formatted(_ value: Int) -> String {
        return numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// 小数値をカンマ区切り文字列に変換（0.5刻みに対応）
    nonisolated static func formatted(_ value: Double) -> String {
        if value == value.rounded(.down) {
            // 整数の場合は小数点なし
            return numberFormatter.string(from: NSNumber(value: Int(value))) ?? "\(Int(value))"
        } else {
            // 小数の場合（0.5）は小数点1桁
            let fmt = NumberFormatter()
            fmt.numberStyle = .decimal
            fmt.groupingSeparator = ","
            fmt.minimumFractionDigits = 1
            fmt.maximumFractionDigits = 1
            return fmt.string(from: NSNumber(value: value)) ?? "\(value)"
        }
    }
}
