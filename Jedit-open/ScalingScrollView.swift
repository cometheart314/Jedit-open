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

    // MARK: - Split Buttons

    private var splitNoneButton: NSButton?
    private var splitVertButton: NSButton?
    private var splitHoriButton: NSButton?

    /// スプリットボタンのアクションターゲット（通常はEditorWindowController）
    weak var splitButtonTarget: AnyObject?

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()
        setupMagnification()
        setupFrameObserver()
        setupSplitButtons()
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

    private func setupSplitButtons() {
        // スプリットボタンのサイズ（画像サイズに合わせる: 16x12）
        let buttonWidth: CGFloat = 16.0
        let buttonHeight: CGFloat = 12.0

        // splitNoneButton - 単一ビューに戻す
        let noneButton = NSButton(frame: NSRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight))
        noneButton.title = ""
        noneButton.setButtonType(.momentaryLight)
        noneButton.bezelStyle = .shadowlessSquare
        noneButton.isBordered = false
        noneButton.image = NSImage(named: "splitNone")
        noneButton.imagePosition = .imageOnly
        noneButton.imageScaling = .scaleNone
        noneButton.target = nil
        noneButton.action = #selector(EditorWindowController.collapseViews(_:))
        noneButton.refusesFirstResponder = true
        noneButton.toolTip = NSLocalizedString("Collapse to single view.", comment: "Split button tooltip")
        addSubview(noneButton)
        splitNoneButton = noneButton

        // splitHoriButton - 水平分割
        let horiButton = NSButton(frame: NSRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight))
        horiButton.title = ""
        horiButton.setButtonType(.momentaryLight)
        horiButton.bezelStyle = .shadowlessSquare
        horiButton.isBordered = false
        horiButton.image = NSImage(named: "splitHori")
        horiButton.imagePosition = .imageOnly
        horiButton.imageScaling = .scaleNone
        horiButton.target = nil
        horiButton.action = #selector(EditorWindowController.splitHorizontally(_:))
        horiButton.refusesFirstResponder = true
        horiButton.toolTip = NSLocalizedString("Split view horizontally.", comment: "Split button tooltip")
        addSubview(horiButton)
        splitHoriButton = horiButton

        // splitVertButton - 垂直分割
        let vertButton = NSButton(frame: NSRect(x: 0, y: 0, width: buttonWidth, height: buttonHeight))
        vertButton.title = ""
        vertButton.setButtonType(.momentaryLight)
        vertButton.bezelStyle = .shadowlessSquare
        vertButton.isBordered = false
        vertButton.image = NSImage(named: "splitVert")
        vertButton.imagePosition = .imageOnly
        vertButton.imageScaling = .scaleNone
        vertButton.target = nil
        vertButton.action = #selector(EditorWindowController.splitVertically(_:))
        vertButton.refusesFirstResponder = true
        vertButton.toolTip = NSLocalizedString("Split view vertically.", comment: "Split button tooltip")
        addSubview(vertButton)
        splitVertButton = vertButton
    }

    // MARK: - Live Resize

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        // リサイズ完了後にコンテナサイズを再計算
        updateTextContainerSize()
    }

    // MARK: - Tile Override

    override func tile() {
        super.tile()

        guard let verticalScroller = verticalScroller,
              let splitNoneButton = splitNoneButton,
              let splitHoriButton = splitHoriButton,
              let splitVertButton = splitVertButton else {
            return
        }

        var verticalScrollerFrame = verticalScroller.frame
        let buttonHeight = splitNoneButton.frame.height

        // splitNoneButton - 縦スクロールバーの最上部
        var buttonFrame = verticalScrollerFrame
        buttonFrame.size.height = buttonHeight
        buttonFrame.size.width = verticalScrollerFrame.width

        verticalScrollerFrame.origin.y += buttonHeight
        verticalScrollerFrame.size.height -= buttonHeight
        verticalScroller.frame = verticalScrollerFrame
        splitNoneButton.frame = buttonFrame

        // splitHoriButton - splitNoneButtonの下
        buttonFrame = verticalScrollerFrame
        buttonFrame.size.height = buttonHeight
        buttonFrame.size.width = verticalScrollerFrame.width

        verticalScrollerFrame.origin.y += buttonHeight
        verticalScrollerFrame.size.height -= buttonHeight
        verticalScroller.frame = verticalScrollerFrame
        splitHoriButton.frame = buttonFrame

        // splitVertButton - splitHoriButtonの下
        buttonFrame = verticalScrollerFrame
        buttonFrame.size.height = buttonHeight
        buttonFrame.size.width = verticalScrollerFrame.width

        verticalScrollerFrame.origin.y += buttonHeight
        verticalScrollerFrame.size.height -= buttonHeight
        verticalScroller.frame = verticalScrollerFrame
        splitVertButton.frame = buttonFrame
    }

    // MARK: - Appearance Change

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // アピアランス変更時にスプリットボタンの画像を再設定
        updateSplitButtonImages()
    }

    private func updateSplitButtonImages() {
        // NSImageはアセットカタログのダークモード対応画像を自動で取得するが、
        // 既存のボタンの画像は更新されないため、明示的に再設定する
        splitNoneButton?.image = NSImage(named: "splitNone")
        splitHoriButton?.image = NSImage(named: "splitHori")
        splitVertButton?.image = NSImage(named: "splitVert")
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

