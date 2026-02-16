//
//  UndoGroupCommand.swift
//  Jedit-open
//
//  AppleScript begin/end undo group command handlers.
//

import Cocoa

/// AppleScript "begin undo group" コマンドの実装
/// begin undo group in document 1
/// tell document 1 / begin undo group
class BeginUndoGroupCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        guard let document = resolveDocument() else { return nil }

        guard let textView = document.windowControllers.first
            .flatMap({ ($0 as? EditorWindowController)?.currentTextView() }) else {
            return nil
        }

        guard let undoManager = textView.undoManager else { return nil }

        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()

        return nil
    }
}

/// AppleScript "end undo group" コマンドの実装
/// end undo group in document 1
/// tell document 1 / end undo group
class EndUndoGroupCommand: NSScriptCommand {

    override func performDefaultImplementation() -> Any? {
        guard let document = resolveDocument() else { return nil }

        guard let textView = document.windowControllers.first
            .flatMap({ ($0 as? EditorWindowController)?.currentTextView() }) else {
            return nil
        }

        guard let undoManager = textView.undoManager else { return nil }

        undoManager.endUndoGrouping()
        undoManager.groupsByEvent = true

        return nil
    }
}
