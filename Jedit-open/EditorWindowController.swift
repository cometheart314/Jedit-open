//
//  EditorWindowController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/26.
//

import Cocoa

class EditorWindowController: NSWindowController {

    // MARK: - IBOutlets

    @IBOutlet weak var splitView: NSSplitView!
    @IBOutlet weak var scrollView2: ScalingScrollView!
    @IBOutlet weak var scrollView1: ScalingScrollView!
    
    // MARK: - Properties

    var textDocument: Document? {
        return document as? Document
    }

    private var isSplitViewCollapsed: Bool = false

    // MARK: - Window Lifecycle

    override func windowDidLoad() {
        super.windowDidLoad()

        // TextStorageを設定
        setupTextStorage()
    }

    // MARK: - Setup Methods

    func setupTextStorage() {
        guard let textDocument = self.textDocument else {
            return
        }

        setupTextViews(with: textDocument.textStorage)
    }

    func setupTextViews(with textStorage: NSTextStorage) {
        // 既存のLayoutManagerを削除
        if textStorage.layoutManagers.count > 0 {
            for lm in textStorage.layoutManagers {
                textStorage.removeLayoutManager(lm)
            }
        }

        // splitViewの表示されているサブビューの数を取得
        guard let splitView = splitView else { return }
        let visibleSubviews = splitView.subviews.filter { !$0.isHidden }
        let numberOfViews = visibleSubviews.count

        // 必要な数のLayoutManagerを作成
        var layoutManagers: [NSLayoutManager] = []
        for _ in 0..<numberOfViews {
            let layoutManager = NSLayoutManager()
            textStorage.addLayoutManager(layoutManager)
            layoutManagers.append(layoutManager)
        }

        // TextView1の設定（常に設定）
        if numberOfViews >= 1, let scrollView = scrollView1 {
            let width = scrollView.contentSize.width

            // TextContainerを作成
            let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[0]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let textView = NSTextView(frame: scrollView.bounds, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainerInset = textDocument!.containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // ScrollViewに設定
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }

        // TextView2の設定（サブビューが2つ以上の場合のみ）
        if numberOfViews >= 2, let scrollView = scrollView2 {
            let width = scrollView.contentSize.width

            // TextContainerを作成
            let textContainer = NSTextContainer(containerSize: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude))
            textContainer.widthTracksTextView = false
            textContainer.heightTracksTextView = false

            // LayoutManagerにTextContainerを追加
            let layoutManager = layoutManagers[1]
            layoutManager.addTextContainer(textContainer)

            // TextViewを作成
            let textView = NSTextView(frame: scrollView.bounds, textContainer: textContainer)
            textView.isEditable = true
            textView.isSelectable = true
            textView.allowsUndo = true
            textView.isHorizontallyResizable = false
            textView.isVerticallyResizable = true
            textView.autoresizingMask = [.width]
            textView.textContainerInset = textDocument!.containerInset
            textView.minSize = NSSize(width: 0, height: 0)
            textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

            // ScrollViewに設定
            scrollView.documentView = textView
            scrollView.hasVerticalScroller = true
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
        }
    }

    // MARK: - Zoom Actions

    @IBAction func zoomIn(_ sender: Any?) {
        scrollView1?.zoomIn()
        scrollView2?.zoomIn()
    }

    @IBAction func zoomOut(_ sender: Any?) {
        scrollView1?.zoomOut()
        scrollView2?.zoomOut()
    }

    @IBAction func resetZoom(_ sender: Any?) {
        scrollView1?.resetZoom()
        scrollView2?.resetZoom()
    }

    // MARK: - Split View Actions

    @IBAction func toggleSplitView(_ sender: Any?) {
        guard let splitView = splitView else { return }

        isSplitViewCollapsed = !isSplitViewCollapsed

        if isSplitViewCollapsed {
            // 2つ目のペインを折りたたむ
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = true
            }
        } else {
            // 2つ目のペインを展開
            if splitView.subviews.count > 1 {
                splitView.subviews[1].isHidden = false
            }
        }

        splitView.adjustSubviews()

        // splitViewの状態に合わせてtextViewsを再設定
        if let textDocument = self.textDocument {
            setupTextViews(with: textDocument.textStorage)
        }
    }
}

