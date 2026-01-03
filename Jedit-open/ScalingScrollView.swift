//
//  ScalingScrollView.swift
//  Jedit-open
//
//  Created by 松本慧 on 2026/01/01.
//

import Cocoa


class ScalingScrollView: NSScrollView {

    // MARK: - Properties

    private var currentMagnification: CGFloat = 1.0

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()
        setupMagnification()
    }

    // MARK: - Setup

    private func setupMagnification() {
        allowsMagnification = true
        minMagnification = 0.25
        maxMagnification = 4.0
        magnification = 1.0
        currentMagnification = 1.0
    }

    // MARK: - Layout

    override func tile() {
        super.tile()
        // tile()後にclipViewの自動リサイズを無効にして、textViewのサイズが勝手に変更されないようにする
        contentView.autoresizesSubviews = false
    }

    override func layout() {
        super.layout()
        updateTextContainerSize()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateTextContainerSize()
    }

    // MARK: - Zoom Methods

    func zoomIn() {
        let newMagnification = min(currentMagnification * 1.2, maxMagnification)
        setMagnification(newMagnification, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = newMagnification
        updateTextContainerSize()
    }

    func zoomOut() {
        let newMagnification = max(currentMagnification / 1.2, minMagnification)
        setMagnification(newMagnification, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = newMagnification
        updateTextContainerSize()
    }

    func resetZoom() {
        setMagnification(1.0, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = 1.0
        updateTextContainerSize()
    }

    func setZoomLevel(_ level: CGFloat) {
        let clampedLevel = max(minMagnification, min(level, maxMagnification))
        setMagnification(clampedLevel, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = clampedLevel
        updateTextContainerSize()
    }

    // MARK: - Helper Methods

    private func updateTextContainerSize() {
        guard let textView = documentView as? NSTextView,
              let textContainer = textView.textContainer else {
            return
        }

        // scrollViewのフレーム幅から利用可能な幅を計算
        var availableWidth = frame.width

        // ルーラーの幅を引く
        if hasVerticalRuler, rulersVisible, let rulerView = verticalRulerView {
            availableWidth -= rulerView.ruleThickness
        }

        // 垂直スクローラーの幅を引く
        if hasVerticalScroller, let scroller = verticalScroller, !scroller.isHidden {
            availableWidth -= scroller.frame.width
        }

        // 拡大率を考慮
        availableWidth = availableWidth / magnification

        // containerInsetを考慮してTextContainerの幅を計算
        let inset = textView.textContainerInset
        let containerWidth = availableWidth - inset.width * 2

        // TextContainerの幅を更新
        textContainer.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)

        // TextViewのサイズを更新
        textView.frame.size.width = availableWidth
    }
}

