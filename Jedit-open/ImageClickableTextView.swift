//
//  ImageClickableTextView.swift
//  Jedit-open
//
//  Custom NSTextView subclass that detects clicks on image attachments
//

import Cocoa

// MARK: - ImageClickableTextView

class ImageClickableTextView: NSTextView {

    // MARK: - Properties

    /// Controller for handling image resize operations
    var imageResizeController: ImageResizeController?

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        // Check if we clicked on an image attachment
        let point = convert(event.locationInWindow, from: nil)

        if let controller = imageResizeController,
           controller.handleClick(in: self, at: point) {
            // Image was clicked, panel is shown, don't pass the event
            return
        }

        // Not an image click, proceed with normal behavior
        super.mouseDown(with: event)
    }
}
