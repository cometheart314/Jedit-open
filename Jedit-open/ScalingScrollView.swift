//
//  ScalingScrollView.swift
//  Jedit-open
//
//  Created by 松本慧 on 2026/01/01.
//

import Cocoa


class ScalingScrollView: NSScrollView {

    // MARK: - Notifications

    static let magnificationDidChangeNotification = Notification.Name("ScalingScrollViewMagnificationDidChange")

    // MARK: - Properties

    private var currentMagnification: CGFloat = 1.0
    private var frameObserver: Any?

    /// フレーム変更時にコンテナサイズを自動調整するかどうか
    /// trueの場合: follows window widthモード（ウィンドウ幅に追従）
    /// falseの場合: follows paper width / fixed width / no wrapモード（EditorWindowControllerが管理）
    var autoAdjustsContainerSizeOnFrameChange: Bool = true

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()
        setupMagnification()
        setupFrameObserver()
    }

    deinit {
        if let observer = frameObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Setup

    private func setupMagnification() {
        allowsMagnification = true
        minMagnification = 0.25
        maxMagnification = 4.0
        magnification = 1.0
        currentMagnification = 1.0
    }

    private func setupFrameObserver() {
        // フレーム変更通知を有効にする
        postsFrameChangedNotifications = true

        // フレーム変更時にテキストコンテナサイズを更新
        // ただしライブリサイズ中は処理しない（viewDidEndLiveResizeで処理）
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: self,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // ライブリサイズ中は更新しない
            if !self.inLiveResize {
                self.updateTextContainerSize()
            }
        }
    }

    // MARK: - Live Resize

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // リサイズ完了後にコンテナサイズを再計算
        updateTextContainerSize()
    }

    // MARK: - Zoom Methods

    func zoomIn() {
        let newMagnification = min(currentMagnification * 1.2, maxMagnification)
        setMagnification(newMagnification, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = newMagnification
        updateTextContainerSize()
        postMagnificationNotification()
    }

    func zoomOut() {
        let newMagnification = max(currentMagnification / 1.2, minMagnification)
        setMagnification(newMagnification, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = newMagnification
        updateTextContainerSize()
        postMagnificationNotification()
    }

    func resetZoom() {
        setMagnification(1.0, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = 1.0
        updateTextContainerSize()
        postMagnificationNotification()
    }

    func setZoomLevel(_ level: CGFloat) {
        let clampedLevel = max(minMagnification, min(level, maxMagnification))
        setMagnification(clampedLevel, centeredAt: NSPoint(x: bounds.midX, y: bounds.midY))
        currentMagnification = clampedLevel
        updateTextContainerSize()
        postMagnificationNotification()
    }

    private func postMagnificationNotification() {
        NotificationCenter.default.post(
            name: ScalingScrollView.magnificationDidChangeNotification,
            object: self,
            userInfo: ["magnification": currentMagnification]
        )
    }

    // MARK: - Gesture Handling

    override func magnify(with event: NSEvent) {
        super.magnify(with: event)
        // ピンチジェスチャー終了時のみ処理
        if event.phase == .ended || event.phase == .cancelled {
            currentMagnification = magnification
            updateTextContainerSize()
            postMagnificationNotification()
        } else if event.phase == .changed {
            // ジェスチャー中も通知を送る（行番号表示更新のため）
            currentMagnification = magnification
            postMagnificationNotification()
        }
    }

    // MARK: - Helper Methods

    private func updateTextContainerSize() {
        // autoAdjustsContainerSizeOnFrameChangeがfalseの場合は、
        // EditorWindowControllerがコンテナサイズを管理するため、ここでは何もしない
        guard autoAdjustsContainerSizeOnFrameChange else { return }

        guard let textView = documentView as? NSTextView,
              let textContainer = textView.textContainer else {
            return
        }

        let isVertical = textView.layoutOrientation == .vertical
        let containerInset = textView.textContainerInset
        let padding = textContainer.lineFragmentPadding

        // macOS 26: ルーラー表示時はシステムがスクロールバー幅を追加するため、その分を補正
        let rulerCompensation: CGFloat
        if rulersVisible {
            rulerCompensation = NSScroller.scrollerWidth(for: .regular, scrollerStyle: scrollerStyle)
        } else {
            rulerCompensation = 0
        }

        if isVertical {
            // 縦書き時: 行の長さを調整
            // 縦書きでは containerSize.width が行の長さ（画面上の高さ方向）を表す
            // 水平スクロールは文章の進行に必要なので、textViewの幅は制限しない
            var availableHeight = contentView.frame.height
            // macOS 26: ルーラー表示時はシステムがスクロールバー幅を追加するため、その分を補正
            availableHeight -= rulerCompensation
            availableHeight = availableHeight / magnification
            let expectedContainerWidth = availableHeight - (containerInset.height * 2) - (padding * 2)

            if expectedContainerWidth > 0 {
                textContainer.containerSize = NSSize(width: expectedContainerWidth, height: CGFloat.greatestFiniteMagnitude)
                textView.setFrameSize(NSSize(width: textView.frame.width, height: availableHeight))
            }
        } else {
            // 横書き時: 幅を調整
            var availableWidth = contentView.frame.width
            // ルーラー表示時の補正を適用
            availableWidth -= rulerCompensation
            availableWidth = availableWidth / magnification
            let expectedContainerWidth = availableWidth - (containerInset.width * 2) - (padding * 2)

            if expectedContainerWidth > 0 {
                textContainer.containerSize = NSSize(width: expectedContainerWidth, height: CGFloat.greatestFiniteMagnitude)
                textView.setFrameSize(NSSize(width: availableWidth, height: textView.frame.height))
            }
        }
    }
}

