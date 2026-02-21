//
//  SmartLanguageSeparation.swift
//  Jedit-open
//
//  英語と日本語の境界にスペースを自動挿入する機能。
//  JeditΩ の doSeparateJapaneseAndEnglish をSwiftで再実装。
//

import Cocoa

// MARK: - Smart Language Separation

/// 英語と日本語の境界にスペースを自動挿入する処理を管理する。
/// FontFallbackRecoveryDelegate から呼び出され、タイマーで遅延実行する。
class SmartLanguageSeparation {

    // MARK: - Character Sets

    /// 英語（Latin）文字セット
    /// lowercaseLetterCharacterSet + uppercaseLetterCharacterSet から全角英字を除外
    static let englishSet: CharacterSet = {
        var set = CharacterSet.lowercaseLetters.union(.uppercaseLetters)
        // 全角大文字 Ａ-Ｚ (U+FF21..U+FF3A)
        set.remove(charactersIn: Unicode.Scalar(0xFF21)!...Unicode.Scalar(0xFF3A)!)
        // 全角小文字 ａ-ｚ (U+FF41..U+FF5A)
        set.remove(charactersIn: Unicode.Scalar(0xFF41)!...Unicode.Scalar(0xFF5A)!)
        return set
    }()

    /// 日本語文字セット
    /// ひらがな (U+3041..U+30FF) + CJK統合漢字拡張A〜CJK統合漢字 (U+3400..U+9FFF)
    static let japaneseSet: CharacterSet = {
        var set = CharacterSet()
        // ひらがな + カタカナ
        set.insert(charactersIn: Unicode.Scalar(0x3041)!...Unicode.Scalar(0x30FF)!)
        // CJK統合漢字拡張A + CJK統合漢字
        set.insert(charactersIn: Unicode.Scalar(0x3400)!...Unicode.Scalar(0x9FFF)!)
        return set
    }()

    /// スペース挿入をスキップする文字セット（空白、改行、句読点）
    private static let skipSet: CharacterSet = {
        return CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    }()

    // MARK: - Properties

    /// ドキュメントへの弱参照
    weak var document: Document?

    /// リクエストされた分離処理の対象範囲
    private var requestedRange: NSRange?

    /// 遅延実行用タイマー
    private var timer: Timer?

    /// 分離処理中フラグ（再帰呼び出し防止）
    private var isProcessing = false

    /// ペースト処理中フラグ
    var isPasting = false

    /// タイマー遅延間隔（秒）
    private static let timerInterval: TimeInterval = 0.05

    // MARK: - Initialization

    init(document: Document) {
        self.document = document
    }

    deinit {
        timer?.invalidate()
    }

    // MARK: - Request Separation

    /// 分離処理をリクエストする（タイマーで遅延実行）
    /// textStorage の didProcessEditing から呼ばれる。
    func requestSeparation(for range: NSRange) {
        // 既存のリクエストがあれば範囲を結合
        if let existing = requestedRange {
            requestedRange = NSUnionRange(existing, range)
        } else {
            requestedRange = range
        }

        // タイマーをリセット
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.timerInterval, repeats: false) { [weak self] _ in
            self?.performSeparation()
        }
        // Common モードに追加（モーダルダイアログ表示中にも動作するように）
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    // MARK: - Perform Separation

    /// 実際の分離処理を実行する
    private func performSeparation() {
        timer = nil

        guard let document = document else { return }
        let textStorage = document.textStorage

        // テキストビューを取得
        guard let textView = textStorage.layoutManagers.first?.firstTextView as? JeditTextView else { return }

        // IME入力中は延期
        if textView.hasMarkedText() {
            if requestedRange != nil {
                // 再度タイマーをセットして延期
                timer = Timer.scheduledTimer(withTimeInterval: Self.timerInterval, repeats: false) { [weak self] _ in
                    self?.performSeparation()
                }
                if let timer = timer {
                    RunLoop.main.add(timer, forMode: .common)
                }
            }
            return
        }

        guard let targetRange = requestedRange else { return }
        requestedRange = nil

        // 再帰呼び出し防止
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        let text = textStorage.string
        let nsText = text as NSString
        let textLength = nsText.length

        guard textLength > 0, targetRange.location < textLength else { return }

        var delta = 0
        var changed = false
        var resetSelection = false
        var nextIndex = NSMaxRange(targetRange)

        // --- 編集範囲の前方の境界をチェック ---
        // targetRange.location の直前の文字と targetRange.location の文字の境界
        if targetRange.location > 0 {
            let prevChar = nsText.character(at: targetRange.location - 1)
            let prevScalar = Unicode.Scalar(prevChar)!

            // 直前の文字がスキップ対象でなければチェック
            if !Self.skipSet.contains(prevScalar) {
                let newChar = nsText.character(at: targetRange.location)
                let newScalar = Unicode.Scalar(newChar)!

                if needsSeparation(prev: prevScalar, new: newScalar) {
                    // スペースを挿入
                    if textView.allowsUndo {
                        textView.undoManager?.beginUndoGrouping()
                    }
                    if textView.shouldChangeText(in: NSRange(location: targetRange.location, length: 0), replacementString: " ") {
                        textStorage.replaceCharacters(in: NSRange(location: targetRange.location, length: 0), with: " ")
                        textView.didChangeText()
                        delta += 1
                    }
                    changed = true
                }
            }
        }

        // --- 編集範囲の後方の境界をチェック ---
        // targetRange の末尾の文字と次の文字の境界
        let afterIndex = NSMaxRange(targetRange) + delta
        if afterIndex < textStorage.string.count {
            // textStorage の内容が変わっている可能性があるので再取得
            let currentText = textStorage.string as NSString
            let currentLength = currentText.length

            if afterIndex < currentLength {
                let newChar = currentText.character(at: afterIndex)
                let newScalar = Unicode.Scalar(newChar)!

                if !Self.skipSet.contains(newScalar) && afterIndex > 0 {
                    let prevChar = currentText.character(at: afterIndex - 1)
                    let prevScalar = Unicode.Scalar(prevChar)!

                    if needsSeparation(prev: prevScalar, new: newScalar) {
                        if !changed && textView.allowsUndo {
                            textView.undoManager?.beginUndoGrouping()
                        }
                        if textView.shouldChangeText(in: NSRange(location: afterIndex, length: 0), replacementString: " ") {
                            textStorage.replaceCharacters(in: NSRange(location: afterIndex, length: 0), with: " ")
                            textView.didChangeText()
                            resetSelection = true
                        }
                        changed = true
                    }
                }
            }
        }

        if changed {
            if textView.allowsUndo {
                textView.undoManager?.endUndoGrouping()
            }
            if resetSelection {
                // カーソル位置を補正
                nextIndex = NSMaxRange(targetRange) + delta
                textView.setSelectedRange(NSRange(location: nextIndex, length: 0))
            }
        }
    }

    // MARK: - Private Helpers

    /// 2つの文字の間にスペースが必要かどうかを判定する
    /// 英語→日本語、または日本語→英語の境界であればtrue
    private func needsSeparation(prev: Unicode.Scalar, new: Unicode.Scalar) -> Bool {
        let prevIsEnglish = Self.englishSet.contains(prev)
        let prevIsJapanese = Self.japaneseSet.contains(prev)
        let newIsEnglish = Self.englishSet.contains(new)
        let newIsJapanese = Self.japaneseSet.contains(new)

        return (prevIsEnglish && newIsJapanese) || (prevIsJapanese && newIsEnglish)
    }
}
