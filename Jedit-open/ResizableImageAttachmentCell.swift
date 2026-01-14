//
//  ResizableImageAttachmentCell.swift
//  Jedit-open
//
//  Custom NSTextAttachmentCell that handles image display size correctly in both
//  horizontal and vertical text layouts.
//

import Cocoa

// MARK: - ResizableImageAttachmentCell

class ResizableImageAttachmentCell: NSTextAttachmentCell {

    // MARK: - Properties

    /// The display size for the image (may differ from the actual image size)
    var displaySize: NSSize = .zero

    // MARK: - Initialization

    override init() {
        super.init()
    }

    init(image: NSImage, displaySize: NSSize) {
        super.init()
        self.image = image
        self.displaySize = displaySize
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Cell Size

    nonisolated override func cellSize() -> NSSize {
        MainActor.assumeIsolated {
            if displaySize.width > 0 && displaySize.height > 0 {
                return displaySize
            }
            return image?.size ?? .zero
        }
    }

    // MARK: - Drawing

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        guard let image = self.image else { return }

        // Check if we're in a vertical text layout
        let isVertical: Bool
        if let textView = controlView as? NSTextView {
            isVertical = textView.layoutOrientation == .vertical
        } else {
            isVertical = false
        }

        if isVertical {
            // For vertical text, we need to rotate the image back to display correctly
            NSGraphicsContext.saveGraphicsState()

            // Move to center of cell frame
            let transform = NSAffineTransform()
            transform.translateX(by: cellFrame.midX, yBy: cellFrame.midY)
            // Rotate -90 degrees (counter-clockwise) to counter the system's rotation
            transform.rotate(byDegrees: -90)
            // Move back
            transform.translateX(by: -cellFrame.midY, yBy: -cellFrame.midX)
            transform.concat()

            // Draw with swapped dimensions
            let drawRect = NSRect(
                x: cellFrame.minY,
                y: cellFrame.minX,
                width: cellFrame.height,
                height: cellFrame.width
            )

            image.draw(in: drawRect,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0,
                       respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high])

            NSGraphicsContext.restoreGraphicsState()
        } else {
            // For horizontal text, draw normally
            image.draw(in: cellFrame,
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver,
                       fraction: 1.0,
                       respectFlipped: true,
                       hints: [.interpolation: NSImageInterpolation.high])
        }
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        // Return appropriate baseline offset
        return NSPoint(x: 0, y: 0)
    }
}
