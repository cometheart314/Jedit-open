//
//  ImageResizePanel.swift
//  Jedit-open
//
//  Image resize panel for RTFD embedded images
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
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 200),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        self.title = "Resize Image"
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
        let labelWidth: CGFloat = 50
        let fieldWidth: CGFloat = 80
        let rowHeight: CGFloat = 24
        let spacing: CGFloat = 8

        var yPos = contentView.bounds.height - margin - rowHeight

        // Width row
        let widthLabel = NSTextField(labelWithString: "Width:")
        widthLabel.frame = NSRect(x: margin, y: yPos, width: labelWidth, height: rowHeight)
        widthLabel.alignment = .right
        contentView.addSubview(widthLabel)

        widthField = NSTextField()
        widthField.frame = NSRect(x: margin + labelWidth + spacing, y: yPos, width: fieldWidth, height: rowHeight)
        widthField.formatter = NumberFormatter()
        widthField.target = self
        widthField.action = #selector(widthFieldChanged(_:))
        contentView.addSubview(widthField)

        let pxLabel1 = NSTextField(labelWithString: "px")
        pxLabel1.frame = NSRect(x: margin + labelWidth + spacing + fieldWidth + 4, y: yPos, width: 30, height: rowHeight)
        contentView.addSubview(pxLabel1)

        yPos -= rowHeight + spacing

        // Height row
        let heightLabel = NSTextField(labelWithString: "Height:")
        heightLabel.frame = NSRect(x: margin, y: yPos, width: labelWidth, height: rowHeight)
        heightLabel.alignment = .right
        contentView.addSubview(heightLabel)

        heightField = NSTextField()
        heightField.frame = NSRect(x: margin + labelWidth + spacing, y: yPos, width: fieldWidth, height: rowHeight)
        heightField.formatter = NumberFormatter()
        heightField.target = self
        heightField.action = #selector(heightFieldChanged(_:))
        contentView.addSubview(heightField)

        let pxLabel2 = NSTextField(labelWithString: "px")
        pxLabel2.frame = NSRect(x: margin + labelWidth + spacing + fieldWidth + 4, y: yPos, width: 30, height: rowHeight)
        contentView.addSubview(pxLabel2)

        yPos -= rowHeight + spacing * 2

        // Aspect ratio checkbox
        aspectRatioCheckbox = NSButton(checkboxWithTitle: "Maintain aspect ratio", target: self, action: #selector(aspectRatioChanged(_:)))
        aspectRatioCheckbox.frame = NSRect(x: margin, y: yPos, width: 200, height: rowHeight)
        aspectRatioCheckbox.state = .on
        contentView.addSubview(aspectRatioCheckbox)

        yPos -= rowHeight + spacing * 2

        // Scale slider row
        let scaleTextLabel = NSTextField(labelWithString: "Scale:")
        scaleTextLabel.frame = NSRect(x: margin, y: yPos, width: labelWidth, height: rowHeight)
        scaleTextLabel.alignment = .right
        contentView.addSubview(scaleTextLabel)

        scaleSlider = NSSlider(value: 100, minValue: 10, maxValue: 400, target: self, action: #selector(scaleSliderChanged(_:)))
        scaleSlider.frame = NSRect(x: margin + labelWidth + spacing, y: yPos, width: 130, height: rowHeight)
        scaleSlider.isContinuous = true
        contentView.addSubview(scaleSlider)

        scaleLabel = NSTextField(labelWithString: "100%")
        scaleLabel.frame = NSRect(x: margin + labelWidth + spacing + 135, y: yPos, width: 50, height: rowHeight)
        scaleLabel.alignment = .left
        contentView.addSubview(scaleLabel)

        yPos -= rowHeight + spacing * 2

        // Buttons
        let buttonWidth: CGFloat = 80
        let buttonSpacing: CGFloat = 12

        cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked(_:)))
        cancelButton.bezelStyle = .rounded
        cancelButton.frame = NSRect(
            x: contentView.bounds.width - margin - buttonWidth * 2 - buttonSpacing,
            y: margin,
            width: buttonWidth,
            height: 28
        )
        cancelButton.keyEquivalent = "\u{1b}" // Escape key
        contentView.addSubview(cancelButton)

        applyButton = NSButton(title: "Apply", target: self, action: #selector(applyClicked(_:)))
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(
            x: contentView.bounds.width - margin - buttonWidth,
            y: margin,
            width: buttonWidth,
            height: 28
        )
        applyButton.keyEquivalent = "\r" // Enter key
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

    @objc private func widthFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingFields else { return }

        let newWidth = CGFloat(sender.integerValue)
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

    @objc private func heightFieldChanged(_ sender: NSTextField) {
        guard !isUpdatingFields else { return }

        let newHeight = CGFloat(sender.integerValue)
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
        onApply?(currentSize)
        close()
    }

    @objc private func cancelClicked(_ sender: NSButton) {
        onCancel?()
        close()
    }
}
