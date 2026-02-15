//
//  ScriptCommand+Document.swift
//  Jedit-open
//
//  Shared helper for AppleScript command handlers.
//

import Cocoa

extension NSScriptCommand {

    /// evaluatedArguments から指定キーの Document を取得する。
    /// 取得できない場合は scriptError を設定して nil を返す。
    func resolveDocument(forKey key: String = "inDocument") -> Document? {
        let args = evaluatedArguments

        if let doc = args?[key] as? Document {
            return doc
        }
        if let specifier = args?[key] as? NSScriptObjectSpecifier,
           let doc = specifier.objectsByEvaluatingSpecifier as? Document {
            return doc
        }

        scriptErrorNumber = -1728
        scriptErrorString = "Could not find the specified document."
        return nil
    }
}
