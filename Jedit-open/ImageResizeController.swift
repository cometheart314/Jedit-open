//
//  ImageResizeController.swift
//  Jedit-open
//
//  Controller for handling image attachment resizing in NSTextView
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

// MARK: - ImageResizeController

class ImageResizeController: NSObject {

    // MARK: - Properties

    private weak var textStorage: NSTextStorage?
    private weak var undoManager: UndoManager?

    private var resizePanel: ImageResizePanel?
    private var currentAttachmentRange: NSRange?
    private var currentAttachment: NSTextAttachment?
    private var originalSize: NSSize?
    private var originalImage: NSImage?
    private var originalFileWrapper: FileWrapper?

    // MARK: - Initialization

    init(textStorage: NSTextStorage, undoManager: UndoManager?) {
        self.textStorage = textStorage
        self.undoManager = undoManager
        super.init()
    }

    // MARK: - Public Methods

    /// Handle click on text view to detect image attachment clicks
    /// Returns true if an image was clicked and panel was shown
    func handleClick(in textView: NSTextView, at point: NSPoint) -> Bool {
        // Get character index at the click point
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer,
              let textStorage = textView.textStorage,
              textStorage.length > 0 else {
            return false
        }

        // Convert point to text container coordinates
        let textContainerOrigin = textView.textContainerOrigin
        let locationInContainer = NSPoint(
            x: point.x - textContainerOrigin.x,
            y: point.y - textContainerOrigin.y
        )

        // Get glyph index at point
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: locationInContainer, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)

        // Convert glyph index to character index
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)

        // Check if there's an attachment at this character index
        guard charIndex < textStorage.length else {
            return false
        }

        // Check for attachment attribute
        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        guard let attachment = attributes[.attachment] as? NSTextAttachment else {
            return false
        }

        // 動画アタッチメントはダブルクリックでリサイズせず外部アプリで開く
        if isVideoAttachment(attachment) {
            return false
        }

        // Get the image
        let image = getImage(from: attachment)
        guard let img = image else {
            return false
        }

        // Get the current display size
        let displaySize = getDisplaySize(attachment, image: img)
        guard displaySize.width > 0 && displaySize.height > 0 else {
            return false
        }

        // Store the current attachment info for resizing
        currentAttachment = attachment
        currentAttachmentRange = NSRange(location: charIndex, length: 1)
        originalSize = displaySize
        originalImage = img
        originalFileWrapper = attachment.fileWrapper

        // Show resize panel
        showResizePanel(for: attachment, currentSize: displaySize, in: textView)

        return true
    }

    // MARK: - Private Methods

    /// 動画ファイルの拡張子セット
    private static let videoExtensions: Set<String> = [
        "mov", "mp4", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "wmv", "flv"
    ]

    /// FileWrapper が動画ファイルかどうかを判定
    static func isVideoFileWrapper(_ fileWrapper: FileWrapper) -> Bool {
        guard let filename = fileWrapper.preferredFilename ?? fileWrapper.filename else {
            return false
        }
        let ext = (filename as NSString).pathExtension.lowercased()
        return videoExtensions.contains(ext)
    }

    /// アタッチメントが動画ファイルかどうかを判定
    private func isVideoAttachment(_ attachment: NSTextAttachment) -> Bool {
        guard let fileWrapper = attachment.fileWrapper else { return false }
        return Self.isVideoFileWrapper(fileWrapper)
    }

    /// 外部から動画判定を行うためのメソッド
    func isVideo(attachment: NSTextAttachment) -> Bool {
        return isVideoAttachment(attachment)
    }

    /// FileWrapper からファイルデータを取得する（シンボリックリンク対応）
    private func fileContents(of fileWrapper: FileWrapper) -> Data? {
        // 通常のファイル
        if let data = fileWrapper.regularFileContents {
            return data
        }
        // シンボリックリンクの場合はリンク先からデータを読み込む
        if fileWrapper.isSymbolicLink, let destURL = fileWrapper.symbolicLinkDestinationURL {
            return try? Data(contentsOf: destURL)
        }
        return nil
    }

    private func getImage(from attachment: NSTextAttachment) -> NSImage? {
        // Try attachment.image first
        if let image = attachment.image {
            return image
        }

        // Try attachment cell
        if let cell = attachment.attachmentCell as? NSTextAttachmentCell,
           let image = cell.image {
            return image
        }

        // Try contents
        if let contents = attachment.contents,
           let image = NSImage(data: contents) {
            return image
        }

        // Try fileWrapper（シンボリックリンク対応）
        if let fileWrapper = attachment.fileWrapper,
           let data = fileContents(of: fileWrapper) {
            if let image = NSImage(data: data) {
                return image
            }

            // 動画ファイルの場合はポスターフレームを取得
            if isVideoAttachment(attachment) {
                return getVideoThumbnail(from: data, fileWrapper: fileWrapper)
            }
        }

        return nil
    }

    /// 動画データからサムネイル（ポスターフレーム）を取得
    private func getVideoThumbnail(from data: Data, fileWrapper: FileWrapper) -> NSImage? {
        // 一時ファイルに書き出して AVAsset で読み込む
        let tempDir = FileManager.default.temporaryDirectory
        let filename = fileWrapper.preferredFilename ?? fileWrapper.filename ?? "video.mov"
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString + "_" + filename)

        do {
            try data.write(to: tempURL)
        } catch {
            return nil
        }

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let asset = AVAsset(url: tempURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true

        do {
            let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            return nil
        }
    }

    private func getDisplaySize(_ attachment: NSTextAttachment, image: NSImage) -> NSSize {
        // Check if bounds are set (custom size)
        if attachment.bounds.size.width > 0 && attachment.bounds.size.height > 0 {
            return attachment.bounds.size
        }

        // Check attachment cell size
        if let cell = attachment.attachmentCell as? NSTextAttachmentCell {
            let cellSize = cell.cellSize
            if cellSize.width > 0 && cellSize.height > 0 {
                return cellSize
            }
        }

        // Fall back to image's natural size
        return image.size
    }

    private func showResizePanel(for attachment: NSTextAttachment, currentSize: NSSize, in textView: NSTextView) {
        // Close existing panel if any
        resizePanel?.close()

        // Create new panel
        let panel = ImageResizePanel()
        resizePanel = panel

        // Configure panel
        panel.configure(with: currentSize)

        // Set up callbacks
        panel.onSizeChange = { [weak self] newSize in
            self?.previewResize(to: newSize, in: textView)
        }

        panel.onApply = { [weak self] newSize in
            self?.applyResize(to: newSize, in: textView)
        }

        panel.onCancel = { [weak self] in
            self?.cancelResize(in: textView)
        }

        // Position panel near the text view window
        if let window = textView.window {
            let windowFrame = window.frame
            let panelFrame = panel.frame
            let x = windowFrame.maxX + 10
            let y = windowFrame.midY - panelFrame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.makeKeyAndOrderFront(nil)
    }

    private func previewResize(to newSize: NSSize, in textView: NSTextView) {
        // Preview is disabled - changes are applied only when Apply is clicked
        // This avoids issues with attachment replacement during preview
    }

    private func applyResize(to newSize: NSSize, in textView: NSTextView) {
        guard let textStorage = textView.textStorage,
              let range = currentAttachmentRange,
              let oldSize = originalSize,
              let image = originalImage else {
            return
        }

        // Register undo before making the change
        registerUndo(oldSize: oldSize, newSize: newSize, range: range, in: textView)

        // Create a new attachment that preserves original image resolution
        let newAttachment = NSTextAttachment()

        // Keep original file wrapper to preserve full resolution image data
        if let fileWrapper = originalFileWrapper {
            newAttachment.fileWrapper = fileWrapper
        }

        // Use custom cell for proper vertical text support
        let cell = ResizableImageAttachmentCell(image: image, displaySize: newSize)
        newAttachment.attachmentCell = cell

        // Also set bounds for persistence
        newAttachment.bounds = CGRect(origin: .zero, size: newSize)

        // Create attributed string with the new attachment
        let attachmentString = NSAttributedString(attachment: newAttachment)

        // Replace the character entirely
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: range, with: attachmentString)
        textStorage.endEditing()

        // Update the range for undo (it's still length 1)
        currentAttachmentRange = NSRange(location: range.location, length: 1)

        // Force layout update
        for layoutManager in textStorage.layoutManagers {
            let fullRange = NSRange(location: 0, length: textStorage.length)
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
            layoutManager.ensureLayout(forCharacterRange: fullRange)

            // Force display update for all text views
            for textContainer in layoutManager.textContainers {
                if let tv = textContainer.textView {
                    tv.needsDisplay = true
                    tv.setNeedsDisplay(tv.bounds)
                }
            }
        }

        textView.needsDisplay = true

        // Clear state
        clearState()
    }

    private func cancelResize(in textView: NSTextView) {
        // Cancel doesn't need to restore anything since we don't do live preview
        // Just clear state and close panel
        textView.needsDisplay = true
        clearState()
    }

    private func registerUndo(oldSize: NSSize, newSize: NSSize, range: NSRange, in textView: NSTextView) {
        guard let undoManager = self.undoManager,
              let image = originalImage else { return }

        // Capture values for the undo block
        let capturedImage = image
        let capturedFileWrapper = originalFileWrapper

        undoManager.registerUndo(withTarget: self) { [weak self, weak textView] controller in
            guard let _ = self,
                  let textView = textView,
                  let textStorage = textView.textStorage else { return }

            // Get current attachment
            guard range.location < textStorage.length else { return }

            // Create attachment with old size, preserving original resolution
            let restoredAttachment = NSTextAttachment()
            if let fileWrapper = capturedFileWrapper {
                restoredAttachment.fileWrapper = fileWrapper
            }

            // Use custom cell for proper vertical text support
            let cell = ResizableImageAttachmentCell(image: capturedImage, displaySize: oldSize)
            restoredAttachment.attachmentCell = cell
            restoredAttachment.bounds = CGRect(origin: .zero, size: oldSize)

            // Create attributed string with the attachment
            let attachmentString = NSAttributedString(attachment: restoredAttachment)

            // Replace the character entirely
            textStorage.beginEditing()
            textStorage.replaceCharacters(in: range, with: attachmentString)
            textStorage.endEditing()

            // Force layout update
            for layoutManager in textStorage.layoutManagers {
                let fullRange = NSRange(location: 0, length: textStorage.length)
                layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
                layoutManager.ensureLayout(forCharacterRange: fullRange)
            }

            textView.needsDisplay = true

            // Register redo
            controller.originalImage = capturedImage
            controller.originalFileWrapper = capturedFileWrapper
            controller.registerUndo(oldSize: newSize, newSize: oldSize, range: range, in: textView)
        }

        // 動画かどうかでUndoアクション名を切り替え
        if let fw = capturedFileWrapper, Self.isVideoFileWrapper(fw) {
            undoManager.setActionName("Resize Video".localized)
        } else {
            undoManager.setActionName("Resize Image".localized)
        }
    }

    private func clearState() {
        currentAttachment = nil
        currentAttachmentRange = nil
        originalSize = nil
        originalImage = nil
        originalFileWrapper = nil
    }

    /// Close the resize panel if open
    func closePanel() {
        resizePanel?.close()
        resizePanel = nil
    }

    /// Check if there's an image/video attachment at the given character index
    /// Returns the attachment info if found
    func getImageAttachment(in textView: NSTextView, at charIndex: Int) -> (attachment: NSTextAttachment, image: NSImage, size: NSSize)? {
        guard let textStorage = textView.textStorage,
              charIndex < textStorage.length else {
            return nil
        }

        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        guard let attachment = attributes[.attachment] as? NSTextAttachment else {
            return nil
        }

        // まず通常の画像取得を試みる
        if let image = getImage(from: attachment) {
            let displaySize = getDisplaySize(attachment, image: image)
            guard displaySize.width > 0 && displaySize.height > 0 else {
                return nil
            }
            return (attachment, image, displaySize)
        }

        // 動画アタッチメントの場合、セルやビューから表示サイズを取得してポスターフレームを生成
        if isVideoAttachment(attachment) {
            let (image, size) = getVideoAttachmentInfo(attachment, in: textView, at: charIndex)
            if let image = image, size.width > 0 && size.height > 0 {
                return (attachment, image, size)
            }
        }

        return nil
    }

    /// 動画アタッチメントの情報（ポスターフレームとサイズ）を取得
    private func getVideoAttachmentInfo(_ attachment: NSTextAttachment, in textView: NSTextView, at charIndex: Int) -> (NSImage?, NSSize) {
        var displaySize = NSSize.zero

        // bounds からサイズを取得
        if attachment.bounds.size.width > 0 && attachment.bounds.size.height > 0 {
            displaySize = attachment.bounds.size
        }

        // attachmentCell からサイズを取得（NSTextAttachmentCell以外のセルも対応）
        if displaySize.width <= 0 || displaySize.height <= 0,
           let cell = attachment.attachmentCell {
            let cellSize = cell.cellSize()
            if cellSize.width > 0 && cellSize.height > 0 {
                displaySize = cellSize
            }
        }

        // レイアウトマネージャーから表示矩形を取得
        if displaySize.width <= 0 || displaySize.height <= 0,
           let layoutManager = textView.layoutManager {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
            let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textView.textContainer!)
            if rect.width > 0 && rect.height > 0 {
                displaySize = rect.size
            }
        }

        // ポスターフレームを一時ファイル経由で取得（シンボリックリンク対応）
        if let fileWrapper = attachment.fileWrapper,
           let data = fileContents(of: fileWrapper) {
            if let thumbnail = getVideoThumbnail(from: data, fileWrapper: fileWrapper) {
                // サイズが未取得ならサムネイルのサイズを使用
                if displaySize.width <= 0 || displaySize.height <= 0 {
                    displaySize = thumbnail.size
                }
                return (thumbnail, displaySize)
            }
        }

        // ポスターフレーム取得失敗時はプレースホルダー画像を作成
        if displaySize.width > 0 && displaySize.height > 0 {
            let placeholder = NSImage(size: displaySize)
            placeholder.lockFocus()
            NSColor.darkGray.setFill()
            NSBezierPath(rect: NSRect(origin: .zero, size: displaySize)).fill()
            // 再生アイコン風の三角形を描画
            let triangleSize: CGFloat = min(displaySize.width, displaySize.height) * 0.3
            let centerX = displaySize.width / 2
            let centerY = displaySize.height / 2
            let path = NSBezierPath()
            path.move(to: NSPoint(x: centerX - triangleSize * 0.4, y: centerY - triangleSize * 0.5))
            path.line(to: NSPoint(x: centerX - triangleSize * 0.4, y: centerY + triangleSize * 0.5))
            path.line(to: NSPoint(x: centerX + triangleSize * 0.5, y: centerY))
            path.close()
            NSColor.white.withAlphaComponent(0.8).setFill()
            path.fill()
            placeholder.unlockFocus()
            return (placeholder, displaySize)
        }

        return (nil, .zero)
    }

    /// Show resize panel for an attachment at the specified character index
    /// Called from context menu
    func showResizePanelForAttachment(in textView: NSTextView, at charIndex: Int) {
        guard let (attachment, image, displaySize) = getImageAttachment(in: textView, at: charIndex) else {
            return
        }

        // Store the current attachment info for resizing
        currentAttachment = attachment
        currentAttachmentRange = NSRange(location: charIndex, length: 1)
        originalSize = displaySize
        originalImage = image
        originalFileWrapper = attachment.fileWrapper

        // Show resize panel
        showResizePanel(for: attachment, currentSize: displaySize, in: textView)
    }
}
