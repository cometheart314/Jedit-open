//
//  FindCommand.swift
//  Jedit-open
//
//  AppleScript find command handler.
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

/// AppleScript "find" コマンドの実装
/// find string "text" in document 1 [case sensitive true] [using regular expression true] [searching all true]
class FindCommand: NSScriptCommand {

    /// {rangeLocation:N, rangeLength:N} のユーザー定義レコードを NSAppleEventDescriptor として構築
    /// usrf キーワードで文字列キーのレコードとして AppleScript に返す
    static func rangeDescriptor(location: Int, length: Int) -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        // usrf (0x75737266) = ユーザー定義フィールドリスト
        // {key1, value1, key2, value2, ...} のフラットリストとして格納
        let usrfList = NSAppleEventDescriptor.list()
        usrfList.insert(NSAppleEventDescriptor(string: "rangeLocation"), at: 1)
        usrfList.insert(NSAppleEventDescriptor(int32: Int32(location)), at: 2)
        usrfList.insert(NSAppleEventDescriptor(string: "rangeLength"), at: 3)
        usrfList.insert(NSAppleEventDescriptor(int32: Int32(length)), at: 4)
        record.setDescriptor(usrfList, forKeyword: AEKeyword(0x75737266))
        return record
    }

    /// 検索の本体ロジック。コマンドハンドラ・responds-to ハンドラの両方から呼ばれる。
    /// selectResult が true の場合、見つかった範囲を自動的に選択する（searching all でない場合のみ）
    static func performSearch(document: Document, args: [String: Any]?, selectResult: Bool = false) -> Any? {
        guard let searchText = args?["forText"] as? String else { return nil }

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
            // 見つかった範囲を自動的に選択する
            if selectResult {
                document.setSelectionRange(foundRange)
            }
            return rangeDescriptor(location: foundRange.location, length: foundRange.length)
        }
    }

    override func performDefaultImplementation() -> Any? {
        let args = evaluatedArguments

        guard let _ = args?["forText"] as? String else {
            scriptErrorNumber = -1708
            scriptErrorString = "Missing search text."
            return nil
        }

        guard let document = resolveDocument() else { return nil }

        return FindCommand.performSearch(document: document, args: args, selectResult: true)
    }
}
