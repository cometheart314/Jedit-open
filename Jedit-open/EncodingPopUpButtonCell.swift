//
//  EncodingPopUpButtonCell.swift
//  Jedit-open
//
//  Based on Apple's EncodingPopUpButtonCell
//  Converted to Swift by Claude on 2026/02/02.
//

import Cocoa

/// A popup button cell that automatically updates its contents when the encodings list changes.
/// In a nib file, to indicate that a default "Automatic" entry is wanted,
/// the first menu item should be given a tag of -1 (WantsAutomaticTag).
class EncodingPopUpButtonCell: NSPopUpButtonCell {

    // MARK: - Initialization

    override init(textCell stringValue: String, pullsDown: Bool) {
        super.init(textCell: stringValue, pullsDown: pullsDown)
        setupNotificationObserver()
        EncodingManager.shared.setupPopUpCell(self,
                                               selectedEncoding: NoStringEncoding,
                                               withDefaultEntry: false)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupNotificationObserver()

        // Check if the first item has the "wants automatic" tag
        let wantsAutomatic = numberOfItems > 0 && item(at: 0)?.tag == WantsAutomaticTag
        EncodingManager.shared.setupPopUpCell(self,
                                               selectedEncoding: NoStringEncoding,
                                               withDefaultEntry: wantsAutomatic)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setupNotificationObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(encodingsListChanged(_:)),
            name: .encodingsListChanged,
            object: nil
        )
    }

    // MARK: - Selection Override

    /// Do not allow selecting the "Customize" item and the separator before it.
    /// The customize item can be chosen and an action will be sent, but the selection doesn't change to it.
    override func selectItem(at index: Int) {
        // Only allow selection if it's not one of the last two items (separator and Customize)
        if index + 2 <= numberOfItems {
            super.selectItem(at: index)
        }
    }

    // MARK: - Notification Handler

    /// Update contents based on encodings list customization
    @objc private func encodingsListChanged(_ notification: Notification) {
        // Get current selected encoding
        var selectedEncoding: UInt = NoStringEncoding
        if let selectedItem = selectedItem,
           let encodingNumber = selectedItem.representedObject as? NSNumber {
            selectedEncoding = encodingNumber.uintValue
        }

        // Check if we want the automatic entry
        let wantsAutomatic = numberOfItems > 0 && item(at: 0)?.tag == WantsAutomaticTag

        // Rebuild the menu
        EncodingManager.shared.setupPopUpCell(self,
                                               selectedEncoding: selectedEncoding,
                                               withDefaultEntry: wantsAutomatic)
    }
}
