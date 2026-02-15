//
//  FindCommand.swift
//  Jedit-open
//
//  AppleScript search command handler.
//

import Cocoa

/// AppleScript "search" コマンドの実装
/// search string "text" in document 1 [case sensitive true] [using regular expression true] [searching all true]
class FindCommand: NSScriptCommand {

    /// {location:N, length:N} のレコードを NSAppleEventDescriptor として構築
    private func rangeDescriptor(location: Int, length: Int) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        // SDEF の selection range record-type のプロパティコードに対応
        // "JLoc" = 0x4A4C6F63, "JLen" = 0x4A4C656E
        record.setDescriptor(NSAppleEventDescriptor(int32: Int32(location)),
                             forKeyword: AEKeyword(0x4A4C6F63))
        record.setDescriptor(NSAppleEventDescriptor(int32: Int32(length)),
                             forKeyword: AEKeyword(0x4A4C656E))
        return record
    }

    override func performDefaultImplementation() -> Any? {
        let args = evaluatedArguments

        guard let searchText = args?["forText"] as? String else {
            scriptErrorNumber = -1708
            scriptErrorString = "Missing search text."
            return nil
        }

        guard let document = resolveDocument() else { return nil }

        let caseSensitive = args?["caseSensitive"] as? Bool ?? false
        let useRegex = args?["usingRegularExpression"] as? Bool ?? false
        let searchAll = args?["searchingAll"] as? Bool ?? false

        let text = document.textStorage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        var options: NSString.CompareOptions = []
        if !caseSensitive { options.insert(.caseInsensitive) }
        if useRegex { options.insert(.regularExpression) }

        if searchAll {
            var searchRange = fullRange
            let list = NSAppleEventDescriptor.list()
            var index: Int32 = 1

            while searchRange.location < text.length {
                let foundRange = text.range(of: searchText, options: options, range: searchRange)
                if foundRange.location == NSNotFound { break }
                list.insert(rangeDescriptor(location: foundRange.location, length: foundRange.length),
                            at: Int(index))
                index += 1
                let nextStart = foundRange.location + max(foundRange.length, 1)
                if nextStart >= text.length { break }
                searchRange = NSRange(location: nextStart, length: text.length - nextStart)
            }
            return index == 1 ? nil : list
        } else {
            let foundRange = text.range(of: searchText, options: options, range: fullRange)
            if foundRange.location == NSNotFound { return nil }
            return rangeDescriptor(location: foundRange.location, length: foundRange.length)
        }
    }
}
