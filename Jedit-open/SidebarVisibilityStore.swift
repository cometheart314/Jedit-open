//
//  SidebarVisibilityStore.swift
//  Jedit-open
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

//
//  サイドバー（SidebarPaneProvider）の表示/非表示状態を書類ごとに永続化する。
//
//  保存先: UserDefaults (キー "SidebarVisibility.v1")
//  形式:   { "<file URL>": { "<provider id>": Bool, ... }, ... }
//
//  既定値はオフ（表示しない）。エントリ数は MAX_ENTRIES でキャップする。
//  保存先 URL を持たない（未保存の）書類はメモリ上だけで状態を保持する。
//

import Foundation

enum SidebarVisibilityStore {

    private static let userDefaultsKey = "SidebarVisibility.v1"
    private static let maxEntries = 500   // LRU 風の上限

    /// 未保存書類用のメモリ上ストア（プロセス内）。
    /// キーは Document の ObjectIdentifier 文字列など、呼び出し側が一意に決める。
    private static var transientStore: [String: [String: Bool]] = [:]

    // MARK: - 読み出し

    /// 既定値オフ。エントリが無ければ false を返す。
    static func isVisible(forFileURL fileURL: URL?,
                          transientKey: String?,
                          providerIdentifier: String) -> Bool {
        let dict = readDict(fileURL: fileURL, transientKey: transientKey)
        return dict?[providerIdentifier] ?? false
    }

    // MARK: - 書き込み

    static func setVisible(_ visible: Bool,
                           forFileURL fileURL: URL?,
                           transientKey: String?,
                           providerIdentifier: String) {
        if let url = fileURL {
            var all = persistedAll()
            let key = url.absoluteString
            var entry = all[key] ?? [:]
            entry[providerIdentifier] = visible
            all[key] = entry
            // 上限超過時は古いエントリから削る（LRU 厳密ではないが、
            // UserDefaults dict は順序を保たないので安全側で先頭から削除）
            if all.count > maxEntries {
                let drop = all.count - maxEntries
                let keysToDrop = all.keys.prefix(drop)
                keysToDrop.forEach { all.removeValue(forKey: $0) }
            }
            UserDefaults.standard.set(all, forKey: userDefaultsKey)
        } else if let tkey = transientKey {
            var entry = transientStore[tkey] ?? [:]
            entry[providerIdentifier] = visible
            transientStore[tkey] = entry
        }
    }

    // MARK: - 内部

    private static func readDict(fileURL: URL?, transientKey: String?) -> [String: Bool]? {
        if let url = fileURL {
            let all = persistedAll()
            return all[url.absoluteString]
        }
        if let tkey = transientKey {
            return transientStore[tkey]
        }
        return nil
    }

    private static func persistedAll() -> [String: [String: Bool]] {
        guard let raw = UserDefaults.standard.dictionary(forKey: userDefaultsKey) else {
            return [:]
        }
        // [String: Any] → [String: [String: Bool]] に絞り込む
        var result: [String: [String: Bool]] = [:]
        for (k, v) in raw {
            if let inner = v as? [String: Bool] {
                result[k] = inner
            } else if let inner = v as? [String: NSNumber] {
                // NSNumber → Bool への寛容な読み出し
                result[k] = inner.mapValues { $0.boolValue }
            }
        }
        return result
    }
}
