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

    /// ペースト完了後に全範囲分離を実行する予約範囲
    private var pendingFullRange: NSRange?

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

    // MARK: - Paste Support

    /// ペースト中の編集範囲を記録する
    func recordPastedRange(_ range: NSRange) {
        if let existing = pendingFullRange {
            pendingFullRange = NSUnionRange(existing, range)
        } else {
            pendingFullRange = range
        }
    }

    /// ペースト/ドロップ完了後に記録された範囲の分離を即座に実行する。
    /// タイマーを使わず同期的に実行することで、ペースト/ドロップ操作と同じUndoグループに含める。
    func processPendingFullSeparation() {
        guard let range = pendingFullRange else { return }
        pendingFullRange = nil

        // 既存のタイマーがあればキャンセル
        timer?.invalidate()
        timer = nil

        // requestedRange を設定して直接実行
        if let existing = requestedRange {
            requestedRange = NSUnionRange(existing, range)
        } else {
            requestedRange = range
        }
        performSeparation()
    }

    // MARK: - Perform Separation

    /// 実際の分離処理を実行する
    /// 編集範囲の前後の境界に加え、範囲内部のすべての英日・日英境界もチェックする。
    /// これにより、ペーストやドロップで挿入された複数文字のテキスト内部にもスペースが挿入される。
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

        let nsText = textStorage.string as NSString
        let textLength = nsText.length

        guard textLength > 0, targetRange.location < textLength else { return }

        // スキャン範囲を決定（編集範囲の1文字前から編集範囲の末尾まで）
        let scanStart = targetRange.location > 0 ? targetRange.location - 1 : 0
        let scanEnd = min(NSMaxRange(targetRange), textLength - 1)

        guard scanStart < scanEnd else { return }

        // スペース挿入が必要な位置を収集
        var insertPositions: [Int] = []

        for i in scanStart..<scanEnd {
            let charA = nsText.character(at: i)
            let charB = nsText.character(at: i + 1)
            guard let scalarA = Unicode.Scalar(charA),
                  let scalarB = Unicode.Scalar(charB) else { continue }

            // スキップ対象文字（空白、改行、句読点）は無視
            if Self.skipSet.contains(scalarA) || Self.skipSet.contains(scalarB) {
                continue
            }

            if needsSeparation(prev: scalarA, new: scalarB) {
                insertPositions.append(i + 1)
            }
        }

        guard !insertPositions.isEmpty else { return }

        // Undo グルーピング開始
        if textView.allowsUndo {
            textView.undoManager?.beginUndoGrouping()
        }

        // 後方から挿入（位置ずれ防止）
        for position in insertPositions.reversed() {
            if textView.shouldChangeText(in: NSRange(location: position, length: 0), replacementString: " ") {
                textStorage.replaceCharacters(in: NSRange(location: position, length: 0), with: " ")
                textView.didChangeText()
            }
        }

        if textView.allowsUndo {
            textView.undoManager?.endUndoGrouping()
        }

        // カーソル位置を補正
        // 編集範囲の末尾より前に挿入されたスペースの数だけカーソルを後方に移動
        let endPos = NSMaxRange(targetRange)
        let spacesBeforeEnd = insertPositions.filter { $0 < endPos }.count
        textView.setSelectedRange(NSRange(location: endPos + spacesBeforeEnd, length: 0))
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
