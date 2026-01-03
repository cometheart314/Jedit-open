//
//  LineNumberRulerView.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
//

import Cocoa

// MARK: - Line Number Mode

enum LineNumberMode {
    case none        // 行番号非表示
    case paragraph   // パラグラフ番号
    case row         // 行番号（折り返しを含む）
}

// MARK: - Line Number Ruler View

class LineNumberRulerView: NSRulerView {
    var lineNumberMode: LineNumberMode = .none {
        didSet {
            updateRuleThicknessAsync()
            needsDisplay = true
        }
    }

    weak var textView: NSTextView?
    private let minimumThickness: CGFloat = 40.0
    private let rightMargin: CGFloat = 5.0
    private let leftMargin: CGFloat = 5.0
    private var updateWorkItem: DispatchWorkItem?

    init(scrollView: NSScrollView, textView: NSTextView?) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = minimumThickness

        // macOSのNSRulerViewのバグ回避: clipsToBoundsを設定
        self.clipsToBounds = true

        // テキスト変更時にルーラーの幅を再計算
        if let textView = textView {
            NotificationCenter.default.addObserver(self, selector: #selector(textDidChange), name: NSText.didChangeNotification, object: textView)
        }

        // 初期表示時にもルーラーの幅を計算
        DispatchQueue.main.async { [weak self] in
            self?.updateRuleThicknessAsync()
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        updateWorkItem?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func textDidChange(_ notification: Notification) {
        // デバウンス: 連続した変更を防ぐため、前のタスクをキャンセル
        updateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateRuleThicknessAsync()
        }
        updateWorkItem = workItem

        // 0.3秒後に実行（タイピング中の連続更新を防ぐ）
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func updateRuleThicknessAsync() {
        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let textStorage = layoutManager.textStorage!
        let mode = lineNumberMode

        switch mode {
        case .none:
            break

        case .paragraph:
            // パラグラフ数のカウントはバックグラウンドで実行可能（文字列のみを使用）
            let textString = textStorage.string
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                var maxLineNumber = 0
                textString.enumerateSubstrings(in: textString.startIndex..<textString.endIndex, options: .byParagraphs) { _, _, _, _ in
                    maxLineNumber += 1
                }

                // UIの更新はメインスレッドで実行
                DispatchQueue.main.async { [weak self] in
                    self?.applyRuleThickness(for: maxLineNumber)
                }
            }

        case .row:
            // LayoutManagerへのアクセスはメインスレッドでのみ可能
            // 非同期で実行してUIをブロックしないようにする
            DispatchQueue.main.async { [weak self] in
                guard let self = self,
                      let textView = self.textView,
                      let layoutManager = textView.layoutManager,
                      let textContainer = textView.textContainer else {
                    return
                }

                var maxLineNumber = 0
                let glyphRange = layoutManager.glyphRange(for: textContainer)
                layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, _, _, _ in
                    maxLineNumber += 1
                }

                self.applyRuleThickness(for: maxLineNumber)
            }
        }
    }

    private func applyRuleThickness(for maxLineNumber: Int) {
        // 最大行番号の幅を計算
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let numberString = "\(maxLineNumber)" as NSString
        let size = numberString.size(withAttributes: attributes)

        // 必要な幅を計算（左マージン + 数字の幅 + 右マージン）
        let requiredThickness = self.leftMargin + size.width + self.rightMargin
        let newThickness = max(self.minimumThickness, requiredThickness)

        if abs(self.ruleThickness - newThickness) > 1.0 {
            self.ruleThickness = newThickness
            // スクロールビューのレイアウトを更新
            if let scrollView = self.scrollView as? NSScrollView {
                scrollView.tile()
                // tile()の効果が反映された後に通知を送る（次のrunloop）
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: LineNumberRulerView.rulerThicknessDidChangeNotification, object: scrollView)
                }
            }
        }
    }

    // ルーラー幅変更通知
    static let rulerThicknessDidChangeNotification = Notification.Name("LineNumberRulerViewThicknessDidChange")

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // 背景を常に描画
        NSColor.controlBackgroundColor.setFill()
        rect.fill()

        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }

        let textStorage = layoutManager.textStorage!
        let visibleRect = self.convert(textView.visibleRect, from: textView)

        // 右端に境界線を描画
        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: rect.maxX - 0.5, y: rect.minY))
        borderPath.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY))
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // textViewの可視範囲内のglyphRangeを取得
        let textViewVisibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textViewVisibleRect, in: textContainer)

        switch lineNumberMode {
        case .none:
            break

        case .paragraph:
            // パラグラフ番号を表示
            let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            var paragraphNumber = 0
            var drawnParagraphs = Set<Int>()

            let searchRange = NSRange(location: 0, length: min(charRange.location + charRange.length, textStorage.length))
            guard let stringRange = Range(searchRange, in: textStorage.string) else { return }

            textStorage.string.enumerateSubstrings(in: stringRange, options: .byParagraphs) { (substring, substringRange, enclosingRange, stop) in
                paragraphNumber += 1

                let nsSubstringRange = NSRange(substringRange, in: textStorage.string)

                if nsSubstringRange.location >= charRange.location {
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: nsSubstringRange, actualCharacterRange: nil)
                    let rectInContainer = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

                    // textContainerの座標をtextViewの座標に変換
                    let rectInTextView = NSRect(
                        x: rectInContainer.minX + textView.textContainerInset.width,
                        y: rectInContainer.minY + textView.textContainerInset.height,
                        width: rectInContainer.width,
                        height: rectInContainer.height
                    )

                    // textViewの座標をrulerViewの座標に変換
                    let rectInRuler = self.convert(rectInTextView, from: textView)

                    if rectInRuler.minY >= rect.minY && rectInRuler.minY <= rect.maxY && !drawnParagraphs.contains(paragraphNumber) {
                        let numberString = "\(paragraphNumber)" as NSString
                        let size = numberString.size(withAttributes: attributes)
                        let xPosition = self.ruleThickness - size.width - self.rightMargin
                        let drawPoint = NSPoint(x: xPosition, y: rectInRuler.minY)
                        numberString.draw(at: drawPoint, withAttributes: attributes)
                        drawnParagraphs.insert(paragraphNumber)
                    }
                }
            }

        case .row:
            // 行番号（折り返しを含む）を表示
            var rowNumber = 0

            // 可視範囲の前の行数を計算
            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphRange.location)) { _, _, _, _, _ in
                rowNumber += 1
            }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rectInContainer, usedRect, textContainer, glyphRange, stop) in
                rowNumber += 1

                // textContainerの座標をtextViewの座標に変換
                let rectInTextView = NSRect(
                    x: rectInContainer.minX + textView.textContainerInset.width,
                    y: rectInContainer.minY + textView.textContainerInset.height,
                    width: rectInContainer.width,
                    height: rectInContainer.height
                )

                // textViewの座標をrulerViewの座標に変換
                let rectInRuler = self.convert(rectInTextView, from: textView)

                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let xPosition = self.ruleThickness - size.width - self.rightMargin
                let drawPoint = NSPoint(x: xPosition, y: rectInRuler.minY)
                numberString.draw(at: drawPoint, withAttributes: attributes)
            }
        }
    }
}
