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
    @IBOutlet weak var textView1: NSTextView!
    @IBOutlet weak var textView2: NSTextView!
    @IBOutlet weak var scrollView2: ScalingScrollView!
    @IBOutlet weak var scrollView1: ScalingScrollView!
    
    // MARK: - Properties

    var textDocument: Document? {
        return document as? Document
    }

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
        // 既存のLayoutManagerを取得または新規作成
        var layoutManager1: NSLayoutManager
        var layoutManager2: NSLayoutManager

        if textStorage.layoutManagers.count > 0 {
            // 既存のLayoutManagerがある場合は削除
            for lm in textStorage.layoutManagers {
                textStorage.removeLayoutManager(lm)
            }
        }

        // 新しいLayoutManagerを作成
        layoutManager1 = NSLayoutManager()
        layoutManager2 = NSLayoutManager()

        // TextStorageにLayoutManagerを追加
        textStorage.addLayoutManager(layoutManager1)
        textStorage.addLayoutManager(layoutManager2)

        // TextView1の設定
        if let textContainer1 = textView1?.textContainer {
            layoutManager1.addTextContainer(textContainer1)
            textView1.isEditable = true
            textView1.isSelectable = true
            textView1.allowsUndo = true

            // 横幅をウィンドウに合わせる設定
            textContainer1.widthTracksTextView = false
            textContainer1.heightTracksTextView = false
            let width1 = scrollView1?.contentSize.width ?? 0
            textContainer1.containerSize = NSSize(width: width1, height: CGFloat.greatestFiniteMagnitude)

            textView1.isHorizontallyResizable = false
            textView1.isVerticallyResizable = true
            textView1.autoresizingMask = []
            textView1.textContainerInset = textDocument!.containerInset
            textView1.minSize = NSSize(width: 0, height: 0)
            textView1.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView1.frame.size.width = width1
        }

        // TextView2の設定
        if let textContainer2 = textView2?.textContainer {
            layoutManager2.addTextContainer(textContainer2)
            textView2.isEditable = true
            textView2.isSelectable = true
            textView2.allowsUndo = true

            // 横幅をウィンドウに合わせる設定
            textContainer2.widthTracksTextView = false
            textContainer2.heightTracksTextView = false
            let width2 = scrollView2?.contentSize.width ?? 0
            textContainer2.containerSize = NSSize(width: width2, height: CGFloat.greatestFiniteMagnitude)

            textView2.isHorizontallyResizable = false
            textView2.isVerticallyResizable = true
            textView2.autoresizingMask = []
            textView2.textContainerInset = textDocument!.containerInset
            textView2.minSize = NSSize(width: 0, height: 0)
            textView2.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            textView2.frame.size.width = width2
        }

        // ScrollViewの設定
        scrollView1?.hasVerticalScroller = true
        scrollView1?.hasHorizontalScroller = false
        scrollView1?.autohidesScrollers = true

        scrollView2?.hasVerticalScroller = true
        scrollView2?.hasHorizontalScroller = false
        scrollView2?.autohidesScrollers = true
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
}

