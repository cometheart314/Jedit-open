//
//  WritingProgressView.swift
//  Jedit-open
//
//  ツールバー用の執筆進捗円グラフビュー
//  目標文字数に対する達成率を円弧で表示する
//

import Cocoa

/// ツールバーに表示する執筆進捗の円グラフビュー
class WritingProgressView: NSView {

    // MARK: - Properties

    /// 進捗率（0.0〜1.0+）
    var progress: Double = 0.0 {
        didSet {
            needsDisplay = true
            updateToolTip()
        }
    }

    /// 目標が設定されているか
    var isGoalSet: Bool = false {
        didSet {
            needsDisplay = true
            updateToolTip()
        }
    }

    /// 現在の文字数（ツールチップ表示用）
    var currentCount: Int = 0

    /// 目標文字数（ツールチップ表示用）
    var targetCount: Int = 0

    /// カウント方法（0: Unicode文字数, 1: 原稿用紙換算）
    var countMethod: Int = 0

    /// クリック時のターゲットとアクション
    weak var target: AnyObject?
    var action: Selector?

    // MARK: - Drawing Constants

    private let lineWidth: CGFloat = 3.0
    private let innerLineWidth: CGFloat = 2.0

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    private func setupView() {
        toolTip = "Writing Progress - Click to set goal".localized
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let size = min(bounds.width, bounds.height)
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        let radius = (size - lineWidth) / 2.0 - 1.0

        if !isGoalSet {
            // 目標未設定: グレーの点線リング
            drawNoGoalState(center: center, radius: radius)
        } else if progress >= 1.0 {
            // 目標達成: 二重丸
            drawGoalAchieved(center: center, radius: radius)
        } else {
            // 進捗表示: 円弧グラフ
            drawProgress(center: center, radius: radius)
        }
    }

    /// 目標未設定時の描画（グレーの破線リング + "–" テキスト）
    private func drawNoGoalState(center: NSPoint, radius: CGFloat) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        path.lineWidth = lineWidth

        NSColor.tertiaryLabelColor.setStroke()
        let pattern: [CGFloat] = [3.0, 3.0]
        path.setLineDash(pattern, count: 2, phase: 0)
        path.stroke()

        // 中央にダッシュ
        let dashString = "–"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .medium),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let dashSize = dashString.size(withAttributes: attrs)
        let dashPoint = NSPoint(x: center.x - dashSize.width / 2, y: center.y - dashSize.height / 2)
        dashString.draw(at: dashPoint, withAttributes: attrs)
    }

    /// 目標達成時の描画（二重丸 + チェック）
    private func drawGoalAchieved(center: NSPoint, radius: CGFloat) {
        // 外側リング
        let outerPath = NSBezierPath()
        outerPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        outerPath.lineWidth = lineWidth
        NSColor.controlAccentColor.setStroke()
        outerPath.stroke()

        // 内側リング（二重丸の内円）
        let innerRadius = radius - lineWidth - 1.0
        if innerRadius > 2 {
            let innerPath = NSBezierPath()
            innerPath.appendArc(withCenter: center, radius: innerRadius, startAngle: 0, endAngle: 360)
            innerPath.lineWidth = innerLineWidth
            NSColor.controlAccentColor.setStroke()
            innerPath.stroke()
        }

        // 中央に達成率（100%超の場合はその値を表示）
        let percentString: String
        if progress > 1.0 {
            percentString = "\(Int(progress * 100))%"
        } else {
            percentString = "✓"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: progress > 1.0 ? 7 : 10, weight: .bold),
            .foregroundColor: NSColor.controlAccentColor
        ]
        let textSize = percentString.size(withAttributes: attrs)
        let textPoint = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
        percentString.draw(at: textPoint, withAttributes: attrs)
    }

    /// 進捗表示の描画（背景リング + 進捗弧 + パーセンテージ）
    private func drawProgress(center: NSPoint, radius: CGFloat) {
        // 背景リング（グレー）
        let bgPath = NSBezierPath()
        bgPath.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        bgPath.lineWidth = lineWidth
        NSColor.separatorColor.setStroke()
        bgPath.stroke()

        // 進捗弧（12時位置から時計回り）
        // NSBezierPath は反時計回りが正なので、90度から開始して負方向に進む
        let startAngle: CGFloat = 90
        let endAngle: CGFloat = 90 - CGFloat(min(progress, 1.0)) * 360

        let progressPath = NSBezierPath()
        progressPath.appendArc(withCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        progressPath.lineWidth = lineWidth
        progressPath.lineCapStyle = .round
        NSColor.controlAccentColor.setStroke()
        progressPath.stroke()

        // 中央にパーセンテージテキスト
        let percent = Int(progress * 100)
        let percentString = "\(percent)%"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 7, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let textSize = percentString.size(withAttributes: attrs)
        let textPoint = NSPoint(x: center.x - textSize.width / 2, y: center.y - textSize.height / 2)
        percentString.draw(at: textPoint, withAttributes: attrs)
    }

    // MARK: - Mouse Handling

    override func mouseDown(with event: NSEvent) {
        if let action = action, let target = target {
            NSApp.sendAction(action, to: target, from: self)
        }
    }

    // MARK: - Accessibility

    override func accessibilityRole() -> NSAccessibility.Role? {
        return .button
    }

    override func accessibilityLabel() -> String? {
        if !isGoalSet {
            return "Writing Progress - No goal set".localized
        }
        let percent = Int(progress * 100)
        return String(format: "Writing Progress - %d%%".localized, percent)
    }

    // MARK: - Private

    private func updateToolTip() {
        if !isGoalSet {
            toolTip = "Writing Progress - Click to set goal".localized
            return
        }

        let percent = Int(progress * 100)
        let countLabel = countMethod == 1
            ? "pages".localized
            : "visible chars".localized

        toolTip = String(format: "%@ / %@ %@ (%d%%)",
                         DocumentStatistics.formatted(currentCount),
                         DocumentStatistics.formatted(targetCount),
                         countLabel,
                         percent)
    }
}
