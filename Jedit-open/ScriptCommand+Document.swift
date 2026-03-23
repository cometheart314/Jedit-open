//
//  ScriptCommand+Document.swift
//  Jedit-open
//
//  Shared helper for AppleScript command handlers.
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

extension NSScriptCommand {

    /// evaluatedArguments から指定キーの Document を取得する。
    /// パラメータが省略された場合は AppleEvent の subject（tell ブロックの対象）から取得する。
    /// 取得できない場合は scriptError を設定して nil を返す。
    func resolveDocument(forKey key: String = "inDocument") -> Document? {
        let args = evaluatedArguments

        // 1. 明示的なパラメータから取得（search string "foo" in document 1）
        if let doc = args?[key] as? Document {
            return doc
        }
        if let specifier = args?[key] as? NSScriptObjectSpecifier,
           let doc = specifier.objectsByEvaluatingSpecifier as? Document {
            return doc
        }

        // 2. AppleEvent の subject attribute から取得（tell document 1 ... end tell）
        if args?[key] == nil, let doc = resolveDocumentFromAppleEvent() {
            return doc
        }

        scriptErrorNumber = -1728
        scriptErrorString = "Could not find the specified document."
        return nil
    }

    /// AppleEvent の subject attribute (keySubjectAttr) から Document を解決する。
    /// tell document 1 ブロック内でコマンドが実行された場合、
    /// subject attribute にドキュメントの object specifier が格納される。
    private func resolveDocumentFromAppleEvent() -> Document? {
        guard let event = appleEvent else { return nil }

        // keySubjectAttr = 'subj' (0x7375626A)
        let subjectDesc = event.attributeDescriptor(forKeyword: AEKeyword(0x7375626A))
        guard let subjectDesc = subjectDesc else { return nil }

        // null descriptor は application 自体を意味する → ドキュメントではない
        if subjectDesc.descriptorType == typeNull { return nil }

        // subject の object specifier を NSScriptObjectSpecifier に変換
        guard let specifier = NSScriptObjectSpecifier(descriptor: subjectDesc) else { return nil }

        // specifier を評価して Document オブジェクトを取得
        if let doc = specifier.objectsByEvaluatingSpecifier as? Document {
            return doc
        }

        return nil
    }
}
