//
//  LineNumberView.swift
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

// MARK: - Line Number View

class LineNumberView: NSView {
    var lineNumberMode: LineNumberMode = .none {
        didSet {
            updateWidthAsync()
            needsDisplay = true
        }
    }

    weak var textView: NSTextView? {
        didSet {
            setupScrollObserver()
        }
    }

    weak var scrollView: NSScrollView?

    private let minimumWidth: CGFloat = 40.0
    private let rightMargin: CGFloat = 5.0
    private let leftMargin: CGFloat = 5.0
    private var updateWorkItem: DispatchWorkItem?
    private var scrollObserver: Any?
    private var textChangeObserver: Any?

    // 幅変更通知
    static let widthDidChangeNotification = Notification.Name("LineNumberViewWidthDidChange")

    // 現在の幅
    private(set) var currentWidth: CGFloat = 40.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.clipsToBounds = true
        self.currentWidth = minimumWidth
    }

    // 座標系を上から下に設定（NSTextViewと同じ）
    override var isFlipped: Bool {
        return true
    }

    deinit {
        updateWorkItem?.cancel()
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = textChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupScrollObserver() {
        // 既存のobserverを削除
        if let observer = scrollObserver {
            NotificationCenter.default.removeObserver(observer)
            scrollObserver = nil
        }
        if let observer = textChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            textChangeObserver = nil
        }

        guard let textView = textView,
              let scrollView = textView.enclosingScrollView else { return }

        self.scrollView = scrollView

        // スクロール時に再描画
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            self?.needsDisplay = true
        }

        // テキスト変更時に幅を再計算
        textChangeObserver = NotificationCenter.default.addObserver(
            forName: NSText.didChangeNotification,
            object: textView,
            queue: .main
        ) { [weak self] _ in
            self?.debounceUpdateWidth()
        }

        // 初期幅を計算
        DispatchQueue.main.async { [weak self] in
            self?.updateWidthAsync()
        }
    }

    private func debounceUpdateWidth() {
        updateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.updateWidthAsync()
        }
        updateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func updateWidthAsync() {
        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              textView.textContainer != nil else {
            return
        }

        let textStorage = layoutManager.textStorage!
        let mode = lineNumberMode

        switch mode {
        case .none:
            break

        case .paragraph:
            let textString = textStorage.string
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }

                var maxLineNumber = 0
                textString.enumerateSubstrings(in: textString.startIndex..<textString.endIndex, options: .byParagraphs) { _, _, _, _ in
                    maxLineNumber += 1
                }

                DispatchQueue.main.async { [weak self] in
                    self?.applyWidth(for: maxLineNumber)
                }
            }

        case .row:
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

                self.applyWidth(for: maxLineNumber)
            }
        }
    }

    private func applyWidth(for maxLineNumber: Int) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10)
        ]
        let numberString = "\(maxLineNumber)" as NSString
        let size = numberString.size(withAttributes: attributes)

        let requiredWidth = self.leftMargin + size.width + self.rightMargin
        let newWidth = max(self.minimumWidth, requiredWidth)

        if abs(self.currentWidth - newWidth) > 1.0 {
            self.currentWidth = newWidth

            // 幅変更を通知
            NotificationCenter.default.post(name: LineNumberView.widthDidChangeNotification, object: self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // 背景を描画
        NSColor.controlBackgroundColor.setFill()
        dirtyRect.fill()

        // 右端に境界線を描画
        NSColor.separatorColor.setStroke()
        let borderPath = NSBezierPath()
        borderPath.move(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.minY))
        borderPath.line(to: NSPoint(x: bounds.maxX - 0.5, y: bounds.maxY))
        borderPath.lineWidth = 1.0
        borderPath.stroke()

        guard lineNumberMode != .none,
              let textView = textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let scrollView = scrollView else {
            return
        }

        let textStorage = layoutManager.textStorage!

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        // textViewの可視範囲内のglyphRangeを取得
        let textViewVisibleRect = textView.visibleRect
        let glyphRange = layoutManager.glyphRange(forBoundingRect: textViewVisibleRect, in: textContainer)

        // スクロールオフセットを取得
        let contentBounds = scrollView.contentView.bounds

        switch lineNumberMode {
        case .none:
            break

        case .paragraph:
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
                    let yInTextView = rectInContainer.minY + textView.textContainerInset.height

                    // スクロールオフセットを考慮して行番号ビューのY座標を計算
                    let yInLineNumberView = yInTextView - contentBounds.origin.y

                    if yInLineNumberView >= dirtyRect.minY - 20 && yInLineNumberView <= dirtyRect.maxY + 20 && !drawnParagraphs.contains(paragraphNumber) {
                        let numberString = "\(paragraphNumber)" as NSString
                        let size = numberString.size(withAttributes: attributes)
                        let xPosition = self.currentWidth - size.width - self.rightMargin
                        let drawPoint = NSPoint(x: xPosition, y: yInLineNumberView)
                        numberString.draw(at: drawPoint, withAttributes: attributes)
                        drawnParagraphs.insert(paragraphNumber)
                    }
                }
            }

        case .row:
            var rowNumber = 0

            // 可視範囲の前の行数を計算
            layoutManager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: glyphRange.location)) { _, _, _, _, _ in
                rowNumber += 1
            }

            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { (rectInContainer, usedRect, textContainer, glyphRange, stop) in
                rowNumber += 1

                // textContainerの座標をtextViewの座標に変換
                let yInTextView = rectInContainer.minY + textView.textContainerInset.height

                // スクロールオフセットを考慮して行番号ビューのY座標を計算
                let yInLineNumberView = yInTextView - contentBounds.origin.y

                let numberString = "\(rowNumber)" as NSString
                let size = numberString.size(withAttributes: attributes)
                let xPosition = self.currentWidth - size.width - self.rightMargin
                let drawPoint = NSPoint(x: xPosition, y: yInLineNumberView)
                numberString.draw(at: drawPoint, withAttributes: attributes)
            }
        }
    }
}
