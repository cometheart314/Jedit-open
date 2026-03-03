//
//  LineSpacingPanel.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/26.
//

import Cocoa

/// 行間隔を設定するためのパネル
class LineSpacingPanel: NSPanel {

    // MARK: - Line Spacing Data

    struct LineSpacingData {
        var lineHeightMultiple: CGFloat      // 行の高さの倍率（times）
        var lineHeightMinimum: CGFloat       // 最小行高（points）
        var lineHeightMaximum: CGFloat       // 最大行高（points）
        var interLineSpacing: CGFloat        // 行間（points）
        var paragraphSpacingBefore: CGFloat  // 段落前（points）
        var paragraphSpacingAfter: CGFloat   // 段落後（points）

        static var `default`: LineSpacingData {
            LineSpacingData(
                lineHeightMultiple: 1.0,
                lineHeightMinimum: 0,
                lineHeightMaximum: 0,
                interLineSpacing: 0,
                paragraphSpacingBefore: 0,
                paragraphSpacingAfter: 0
            )
        }
    }

    // MARK: - Properties

    private var lineHeightMultipleField: NSTextField!
    private var lineHeightMultipleStepper: NSStepper!
    private var lineHeightMinField: NSTextField!
    private var lineHeightMinStepper: NSStepper!
    private var lineHeightMaxField: NSTextField!
    private var lineHeightMaxStepper: NSStepper!
    private var interLineSpacingField: NSTextField!
    private var interLineSpacingStepper: NSStepper!
    private var paragraphSpacingBeforeField: NSTextField!
    private var paragraphSpacingBeforeStepper: NSStepper!
    private var paragraphSpacingAfterField: NSTextField!
    private var paragraphSpacingAfterStepper: NSStepper!

    private var completionHandler: ((LineSpacingData?) -> Void)?
    private weak var sheetParentWindow: NSWindow?

    // MARK: - Initialization

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 230),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )

        self.title = "Line Spacing".localized
        self.isReleasedWhenClosed = false

        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = self.contentView else { return }

        let rowHeight: CGFloat = 26
        let labelWidth: CGFloat = 135
        let fieldWidth: CGFloat = 50
        let stepperWidth: CGFloat = 19
        let unitLabelWidth: CGFloat = 45
        let leftMargin: CGFloat = 20
        var currentY: CGFloat = 190

        // Row 1: Line height multiple
        let multipleLabel = NSTextField(labelWithString: "Line height multiple".localized)
        multipleLabel.frame = NSRect(x: leftMargin, y: currentY, width: labelWidth, height: 17)
        contentView.addSubview(multipleLabel)

        lineHeightMultipleField = createNumberField(
            frame: NSRect(x: leftMargin + labelWidth + 5, y: currentY - 3, width: fieldWidth, height: 22),
            minValue: 0.1,
            maxValue: 10.0,
            fractionDigits: 1
        )
        contentView.addSubview(lineHeightMultipleField)

        lineHeightMultipleStepper = createStepper(
            frame: NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5, y: currentY - 3, width: stepperWidth, height: 22),
            minValue: 0.1,
            maxValue: 10.0,
            increment: 0.1
        )
        lineHeightMultipleStepper.target = self
        lineHeightMultipleStepper.action = #selector(lineHeightMultipleStepperChanged(_:))
        contentView.addSubview(lineHeightMultipleStepper)

        let timesLabel = NSTextField(labelWithString: "times".localized)
        timesLabel.frame = NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5 + stepperWidth + 5, y: currentY, width: unitLabelWidth, height: 17)
        contentView.addSubview(timesLabel)

        currentY -= rowHeight

        // Row 2: Line height (min/max)
        let lineHeightLabel = NSTextField(labelWithString: "Line height".localized)
        lineHeightLabel.frame = NSRect(x: leftMargin, y: currentY - 10, width: 80, height: 17)
        contentView.addSubview(lineHeightLabel)

        // >= symbol
        let geLabel = NSTextField(labelWithString: "≥")
        geLabel.font = NSFont.systemFont(ofSize: 14)
        geLabel.frame = NSRect(x: leftMargin + 85, y: currentY, width: 20, height: 17)
        contentView.addSubview(geLabel)

        lineHeightMinField = createNumberField(
            frame: NSRect(x: leftMargin + 105, y: currentY - 3, width: fieldWidth - 5, height: 22),
            minValue: 0,
            maxValue: 999,
            fractionDigits: 1
        )
        contentView.addSubview(lineHeightMinField)

        lineHeightMinStepper = createStepper(
            frame: NSRect(x: leftMargin + 105 + fieldWidth - 5 + 3, y: currentY - 3, width: stepperWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            increment: 1
        )
        lineHeightMinStepper.target = self
        lineHeightMinStepper.action = #selector(lineHeightMinStepperChanged(_:))
        contentView.addSubview(lineHeightMinStepper)

        let minPointsLabel = NSTextField(labelWithString: "points".localized)
        minPointsLabel.frame = NSRect(x: leftMargin + 105 + fieldWidth - 5 + 3 + stepperWidth + 3, y: currentY, width: unitLabelWidth, height: 17)
        contentView.addSubview(minPointsLabel)

        currentY -= rowHeight

        // Row 3: Line height max (<=)
        let leLabel = NSTextField(labelWithString: "≤")
        leLabel.font = NSFont.systemFont(ofSize: 14)
        leLabel.frame = NSRect(x: leftMargin + 85, y: currentY, width: 20, height: 17)
        contentView.addSubview(leLabel)

        lineHeightMaxField = createNumberField(
            frame: NSRect(x: leftMargin + 105, y: currentY - 3, width: fieldWidth - 5, height: 22),
            minValue: 0,
            maxValue: 999,
            fractionDigits: 1
        )
        contentView.addSubview(lineHeightMaxField)

        lineHeightMaxStepper = createStepper(
            frame: NSRect(x: leftMargin + 105 + fieldWidth - 5 + 3, y: currentY - 3, width: stepperWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            increment: 1
        )
        lineHeightMaxStepper.target = self
        lineHeightMaxStepper.action = #selector(lineHeightMaxStepperChanged(_:))
        contentView.addSubview(lineHeightMaxStepper)

        let maxPointsLabel = NSTextField(labelWithString: "points".localized)
        maxPointsLabel.frame = NSRect(x: leftMargin + 105 + fieldWidth - 5 + 3 + stepperWidth + 3, y: currentY, width: unitLabelWidth, height: 17)
        contentView.addSubview(maxPointsLabel)

        currentY -= rowHeight

        // Row 4: Inter-line spacing
        let interLineLabel = NSTextField(labelWithString: "Inter-line spacing".localized)
        interLineLabel.frame = NSRect(x: leftMargin, y: currentY, width: labelWidth, height: 17)
        contentView.addSubview(interLineLabel)

        interLineSpacingField = createNumberField(
            frame: NSRect(x: leftMargin + labelWidth + 5, y: currentY - 3, width: fieldWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            fractionDigits: 1
        )
        contentView.addSubview(interLineSpacingField)

        interLineSpacingStepper = createStepper(
            frame: NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5, y: currentY - 3, width: stepperWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            increment: 1
        )
        interLineSpacingStepper.target = self
        interLineSpacingStepper.action = #selector(interLineSpacingStepperChanged(_:))
        contentView.addSubview(interLineSpacingStepper)

        let interLinePointsLabel = NSTextField(labelWithString: "points".localized)
        interLinePointsLabel.frame = NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5 + stepperWidth + 5, y: currentY, width: unitLabelWidth, height: 17)
        contentView.addSubview(interLinePointsLabel)

        currentY -= rowHeight

        // Row 5: Paragraph spacing (before)
        let paragraphLabel = NSTextField(labelWithString: "Paragraph spacing".localized)
        paragraphLabel.frame = NSRect(x: leftMargin, y: currentY - 10, width: labelWidth - 15, height: 17)
        contentView.addSubview(paragraphLabel)

        let beforeLabel = NSTextField(labelWithString: "before".localized)
        beforeLabel.alignment = .right
        beforeLabel.frame = NSRect(x: leftMargin + labelWidth - 55, y: currentY, width: 55, height: 17)
        contentView.addSubview(beforeLabel)

        paragraphSpacingBeforeField = createNumberField(
            frame: NSRect(x: leftMargin + labelWidth + 5, y: currentY - 3, width: fieldWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            fractionDigits: 1
        )
        contentView.addSubview(paragraphSpacingBeforeField)

        paragraphSpacingBeforeStepper = createStepper(
            frame: NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5, y: currentY - 3, width: stepperWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            increment: 1
        )
        paragraphSpacingBeforeStepper.target = self
        paragraphSpacingBeforeStepper.action = #selector(paragraphSpacingBeforeStepperChanged(_:))
        contentView.addSubview(paragraphSpacingBeforeStepper)

        let beforePointsLabel = NSTextField(labelWithString: "points".localized)
        beforePointsLabel.frame = NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5 + stepperWidth + 5, y: currentY, width: unitLabelWidth, height: 17)
        contentView.addSubview(beforePointsLabel)

        currentY -= rowHeight

        // Row 6: Paragraph spacing (after)
        let afterLabel = NSTextField(labelWithString: "after".localized)
        afterLabel.alignment = .right
        afterLabel.frame = NSRect(x: leftMargin + labelWidth - 55, y: currentY, width: 55, height: 17)
        contentView.addSubview(afterLabel)

        paragraphSpacingAfterField = createNumberField(
            frame: NSRect(x: leftMargin + labelWidth + 5, y: currentY - 3, width: fieldWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            fractionDigits: 1
        )
        contentView.addSubview(paragraphSpacingAfterField)

        paragraphSpacingAfterStepper = createStepper(
            frame: NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5, y: currentY - 3, width: stepperWidth, height: 22),
            minValue: 0,
            maxValue: 999,
            increment: 1
        )
        paragraphSpacingAfterStepper.target = self
        paragraphSpacingAfterStepper.action = #selector(paragraphSpacingAfterStepperChanged(_:))
        contentView.addSubview(paragraphSpacingAfterStepper)

        let afterPointsLabel = NSTextField(labelWithString: "points".localized)
        afterPointsLabel.frame = NSRect(x: leftMargin + labelWidth + 5 + fieldWidth + 5 + stepperWidth + 5, y: currentY, width: unitLabelWidth, height: 17)
        contentView.addSubview(afterPointsLabel)

        // Buttons
        let cancelButton = NSButton(title: "Cancel".localized, target: self, action: #selector(cancelClicked(_:)))
        cancelButton.frame = NSRect(x: 140, y: 13, width: 82, height: 32)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        contentView.addSubview(cancelButton)

        let okButton = NSButton(title: "OK".localized, target: self, action: #selector(okClicked(_:)))
        okButton.frame = NSRect(x: 225, y: 13, width: 82, height: 32)
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r" // Return
        contentView.addSubview(okButton)
    }

    private func createNumberField(frame: NSRect, minValue: Double, maxValue: Double, fractionDigits: Int) -> NSTextField {
        let field = NSTextField(frame: frame)
        field.alignment = .right
        field.doubleValue = 0

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimum = NSNumber(value: minValue)
        formatter.maximum = NSNumber(value: maxValue)
        formatter.minimumFractionDigits = fractionDigits
        formatter.maximumFractionDigits = fractionDigits
        field.formatter = formatter

        return field
    }

    private func createStepper(frame: NSRect, minValue: Double, maxValue: Double, increment: Double) -> NSStepper {
        let stepper = NSStepper(frame: frame)
        stepper.minValue = minValue
        stepper.maxValue = maxValue
        stepper.increment = increment
        stepper.valueWraps = false
        stepper.doubleValue = 0
        return stepper
    }

    // MARK: - Public Methods

    /// シートとして表示
    func beginSheet(
        for window: NSWindow,
        currentData: LineSpacingData,
        completionHandler: @escaping (LineSpacingData?) -> Void
    ) {
        self.sheetParentWindow = window
        self.completionHandler = completionHandler

        // 現在の値を設定
        lineHeightMultipleField.doubleValue = Double(currentData.lineHeightMultiple)
        lineHeightMultipleStepper.doubleValue = Double(currentData.lineHeightMultiple)

        lineHeightMinField.doubleValue = Double(currentData.lineHeightMinimum)
        lineHeightMinStepper.doubleValue = Double(currentData.lineHeightMinimum)

        lineHeightMaxField.doubleValue = Double(currentData.lineHeightMaximum)
        lineHeightMaxStepper.doubleValue = Double(currentData.lineHeightMaximum)

        interLineSpacingField.doubleValue = Double(currentData.interLineSpacing)
        interLineSpacingStepper.doubleValue = Double(currentData.interLineSpacing)

        paragraphSpacingBeforeField.doubleValue = Double(currentData.paragraphSpacingBefore)
        paragraphSpacingBeforeStepper.doubleValue = Double(currentData.paragraphSpacingBefore)

        paragraphSpacingAfterField.doubleValue = Double(currentData.paragraphSpacingAfter)
        paragraphSpacingAfterStepper.doubleValue = Double(currentData.paragraphSpacingAfter)

        window.beginSheet(self) { _ in }
    }

    // MARK: - Stepper Actions

    @objc private func lineHeightMultipleStepperChanged(_ sender: NSStepper) {
        lineHeightMultipleField.doubleValue = sender.doubleValue
    }

    @objc private func lineHeightMinStepperChanged(_ sender: NSStepper) {
        lineHeightMinField.doubleValue = sender.doubleValue
    }

    @objc private func lineHeightMaxStepperChanged(_ sender: NSStepper) {
        lineHeightMaxField.doubleValue = sender.doubleValue
    }

    @objc private func interLineSpacingStepperChanged(_ sender: NSStepper) {
        interLineSpacingField.doubleValue = sender.doubleValue
    }

    @objc private func paragraphSpacingBeforeStepperChanged(_ sender: NSStepper) {
        paragraphSpacingBeforeField.doubleValue = sender.doubleValue
    }

    @objc private func paragraphSpacingAfterStepperChanged(_ sender: NSStepper) {
        paragraphSpacingAfterField.doubleValue = sender.doubleValue
    }

    // MARK: - Button Actions

    @objc private func cancelClicked(_ sender: Any) {
        endSheet(with: nil)
    }

    @objc private func okClicked(_ sender: Any) {
        let data = LineSpacingData(
            lineHeightMultiple: CGFloat(lineHeightMultipleField.doubleValue),
            lineHeightMinimum: CGFloat(lineHeightMinField.doubleValue),
            lineHeightMaximum: CGFloat(lineHeightMaxField.doubleValue),
            interLineSpacing: CGFloat(interLineSpacingField.doubleValue),
            paragraphSpacingBefore: CGFloat(paragraphSpacingBeforeField.doubleValue),
            paragraphSpacingAfter: CGFloat(paragraphSpacingAfterField.doubleValue)
        )
        endSheet(with: data)
    }

    private func endSheet(with data: LineSpacingData?) {
        sheetParentWindow?.endSheet(self)
        orderOut(nil)
        completionHandler?(data)
    }
}
