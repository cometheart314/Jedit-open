//
//  ImageResizePanel.swift
//  Jedit-open
//
//  Image resize panel for RTFD embedded images
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

// MARK: - ImageResizePanel

class ImageResizePanel: NSPanel {

    // MARK: - Properties

    private var widthField: NSTextField!
    private var heightField: NSTextField!
    private var scaleSlider: NSSlider!
    private var scaleLabel: NSTextField!
    private var aspectRatioCheckbox: NSButton!
    private var applyButton: NSButton!
    private var cancelButton: NSButton!

    private var originalSize: NSSize = .zero
    private var currentSize: NSSize = .zero
    private var isUpdatingFields = false

    // Callback when size changes
    var onSizeChange: ((NSSize) -> Void)?
    var onApply: ((NSSize) -> Void)?
    var onCancel: (() -> Void)?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.title = "Resize Image".localized
        self.isFloatingPanel = true
        self.becomesKeyOnlyIfNeeded = true
        self.hidesOnDeactivate = false
        self.isReleasedWhenClosed = false

        setupUI()
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let margin: CGFloat = 16
        let fieldWidth: CGFloat = 80
        let rowHeight: CGFloat = 24
        let spacing: CGFloat = 8
        let labelFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

        // ラベルの最大幅を動的に計算
        let labelStrings = ["Width:".localized, "Height:".localized, "Scale:".localized]
        let labelWidth = ceil(labelStrings.map {
            ($0 as NSString).size(withAttributes: [.font: labelFont]).width
        }.max()! + 4)

        // フィールド開始位置
        let fieldX = margin + labelWidth + spacing
        // パネル幅を計算
        let panelWidth = max(fieldX + fieldWidth + 4 + 30 + margin, 280)
        // パネル高さ（ボタンを下に余裕を持たせる）
        let panelHeight: CGFloat = 220

        self.setContentSize(NSSize(width: panelWidth, height: panelHeight))

        var yPos = panelHeight - margin - rowHeight

        // 右揃えラベルを作成するヘルパー（手動構成で確実に右揃え）
        func makeLabel(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
            let label = NSTextField(frame: NSRect(x: x, y: y, width: width, height: rowHeight))
            label.stringValue = text
            label.isEditable = false
            label.isSelectable = false
            label.isBordered = false
            label.drawsBackground = false
            label.alignment = .right
            label.font = labelFont
            label.cell?.lineBreakMode = .byClipping
            label.cell?.wraps = false
            return label
        }

        // Width row
        let widthLabel = makeLabel("Width:".localized, x: margin, y: yPos, width: labelWidth)
        contentView.addSubview(widthLabel)

        widthField = NSTextField()
        widthField.frame = NSRect(x: fieldX, y: yPos, width: fieldWidth, height: rowHeight)
        widthField.formatter = NumberFormatter()
        widthField.delegate = self
        contentView.addSubview(widthField)

        let pxLabel1 = NSTextField(labelWithString: "px")
        pxLabel1.frame = NSRect(x: fieldX + fieldWidth + 4, y: yPos, width: 30, height: rowHeight)
        contentView.addSubview(pxLabel1)

        yPos -= rowHeight + spacing

        // Height row
        let heightLabel = makeLabel("Height:".localized, x: margin, y: yPos, width: labelWidth)
        contentView.addSubview(heightLabel)

        heightField = NSTextField()
        heightField.frame = NSRect(x: fieldX, y: yPos, width: fieldWidth, height: rowHeight)
        heightField.formatter = NumberFormatter()
        heightField.delegate = self
        contentView.addSubview(heightField)

        let pxLabel2 = NSTextField(labelWithString: "px")
        pxLabel2.frame = NSRect(x: fieldX + fieldWidth + 4, y: yPos, width: 30, height: rowHeight)
        contentView.addSubview(pxLabel2)

        yPos -= rowHeight + spacing * 2

        // Aspect ratio checkbox
        aspectRatioCheckbox = NSButton(checkboxWithTitle: "Maintain aspect ratio".localized, target: self, action: #selector(aspectRatioChanged(_:)))
        aspectRatioCheckbox.frame = NSRect(x: margin, y: yPos, width: panelWidth - margin * 2, height: rowHeight)
        aspectRatioCheckbox.state = .on
        contentView.addSubview(aspectRatioCheckbox)

        yPos -= rowHeight + spacing * 2

        // Scale slider row
        let scaleTextLabel = makeLabel("Scale:".localized, x: margin, y: yPos, width: labelWidth)
        contentView.addSubview(scaleTextLabel)

        let scaleLabelWidth: CGFloat = 50
        let sliderWidth = panelWidth - fieldX - scaleLabelWidth - 4 - margin
        scaleSlider = NSSlider(value: 100, minValue: 0, maxValue: 200, target: self, action: #selector(scaleSliderChanged(_:)))
        scaleSlider.frame = NSRect(x: fieldX, y: yPos + 2, width: sliderWidth, height: rowHeight)
        scaleSlider.isContinuous = true
        contentView.addSubview(scaleSlider)

        scaleLabel = NSTextField(labelWithString: "100%")
        scaleLabel.frame = NSRect(x: fieldX + sliderWidth + 4, y: yPos, width: scaleLabelWidth, height: rowHeight)
        scaleLabel.alignment = .left
        contentView.addSubview(scaleLabel)

        // Buttons（下に余裕を持たせる）
        let buttonWidth: CGFloat = 80
        let buttonSpacing: CGFloat = 12
        let buttonY: CGFloat = 10

        cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(
            x: panelWidth - margin - buttonWidth * 2 - buttonSpacing,
            y: buttonY,
            width: buttonWidth,
            height: 28
        )
        cancelButton.keyEquivalent = "\u{1b}"
        contentView.addSubview(cancelButton)

        applyButton = NSButton(title: "Apply".localized, target: self, action: #selector(applyClicked(_:)))
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(
            x: panelWidth - margin - buttonWidth,
            y: buttonY,
            width: buttonWidth,
            height: 28
        )
        applyButton.keyEquivalent = "\r"
        contentView.addSubview(applyButton)
    }

    // MARK: - Public Methods

    func configure(with size: NSSize) {
        originalSize = size
        currentSize = size
        updateFields()
        scaleSlider.doubleValue = 100
        scaleLabel.stringValue = "100%"
    }

    // MARK: - Private Methods

    private func updateFields() {
        isUpdatingFields = true
        widthField.integerValue = Int(round(currentSize.width))
        heightField.integerValue = Int(round(currentSize.height))
        isUpdatingFields = false
    }

    private func updateScale() {
        guard originalSize.width > 0 else { return }
        let scale = currentSize.width / originalSize.width * 100
        scaleSlider.doubleValue = scale
        scaleLabel.stringValue = String(format: "%.0f%%", scale)
    }

    // MARK: - Actions

    private func commitWidthField() {
        guard !isUpdatingFields else { return }

        let newWidth = CGFloat(widthField.integerValue)
        guard newWidth > 0 else { return }

        if aspectRatioCheckbox.state == .on && originalSize.width > 0 {
            let ratio = originalSize.height / originalSize.width
            currentSize = NSSize(width: newWidth, height: newWidth * ratio)
        } else {
            currentSize.width = newWidth
        }

        updateFields()
        updateScale()
        onSizeChange?(currentSize)
    }

    private func commitHeightField() {
        guard !isUpdatingFields else { return }

        let newHeight = CGFloat(heightField.integerValue)
        guard newHeight > 0 else { return }

        if aspectRatioCheckbox.state == .on && originalSize.height > 0 {
            let ratio = originalSize.width / originalSize.height
            currentSize = NSSize(width: newHeight * ratio, height: newHeight)
        } else {
            currentSize.height = newHeight
        }

        updateFields()
        updateScale()
        onSizeChange?(currentSize)
    }

    @objc private func scaleSliderChanged(_ sender: NSSlider) {
        let scale = sender.doubleValue / 100.0
        currentSize = NSSize(
            width: originalSize.width * scale,
            height: originalSize.height * scale
        )

        updateFields()
        scaleLabel.stringValue = String(format: "%.0f%%", sender.doubleValue)
        onSizeChange?(currentSize)
    }

    @objc private func aspectRatioChanged(_ sender: NSButton) {
        // Just update the state, no immediate action needed
    }

    @objc private func applyClicked(_ sender: NSButton) {
        // End editing to commit any pending text field input
        // Check which field was being edited before resigning first responder
        let editingWidth = (self.firstResponder as? NSText)?.delegate === widthField
        let editingHeight = (self.firstResponder as? NSText)?.delegate === heightField

        self.makeFirstResponder(nil)

        // Read the current values from the text fields directly
        // in case they were changed but not committed
        let width = CGFloat(widthField.integerValue)
        let height = CGFloat(heightField.integerValue)

        if width > 0 && height > 0 {
            // If aspect ratio should be maintained, adjust the other dimension
            if aspectRatioCheckbox.state == .on && originalSize.width > 0 && originalSize.height > 0 {
                if editingWidth {
                    // Width was being edited, adjust height
                    let ratio = originalSize.height / originalSize.width
                    currentSize = NSSize(width: width, height: width * ratio)
                } else if editingHeight {
                    // Height was being edited, adjust width
                    let ratio = originalSize.width / originalSize.height
                    currentSize = NSSize(width: height * ratio, height: height)
                } else {
                    // Neither was being edited, use current values
                    currentSize = NSSize(width: width, height: height)
                }
            } else {
                currentSize = NSSize(width: width, height: height)
            }
        }

        onApply?(currentSize)
        close()
    }

    @objc private func cancelClicked(_ sender: NSButton) {
        onCancel?()
        close()
    }
}

// MARK: - NSTextFieldDelegate

extension ImageResizePanel: NSTextFieldDelegate {

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // Return key: apply and close
            applyClicked(applyButton)
            return true
        }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else { return }

        // Check if ended by Tab or Backtab (not Return, which is handled above)
        if let movementValue = obj.userInfo?["NSTextMovement"] as? Int,
           movementValue == NSTextMovement.tab.rawValue || movementValue == NSTextMovement.backtab.rawValue {
            if textField === widthField {
                commitWidthField()
            } else if textField === heightField {
                commitHeightField()
            }
        }
    }
}
