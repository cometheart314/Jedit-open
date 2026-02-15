//
//  InsertCommand.swift
//  Jedit-open
//
//  AppleScript insert into command handler.
//

import Cocoa

/// AppleScript "insert into" コマンドの実装
/// insert into in document 1 text "..." [at top/bottom] [at offset N]
class InsertCommand: NSScriptCommand {

    // insertion position 列挙型コード（SDEF の enumerator code に対応）
    // "JBeg" = 0x4A426567, "JEnd" = 0x4A456E64
    static let positionTop: UInt32 = 0x4A426567
    static let positionBottom: UInt32 = 0x4A456E64

    /// 挿入の本体ロジック。コマンドハンドラ・responds-to ハンドラの両方から呼ばれる。
    static func performInsert(document: Document, args: [String: Any]?) -> Any? {
        guard let insertText = args?["insertText"] as? String else { return nil }

        let textStorage = document.textStorage

        // 挿入位置の決定
        let insertionPoint: Int
        if let offset = args?["atOffset"] as? Int {
            insertionPoint = min(max(offset, 0), textStorage.length)
        } else if let positionCode = args?["atPosition"] as? UInt32 {
            if positionCode == InsertCommand.positionTop {
                insertionPoint = 0
            } else {
                insertionPoint = textStorage.length
            }
        } else {
            insertionPoint = textStorage.length
        }

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: insertionPoint, length: 0), with: insertText)
        textStorage.endEditing()

        return nil
    }

    override func performDefaultImplementation() -> Any? {
        let args = evaluatedArguments

        guard let _ = args?["insertText"] as? String else {
            scriptErrorNumber = -1708
            scriptErrorString = "Missing text to insert."
            return nil
        }

        guard let document = resolveDocument() else { return nil }

        return InsertCommand.performInsert(document: document, args: args)
    }
}
