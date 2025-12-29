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
    @IBOutlet weak var scrollView1: NSScrollView!
    @IBOutlet weak var scrollView2: NSScrollView!
    @IBOutlet weak var textView1: NSTextView!
    @IBOutlet weak var textView2: NSTextView!

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
        }

        // TextView2の設定
        if let textContainer2 = textView2?.textContainer {
            layoutManager2.addTextContainer(textContainer2)
            textView2.isEditable = true
            textView2.isSelectable = true
            textView2.allowsUndo = true
        }

        // ScrollViewの設定
        scrollView1?.hasVerticalScroller = true
        scrollView1?.hasHorizontalScroller = true
        scrollView1?.autohidesScrollers = true

        scrollView2?.hasVerticalScroller = true
        scrollView2?.hasHorizontalScroller = true
        scrollView2?.autohidesScrollers = true
    }
}

