//
//  UndoGroupCommand.swift
//  Jedit-open
//
//  AppleScript begin/end undo group command handlers.
//

//
//  This file is part of Jedit-open.
//  Copyright (C) 2025 Satoshi Matsumoto
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program. If not, see <https://www.gnu.org/licenses/>.
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
