//
//  JeditTextView+Speech.swift
//  Jedit-open
//
//  読み上げ (Edit > Speech > Start Speaking) を AVSpeechSynthesizer で実装し、
//  読み上げ中の単語をレイアウトマネージャの一時属性で背景ハイライトする。
//
//  NSTextView 既定の startSpeaking: は NSSpeechSynthesizer を使うため、
//  単語位置のコールバックが取りにくくハイライトに使えない。本拡張で
//  startSpeaking(_:) / stopSpeaking(_:) を上書きして AVSpeechSynthesizer に置き換える。
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

import Cocoa
import AVFoundation
import NaturalLanguage

extension JeditTextView {

    // MARK: - Associated Object Keys

    private static var synthesizerKey: UInt8 = 0
    private static var delegateKey: UInt8 = 0
    private static var baseLocationKey: UInt8 = 0
    private static var highlightedRangeKey: UInt8 = 0
    private static var savedSelectedRangesKey: UInt8 = 0

    /// 現在動作中の AVSpeechSynthesizer (発話中のみ非 nil)。
    private var speechSynthesizer: AVSpeechSynthesizer? {
        get { return objc_getAssociatedObject(self, &Self.synthesizerKey) as? AVSpeechSynthesizer }
        set { objc_setAssociatedObject(self, &Self.synthesizerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// synthesizer のデリゲート (NSObject 必須なので別クラスで保持)。
    private var speechDelegate: SpeechHighlightDelegate? {
        get { return objc_getAssociatedObject(self, &Self.delegateKey) as? SpeechHighlightDelegate }
        set { objc_setAssociatedObject(self, &Self.delegateKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 発話対象テキストの textStorage 上の開始位置 (UTF-16)。
    /// utterance 内 NSRange + baseLocation = textStorage 上の NSRange。
    private var speechBaseLocation: Int {
        get { return (objc_getAssociatedObject(self, &Self.baseLocationKey) as? Int) ?? 0 }
        set { objc_setAssociatedObject(self, &Self.baseLocationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// 自前 synthesizer で現在発話中（または一時停止中）か。
    /// メニュー検証 (validateMenuItem) から参照される。
    var isSpeechActive: Bool {
        guard let synth = speechSynthesizer else { return false }
        return synth.isSpeaking || synth.isPaused
    }

    /// 現在ハイライト中の textStorage 上の単語範囲 (なければ nil)。
    fileprivate var speechHighlightedRange: NSRange? {
        get { return (objc_getAssociatedObject(self, &Self.highlightedRangeKey) as? NSValue)?.rangeValue }
        set {
            if let r = newValue {
                objc_setAssociatedObject(self, &Self.highlightedRangeKey, NSValue(range: r), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            } else {
                objc_setAssociatedObject(self, &Self.highlightedRangeKey, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
    }

    /// 読み上げ開始時に保存した selectedRanges (発話中はキャレットに畳むため)。
    /// 終了時に同じ位置にキャレットがあれば復元する。
    private var speechSavedSelectedRanges: [NSValue]? {
        get { return objc_getAssociatedObject(self, &Self.savedSelectedRangesKey) as? [NSValue] }
        set { objc_setAssociatedObject(self, &Self.savedSelectedRangesKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    // MARK: - Action Overrides

    /// 「読み上げを開始」アクション。
    /// 選択範囲があればその範囲、なければ書類全体を AVSpeechSynthesizer で発話し、
    /// willSpeakRange コールバックで現在単語をハイライトする。
    override func startSpeaking(_ sender: Any?) {
        guard let storage = self.textStorage, storage.length > 0 else {
            return
        }

        let selRange = self.selectedRange()
        let speakRange: NSRange
        if selRange.length > 0 {
            speakRange = selRange
        } else {
            // 選択なし: カーソル位置から書類末尾までを読む。
            let start = max(0, min(selRange.location, storage.length))
            speakRange = NSRange(location: start, length: storage.length - start)
        }

        // 念のため範囲を有効範囲にクランプ。
        let safeRange = NSIntersectionRange(speakRange, NSRange(location: 0, length: storage.length))
        guard safeRange.length > 0 else { return }

        let utteranceString = storage.attributedSubstring(from: safeRange).string
        guard !utteranceString.isEmpty else { return }

        // 既存の発話があれば破棄。
        stopAndCleanupSpeech()

        let synthesizer = AVSpeechSynthesizer()
        let delegate = SpeechHighlightDelegate(owner: self)
        synthesizer.delegate = delegate

        self.speechSynthesizer = synthesizer
        self.speechDelegate = delegate
        self.speechBaseLocation = safeRange.location
        self.speechHighlightedRange = nil

        // 選択ハイライトが単語ハイライトを覆うため、発話中は選択を畳む。
        // 発話前 selectedRanges を保存し、cleanup で「現在の選択が畳んだままなら」復元。
        if selRange.length > 0 {
            self.speechSavedSelectedRanges = self.selectedRanges
            self.setSelectedRange(NSRange(location: safeRange.location, length: 0))
        } else {
            self.speechSavedSelectedRanges = nil
        }

        // 段落ごとに utterance を作り、各段落末に短いポーズを入れる。
        // 段落区切りは NSString.enumerateSubstrings の .byParagraphs を採用
        // (\n, \r\n, \r, U+2028, U+2029 を網羅)。
        let voice = preferredVoice(for: utteranceString)
        let nsFull = utteranceString as NSString
        let fullRange = NSRange(location: 0, length: nsFull.length)
        var utterances: [(AVSpeechUtterance, Int)] = []

        nsFull.enumerateSubstrings(in: fullRange, options: .byParagraphs) {
            substring, paraRange, _, _ in
            guard let substring = substring,
                  !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let u = AVSpeechUtterance(string: substring)
            if let voice = voice { u.voice = voice }
            u.postUtteranceDelay = Self.paragraphPauseSeconds
            utterances.append((u, safeRange.location + paraRange.location))
        }

        if utterances.isEmpty {
            // 段落区切りが見つからない/全部空白なら単一 utterance にフォールバック。
            let u = AVSpeechUtterance(string: utteranceString)
            if let voice = voice { u.voice = voice }
            utterances.append((u, safeRange.location))
        } else {
            // 最後の段落の後にポーズは不要。
            utterances[utterances.count - 1].0.postUtteranceDelay = 0
        }

        for (u, base) in utterances {
            delegate.utteranceBases[ObjectIdentifier(u)] = base
            synthesizer.speak(u)
        }
    }

    /// 段落区切りで挟む無音時間 (秒)。
    private static let paragraphPauseSeconds: TimeInterval = 0.35

    /// 「読み上げを停止」アクション。
    override func stopSpeaking(_ sender: Any?) {
        stopAndCleanupSpeech()
    }

    // MARK: - Internal Helpers

    /// 発話を停止し、ハイライトと保持オブジェクトをすべて破棄する。
    /// stopSpeaking → didCancel → 本メソッド の再入を防ぐため synthesizer nil で早期 return。
    fileprivate func stopAndCleanupSpeech() {
        guard speechSynthesizer != nil else { return }
        if let synth = speechSynthesizer, synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
        clearSpeechHighlight()
        restoreSelectionIfUntouched()
        speechSynthesizer?.delegate = nil
        speechSynthesizer = nil
        speechDelegate = nil
        speechBaseLocation = 0
    }

    /// 発話開始時に畳んだ選択範囲を復元する (現在の選択がこちらが畳んだキャレットのままなら)。
    /// ユーザが発話中にクリック等で選択を動かしていた場合は、その意思を尊重して復元しない。
    private func restoreSelectionIfUntouched() {
        defer { speechSavedSelectedRanges = nil }
        guard let saved = speechSavedSelectedRanges,
              let storage = self.textStorage else { return }
        let current = self.selectedRange()
        // 開始時にキャレットを置いた location は speechBaseLocation。
        // length=0 かつ location 一致のときだけ復元する。
        guard current.length == 0, current.location == speechBaseLocation else { return }
        // 保存した範囲が現在の文書長を超えていないことだけ軽くチェック。
        for value in saved {
            let r = value.rangeValue
            if NSMaxRange(r) > storage.length { return }
        }
        self.selectedRanges = saved
    }

    /// 現在のハイライトを除去する。
    fileprivate func clearSpeechHighlight() {
        guard let layoutManager = self.layoutManager,
              let storage = self.textStorage else { return }
        if let r = speechHighlightedRange,
           NSMaxRange(r) <= storage.length {
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: r)
        }
        speechHighlightedRange = nil
    }

    /// textStorage 上の NSRange をハイライトする。
    /// 呼び出し側 (delegate) で utterance ごとの base offset を加算済みの doc 座標 range を渡す。
    fileprivate func applySpeechHighlight(docRange: NSRange) {
        guard let layoutManager = self.layoutManager,
              let storage = self.textStorage else { return }
        guard NSMaxRange(docRange) <= storage.length else { return }

        clearSpeechHighlight()

        let color = NSColor.systemYellow.withAlphaComponent(0.45)
        layoutManager.addTemporaryAttribute(.backgroundColor,
                                            value: color,
                                            forCharacterRange: docRange)
        speechHighlightedRange = docRange

        self.scrollRangeToVisible(docRange)
    }

    /// 発話テキストから優勢言語を判定し、その言語で利用可能な「最も品質の高い」声を返す。
    /// AVSpeechSynthesisVoice(language:) は Default 品質の標準音声を返してしまうため、
    /// インストール済みボイスを列挙して Premium > Enhanced > Default の順に選ぶ。
    /// （TextEdit がシステム設定の声で読むとき高品質なのは Premium / Enhanced の音声を
    /// 使っているため。)
    private func preferredVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage else { return nil }

        // 例: dominantLanguage = "ja" のとき、voice.language は "ja-JP"。前方一致で絞る。
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(lang.rawValue)
        }
        if candidates.isEmpty {
            return AVSpeechSynthesisVoice(language: lang.rawValue)
        }

        // 品質順 (Premium → Enhanced → Default) に最初に見つかったものを採用。
        // Premium は macOS 13+ なので availability で分岐。
        if #available(macOS 13.0, *) {
            if let v = candidates.first(where: { $0.quality == .premium }) { return v }
        }
        if let v = candidates.first(where: { $0.quality == .enhanced }) { return v }
        if let v = candidates.first(where: { $0.quality == .default }) { return v }
        return candidates.first
    }
}

// MARK: - AVSpeechSynthesizerDelegate

/// AVSpeechSynthesizerDelegate を別クラスで保持する。
/// JeditTextView 自身を delegate にしてもよいが、Objective-C 選択子の
/// 衝突や責務分離の観点で独立クラスのほうが扱いやすい。
private final class SpeechHighlightDelegate: NSObject, AVSpeechSynthesizerDelegate {

    weak var owner: JeditTextView?

    /// utterance ごとの textStorage 上の base location。
    /// 段落分割した発話の進行に合わせて willSpeakRangeOfSpeechString で参照する。
    var utteranceBases: [ObjectIdentifier: Int] = [:]

    init(owner: JeditTextView) {
        self.owner = owner
    }

    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           willSpeakRangeOfSpeechString characterRange: NSRange,
                           utterance: AVSpeechUtterance) {
        // 登録外の utterance (ウォームアップ) はハイライト対象外。
        guard let base = utteranceBases[ObjectIdentifier(utterance)] else { return }
        let docRange = NSRange(location: base + characterRange.location,
                               length: characterRange.length)
        onMain { [weak owner] in
            owner?.applySpeechHighlight(docRange: docRange)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        utteranceBases.removeValue(forKey: ObjectIdentifier(utterance))
        // 段落分割しているので didFinish はキューの utterance ごとに発火する。
        // 全部終わったら最終クリーンアップ。
        guard utteranceBases.isEmpty else { return }
        onMain { [weak owner] in
            owner?.stopAndCleanupSpeech()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        // stopSpeaking はキュー全体を一括キャンセルする。キューがあった場合のみ最終クリーンアップ。
        let hadAny = !utteranceBases.isEmpty
        utteranceBases.removeAll()
        guard hadAny else { return }
        onMain { [weak owner] in
            owner?.stopAndCleanupSpeech()
        }
    }
}
