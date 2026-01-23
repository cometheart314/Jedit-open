//
//  LabeledRulerView.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/22.
//

import Cocoa

/// ルーラーの右端にタイプラベルを表示するカスタムNSRulerView
class LabeledRulerView: NSRulerView {

    /// ルーラータイプのラベルテキスト
    var typeLabel: String = "" {
        didSet {
            needsDisplay = true
        }
    }

    /// キャレット（挿入点）のルーラー上の位置（ドキュメント座標系）
    /// 横ルーラーの場合はX座標、縦ルーラーの場合はY座標
    var caretPosition: CGFloat? {
        didSet {
            needsDisplay = true
        }
    }

    /// キャレットスリットの色
    var caretSlitColor: NSColor = NSColor.systemRed.withAlphaComponent(0.8)

    override var isFlipped: Bool {
        return true  // 上から下への座標系を使用
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // リサイズ終了時に全体を再描画してラベルが正しい位置に表示されるようにする
        needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // フレームサイズが変わったら再描画
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        // 先にラベルを描画（目盛りの下に表示）
        if orientation == .horizontalRuler {
            drawTypeLabel()
        } else if orientation == .verticalRuler {
            drawVerticalRulerLabel()
        }

        // 目盛りとラベルを描画（ラベルの上に表示）
        super.drawHashMarksAndLabels(in: rect)

        // キャレット位置のスリットを描画（目盛りの上に表示）
        drawCaretSlit()
    }

    /// キャレット位置を示すスリット（細線）を描画
    private func drawCaretSlit() {
        guard let position = caretPosition else { return }
        guard let scrollView = self.scrollView else { return }

        // ルーラーのオリジン（baselineLocation）を考慮
        let baseline = baselineLocation

        // ズーム倍率を取得
        let magnification = scrollView.magnification

        if orientation == .horizontalRuler {
            // 横ルーラー：キャレットのX位置に縦線を描画
            // caretPositionはテキストコンテナ座標系の値
            // ズーム倍率を適用し、スクロール位置とoriginOffset（ズーム適用済み）を考慮
            let clipView = scrollView.contentView
            let scrollOffsetX = clipView.bounds.origin.x
            // originOffsetもズーム倍率の影響を受ける（ページモードでのマージン）
            let scaledOriginOffset = originOffset * magnification
            let xInRuler = position * magnification - scrollOffsetX + scaledOriginOffset

            // スリットの描画
            let slitRect = NSRect(
                x: xInRuler - 0.5,
                y: baseline,
                width: 1.0,
                height: bounds.height - baseline
            )

            // 可視範囲内かチェック
            if slitRect.minX >= visibleRect.minX && slitRect.maxX <= visibleRect.maxX {
                caretSlitColor.setFill()
                slitRect.fill()

                // 小さな三角形のインジケータを上部に描画
                let trianglePath = NSBezierPath()
                let triangleSize: CGFloat = 4.0
                let centerX = xInRuler
                let topY = baseline

                trianglePath.move(to: NSPoint(x: centerX, y: topY + triangleSize))
                trianglePath.line(to: NSPoint(x: centerX - triangleSize, y: topY))
                trianglePath.line(to: NSPoint(x: centerX + triangleSize, y: topY))
                trianglePath.close()
                trianglePath.fill()
            }
        } else if orientation == .verticalRuler {
            // 縦ルーラー：キャレットのY位置に横線を描画
            // caretPositionはテキストコンテナ座標系の値
            // ズーム倍率を適用し、スクロール位置とoriginOffset（ズーム適用済み）を考慮
            let clipView = scrollView.contentView
            let scrollOffsetY = clipView.bounds.origin.y
            // originOffsetもズーム倍率の影響を受ける（ページモードでのマージン）
            let scaledOriginOffset = originOffset * magnification
            let yInRuler = position * magnification - scrollOffsetY + scaledOriginOffset

            // スリットの描画
            let slitRect = NSRect(
                x: baseline,
                y: yInRuler - 0.5,
                width: bounds.width - baseline,
                height: 1.0
            )

            // 可視範囲内かチェック
            if slitRect.minY >= visibleRect.minY && slitRect.maxY <= visibleRect.maxY {
                caretSlitColor.setFill()
                slitRect.fill()

                // 小さな三角形のインジケータを左側に描画
                let trianglePath = NSBezierPath()
                let triangleSize: CGFloat = 4.0
                let centerY = yInRuler
                let leftX = baseline

                trianglePath.move(to: NSPoint(x: leftX + triangleSize, y: centerY))
                trianglePath.line(to: NSPoint(x: leftX, y: centerY - triangleSize))
                trianglePath.line(to: NSPoint(x: leftX, y: centerY + triangleSize))
                trianglePath.close()
                trianglePath.fill()
            }
        }
    }

    /// 縦ルーラー用のラベル描画（縦書き）
    private func drawVerticalRulerLabel() {
        guard !typeLabel.isEmpty else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let labelSize = typeLabel.size(withAttributes: attributes)

        // 縦ルーラー: 下端に縦書きで描画
        let rulerBounds = self.bounds

        // 回転後の描画位置を計算
        // 回転の中心点を設定し、-90度回転させて縦書きにする
        let rotatedWidth = labelSize.height
        let rotatedHeight = labelSize.width

        // 左寄せ、上に少し余裕を持たせる
        let x: CGFloat = 1
        let y: CGFloat = rulerBounds.maxY - rotatedHeight - 16

        // グラフィックスコンテキストを保存
        NSGraphicsContext.current?.saveGraphicsState()

        // 回転の中心点を設定
        let transform = NSAffineTransform()
        transform.translateX(by: x + rotatedWidth / 2, yBy: y + rotatedHeight / 2)
        transform.rotate(byDegrees: -90)
        transform.translateX(by: -labelSize.width / 2, yBy: -labelSize.height / 2)
        transform.concat()

        // 背景を描画
        let bgRect = NSRect(x: 0, y: 0, width: labelSize.width, height: labelSize.height).insetBy(dx: -2, dy: -1)
        let bgColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9)
        bgColor.setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2).fill()

        // テキストを描画
        let labelRect = NSRect(x: 0, y: 0, width: labelSize.width, height: labelSize.height)
        typeLabel.draw(in: labelRect, withAttributes: attributes)

        // グラフィックスコンテキストを復元
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    private func drawTypeLabel() {
        guard !typeLabel.isEmpty else { return }

        // グレーの文字でラベルを描画
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]

        let labelSize = typeLabel.size(withAttributes: attributes)

        // ルーラーの方向に応じて描画位置を決定
        let labelRect: NSRect
        if orientation == .horizontalRuler {
            // 横ルーラー: 可視領域の右端、上付き位置に描画
            let visibleRect = self.visibleRect
            let x = visibleRect.maxX - labelSize.width - 4
            let y = visibleRect.minY + 2  // 上付き位置（flipped座標系）
            labelRect = NSRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
        } else {
            // 縦ルーラー: 可視領域の下端に描画
            let visibleRect = self.visibleRect
            let x = visibleRect.minX + 2
            let y = visibleRect.maxY - labelSize.height - 4  // 下端（flipped座標系）
            labelRect = NSRect(x: x, y: y, width: labelSize.width, height: labelSize.height)
        }

        // 背景を描画
        let bgRect = labelRect.insetBy(dx: -2, dy: -1)
        let bgColor = NSColor.controlBackgroundColor.withAlphaComponent(0.9)
        bgColor.setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 2, yRadius: 2).fill()

        typeLabel.draw(in: labelRect, withAttributes: attributes)
    }
}
