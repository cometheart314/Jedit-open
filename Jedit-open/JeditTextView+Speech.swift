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
import CoreText
import NaturalLanguage

/// 発話用 utterance 文字列の 1 セグメント。
/// utterance 文字列のある範囲が、textStorage のどの範囲に対応するかを保持し、
/// 発話進行時の単語ハイライトに使う。
/// - ルビ範囲は `isOpaque = true`: 読み (ふりがな) のどこを発話していても、
///   親文字 (base) の範囲全体を一塊でハイライトする。
/// - 通常範囲は `isOpaque = false`: speechRange と docRange は同じ長さの 1:1 対応。
///
/// Google TTS 経路 (GoogleTTSService) からも参照するため internal にしてある。
struct SpeechSegment {
    let speechRange: NSRange
    let docRange: NSRange
    let isOpaque: Bool
}

extension Notification.Name {
    /// 読み上げの開始/停止のタイミングで送信される。
    /// object には対象の JeditTextView が入る。
    /// ツールバーの読み上げトグルアイテムが状態を更新するために購読する。
    static let jeditSpeechStateDidChange = Notification.Name("jeditSpeechStateDidChange")
}

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

    /// 自前 synthesizer で読み上げセッションを所有しているか。
    /// メニュー検証 (validateMenuItem) とツールバー Speak アイテムの状態判定から参照される。
    /// `synth.isSpeaking` は speak() 呼出し直後ではまだ false のため、セッション所有を
    /// 表す `speechDelegate` の存在で判定する。Pro 提供の別エンジン (Google TTS 等) が
    /// 発話中の場合は SpeechEngineProvider.isSpeaking を参照して合算する。
    var isSpeechActive: Bool {
        if speechDelegate != nil { return true }
        if FeatureProviderRegistry.shared.speechEngineProvider?.isSpeaking == true {
            return true
        }
        return false
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

        // 発話用文字列を組み立てる際、ルビが付いた範囲は親文字ではなく
        // ルビ読みを発話する。基となる base 文字列は preferredVoice の
        // 言語推定にも使うので先に確保しておく。
        let attrSubstring = storage.attributedSubstring(from: safeRange)
        let baseString = attrSubstring.string
        guard !baseString.isEmpty else { return }

        // 既存の発話があれば破棄。
        stopAndCleanupSpeech()

        // Pro 版で代替エンジン (Google Cloud TTS 等) が登録されていれば、
        // そちらに引き継いでもらう。Provider が false を返したら Apple 経路を続行。
        // 全範囲を 1 本の (speechText, segments) にまとめてから渡す。
        // ルビ置換は Open 側で適用されるので Provider は受け取った speechText を
        // そのまま合成に流せばよい。
        if let provider = FeatureProviderRegistry.shared.speechEngineProvider {
            let nsBase = baseString as NSString
            let fullRange = NSRange(location: 0, length: nsBase.length)
            let built = Self.buildSpeechSegments(from: attrSubstring,
                                                  paragraphRange: fullRange,
                                                  docBase: safeRange.location)
            if !built.speechText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               provider.startSpeaking(on: self,
                                      speechText: built.speechText,
                                      segments: built.segments,
                                      safeRange: safeRange,
                                      hadSelection: selRange.length > 0) {
                NotificationCenter.default.post(name: .jeditSpeechStateDidChange, object: self)
                return
            }
        }

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
        // 言語推定の base text には親文字側を渡す (ルビ読みは通常かな・ひらがな
        // で、本文全体の言語推定にバイアスをかけないため)。
        let voice = preferredVoice(for: baseString)
        let nsBase = baseString as NSString
        let fullRange = NSRange(location: 0, length: nsBase.length)
        var utterances: [(AVSpeechUtterance, [SpeechSegment])] = []

        nsBase.enumerateSubstrings(in: fullRange, options: .byParagraphs) {
            substring, paraRange, _, _ in
            guard let substring = substring,
                  !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            let built = Self.buildSpeechSegments(
                from: attrSubstring,
                paragraphRange: paraRange,
                docBase: safeRange.location)
            guard !built.speechText.isEmpty else { return }
            let u = AVSpeechUtterance(string: built.speechText)
            if let voice = voice { u.voice = voice }
            u.postUtteranceDelay = Self.paragraphPauseSeconds
            utterances.append((u, built.segments))
        }

        if utterances.isEmpty {
            // 段落区切りが見つからない/全部空白なら単一 utterance にフォールバック。
            let built = Self.buildSpeechSegments(
                from: attrSubstring,
                paragraphRange: fullRange,
                docBase: safeRange.location)
            if !built.speechText.isEmpty {
                let u = AVSpeechUtterance(string: built.speechText)
                if let voice = voice { u.voice = voice }
                utterances.append((u, built.segments))
            }
        } else {
            // 最後の段落の後にポーズは不要。
            utterances[utterances.count - 1].0.postUtteranceDelay = 0
        }

        guard !utterances.isEmpty else {
            // base text が空白のみ等で発話する内容が無い場合は中断。
            stopAndCleanupSpeech()
            return
        }

        for (u, segments) in utterances {
            delegate.utteranceSegments[ObjectIdentifier(u)] = segments
            synthesizer.speak(u)
        }

        NotificationCenter.default.post(name: .jeditSpeechStateDidChange, object: self)
    }

    /// 指定された段落範囲について、発話用文字列とハイライト用セグメント表を
    /// 組み立てる。ルビ (CTRubyAnnotation) が付いている範囲は親文字ではなく
    /// ルビ読みを発話するため、speech 文字数と doc 文字数が一致しないことが
    /// ある。それを後段 (willSpeakRange ハンドラ) で扱えるよう、対応関係を
    /// セグメント単位で保持する。
    static func buildSpeechSegments(
        from attrStr: NSAttributedString,
        paragraphRange: NSRange,
        docBase: Int
    ) -> (speechText: String, segments: [SpeechSegment]) {
        var speechText = ""
        var segments: [SpeechSegment] = []
        let rubyKey = NSAttributedString.Key(kCTRubyAnnotationAttributeName as String)
        let nsBase = attrStr.string as NSString

        attrStr.enumerateAttribute(rubyKey, in: paragraphRange, options: []) {
            value, range, _ in
            let docRange = NSRange(location: docBase + range.location, length: range.length)
            let speechStart = (speechText as NSString).length

            // CTRubyAnnotation が付いていればルビ読みで置換
            if let cf = value as CFTypeRef?,
               CFGetTypeID(cf) == CTRubyAnnotationGetTypeID() {
                let ruby = cf as! CTRubyAnnotation
                if let cfRubyText = CTRubyAnnotationGetTextForPosition(ruby, .before) {
                    let rubyText = cfRubyText as String
                    if !rubyText.isEmpty {
                        speechText += rubyText
                        let speechEnd = (speechText as NSString).length
                        segments.append(SpeechSegment(
                            speechRange: NSRange(location: speechStart,
                                                 length: speechEnd - speechStart),
                            docRange: docRange,
                            isOpaque: true))
                        return
                    }
                }
                // ルビ読みが取れない/空の場合は base text にフォールバック。
            }

            // 非ルビ範囲: base text を 1:1 で speechText に積む。
            let baseSubstr = nsBase.substring(with: range)
            speechText += baseSubstr
            let speechEnd = (speechText as NSString).length
            segments.append(SpeechSegment(
                speechRange: NSRange(location: speechStart,
                                     length: speechEnd - speechStart),
                docRange: docRange,
                isOpaque: false))
        }

        return (speechText, segments)
    }

    /// 段落区切りで挟む無音時間 (秒)。
    private static let paragraphPauseSeconds: TimeInterval = 0.35

    /// 「読み上げを停止」アクション。
    override func stopSpeaking(_ sender: Any?) {
        stopAndCleanupSpeech()
    }

    /// 書類ウィンドウが閉じられる等で textView が window から外されるときに、
    /// 残っている発話セッションを必ず止める。これがないと Apple 経路では
    /// AVSpeechSynthesizer がプロセスに残って読み上げが続いてしまうし、
    /// Google TTS 経路ではバックグラウンドの AVAudioPlayer が再生し続ける。
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, self.window != nil, isSpeechActive {
            stopAndCleanupSpeech()
        }
    }

    // MARK: - Internal Helpers

    /// 発話を停止し、ハイライトと保持オブジェクトをすべて破棄する。
    /// stopSpeaking → didCancel → 本メソッド の再入を防ぐため synthesizer nil で早期 return。
    /// Pro 提供エンジンが動作中なら、そちらにも停止を伝える。
    fileprivate func stopAndCleanupSpeech() {
        let provider = FeatureProviderRegistry.shared.speechEngineProvider
        let providerActive = provider?.isSpeaking == true
        guard speechSynthesizer != nil || providerActive else { return }

        if providerActive {
            provider?.stopSpeaking(silently: true)
        }
        if let synth = speechSynthesizer, synth.isSpeaking || synth.isPaused {
            synth.stopSpeaking(at: .immediate)
        }
        clearSpeechHighlight()
        restoreSelectionIfUntouched()
        speechSynthesizer?.delegate = nil
        speechSynthesizer = nil
        speechDelegate = nil
        speechBaseLocation = 0
        NotificationCenter.default.post(name: .jeditSpeechStateDidChange, object: self)
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

    // MARK: - External Speech Engine (Pro) Hooks

    /// Pro 提供の代替読み上げエンジン (Google TTS 等) がセッション開始時に呼ぶ。
    /// 選択範囲をキャレット位置に畳んで保存し、ハイライト解除・終了通知を行えるよう
    /// 状態を整える。
    func beginExternalSpeechSession(safeRange: NSRange, hadSelection: Bool) {
        speechBaseLocation = safeRange.location
        speechHighlightedRange = nil
        if hadSelection {
            speechSavedSelectedRanges = selectedRanges
            setSelectedRange(NSRange(location: safeRange.location, length: 0))
        } else {
            speechSavedSelectedRanges = nil
        }
    }

    /// Pro 提供エンジンの再生中、現在発話している textStorage 範囲を反映するために呼ぶ。
    func updateExternalSpeechHighlight(docRange: NSRange) {
        applySpeechHighlight(docRange: docRange)
    }

    /// Pro 提供エンジンが正常終了・キャンセル・エラーで停止したときに呼ぶ。
    /// ハイライト解除と選択範囲復元を行い、状態変更通知を出す。
    func endExternalSpeechSession() {
        clearSpeechHighlight()
        restoreSelectionIfUntouched()
        speechBaseLocation = 0
        NotificationCenter.default.post(name: .jeditSpeechStateDidChange, object: self)
    }

    /// 発話に使う声を決める。
    /// 本文の優勢言語を判定し、システム設定 (アクセシビリティ > 読み上げ >
    /// システムの声) の声がその言語を読めるなら、そのシステムの声を優先する。
    /// 言語が合わない場合 (例: 日本語のシステム音声で英文を読む場合) は、
    /// 本文言語で利用可能な「最も品質の高い」声に切り替える。これにより、
    /// 英文を日本語ボイスでカタカナ読みしてしまう問題を避ける。
    private func preferredVoice(for text: String) -> AVSpeechSynthesisVoice? {
        let dominant = dominantLanguageCode(for: text)

        if let systemVoice = systemDefaultVoice() {
            // 言語判定できない場合はシステムの声をそのまま使う。
            guard let dominant = dominant else { return systemVoice }
            // システムの声が本文の言語を読めるなら、それを優先。
            if systemVoice.language.hasPrefix(dominant) {
                return systemVoice
            }
            // 言語が合わない場合は本文言語の最高品質ボイス。無ければシステムの声に戻す。
            return bestQualityVoice(forLanguage: dominant) ?? systemVoice
        }

        // システムの声が解決できない場合は従来どおり本文言語の最高品質ボイス。
        guard let dominant = dominant else { return nil }
        return bestQualityVoice(forLanguage: dominant)
    }

    /// システム設定 (アクセシビリティ > 読み上げ > システムの声) で選ばれている
    /// デフォルト音声を AVSpeechSynthesisVoice として解決する。
    /// AVFoundation にはシステム選択音声を直接返す API がないため、AppKit の
    /// NSSpeechSynthesizer.defaultVoice を取得し、対応する声を探す。
    /// 注: Spoken Content で Siri 系の声を選んでいる場合、サードパーティアプリからは
    /// 合成に使えないため解決に失敗 (nil) し、bestQualityVoice にフォールバックする。
    private func systemDefaultVoice() -> AVSpeechSynthesisVoice? {
        let defaultName = NSSpeechSynthesizer.defaultVoice.rawValue

        // 近年の macOS では NSSpeechSynthesizer と AVSpeechSynthesisVoice の識別子が
        // 揃っている (例: com.apple.voice.compact.ja-JP.Kyoko) ため、まず識別子で直接照合。
        if let v = AVSpeechSynthesisVoice(identifier: defaultName) {
            return v
        }

        // 識別子が一致しない古い声などのため、名前 + ロケールで照合するフォールバック。
        let attrs = NSSpeechSynthesizer.attributes(forVoice: NSSpeechSynthesizer.defaultVoice)
        guard let name = attrs[.name] as? String else { return nil }
        let locale = (attrs[.localeIdentifier] as? String)?.replacingOccurrences(of: "_", with: "-")
        let byName = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
        if let locale = locale,
           let v = byName.first(where: { $0.language == locale }) {
            return v
        }
        return byName.first
    }

    /// テキストの優勢言語コード ("ja", "en" 等) を返す。判定できなければ nil。
    private func dominantLanguageCode(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage?.rawValue
    }

    /// 指定言語で利用可能な「最も品質の高い」声を返す。
    /// AVSpeechSynthesisVoice(language:) は Default 品質の標準音声を返してしまうため、
    /// インストール済みボイスを列挙して Premium > Enhanced > Default の順に選ぶ。
    private func bestQualityVoice(forLanguage lang: String) -> AVSpeechSynthesisVoice? {
        // 例: lang = "ja" のとき、voice.language は "ja-JP"。前方一致で絞る。
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(lang)
        }
        if candidates.isEmpty {
            return AVSpeechSynthesisVoice(language: lang)
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

    /// utterance ごとの「speech 文字範囲 → textStorage 文字範囲」マップ。
    /// 段落分割した発話の進行に合わせて willSpeakRangeOfSpeechString で参照する。
    /// ルビ範囲は SpeechSegment.isOpaque = true で、読みのどこを発話していても
    /// 親文字の docRange 全体をハイライトする。
    var utteranceSegments: [ObjectIdentifier: [SpeechSegment]] = [:]

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
        guard let segments = utteranceSegments[ObjectIdentifier(utterance)] else { return }

        let speechStart = characterRange.location
        // 発話中のセグメントを線形検索 (1 段落あたりせいぜい数十~数百セグメントなので十分)。
        guard let segment = segments.first(where: { seg in
            speechStart >= seg.speechRange.location
                && speechStart < seg.speechRange.location + seg.speechRange.length
        }) else { return }

        let docRange: NSRange
        if segment.isOpaque {
            // ルビ範囲: 読みのどこを発話していても親文字全体をハイライト。
            docRange = segment.docRange
        } else {
            // 1:1 セグメント。speechRange と docRange は同じ長さの想定。
            let offset = speechStart - segment.speechRange.location
            let available = segment.speechRange.length - offset
            let length = min(characterRange.length, max(0, available))
            docRange = NSRange(location: segment.docRange.location + offset, length: length)
        }
        onMain { [weak owner] in
            owner?.applySpeechHighlight(docRange: docRange)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        utteranceSegments.removeValue(forKey: ObjectIdentifier(utterance))
        // 段落分割しているので didFinish はキューの utterance ごとに発火する。
        // 全部終わったら最終クリーンアップ。
        guard utteranceSegments.isEmpty else { return }
        onMain { [weak owner] in
            owner?.stopAndCleanupSpeech()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        // stopSpeaking はキュー全体を一括キャンセルする。キューがあった場合のみ最終クリーンアップ。
        let hadAny = !utteranceSegments.isEmpty
        utteranceSegments.removeAll()
        guard hadAny else { return }
        onMain { [weak owner] in
            owner?.stopAndCleanupSpeech()
        }
    }
}
