//
//  ImageResizeController.swift
//  Jedit-open
//
//  Controller for handling image attachment resizing in NSTextView
//

import Cocoa

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
              let textContainer = textView.textContainer else {
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
        guard let textStorage = textView.textStorage,
              charIndex < textStorage.length else {
            return false
        }

        // Check for attachment attribute
        let attributes = textStorage.attributes(at: charIndex, effectiveRange: nil)
        guard let attachment = attributes[.attachment] as? NSTextAttachment else {
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

        // Try fileWrapper
        if let fileWrapper = attachment.fileWrapper,
           let data = fileWrapper.regularFileContents,
           let image = NSImage(data: data) {
            return image
        }

        return nil
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

        undoManager.setActionName("Resize Image")
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
}
