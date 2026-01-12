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

        // ズーム後のサイズを計算
        var availableWidth = contentView.frame.width
        availableWidth = availableWidth / magnification

        // textContainerのサイズを更新（widthTracksTextView = falseなので手動で更新）
        let containerInset = textView.textContainerInset
        let containerWidth = availableWidth - (containerInset.width * 2)
        if containerWidth > 0 {
            textContainer.containerSize = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
        }

        // textViewのフレームを更新
        textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height))
    }
}

