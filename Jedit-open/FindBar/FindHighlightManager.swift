//
//  FindHighlightManager.swift
//  Jedit-open
//
//  検索マッチのハイライト管理。NSLayoutManager の temporary attributes を使用し、
//  テキストストレージや Undo に影響を与えない。
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

class FindHighlightManager {

    // MARK: - Colors

    static let matchHighlightColor = NSColor.systemYellow.withAlphaComponent(0.4)
    static let currentMatchHighlightColor = NSColor.systemOrange.withAlphaComponent(0.6)

    // MARK: - State

    private weak var textStorage: NSTextStorage?
    private var highlightedRanges: [NSRange] = []
    private var currentMatchIndex: Int = -1

    // MARK: - Setup

    func setTextStorage(_ textStorage: NSTextStorage?) {
        if self.textStorage !== textStorage {
            clearAllHighlights()
        }
        self.textStorage = textStorage
    }

    // MARK: - Highlight

    /// 全マッチをハイライトし、currentIndex のマッチを現在のマッチとして強調する
    func highlightMatches(_ ranges: [NSRange], currentIndex: Int) {
        clearAllHighlights()

        guard let textStorage = textStorage else { return }

        highlightedRanges = ranges
        currentMatchIndex = currentIndex

        for layoutManager in textStorage.layoutManagers {
            // 全マッチに黄色ハイライト
            for range in ranges {
                guard range.location + range.length <= textStorage.length else { continue }
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: Self.matchHighlightColor,
                    forCharacterRange: range
                )
            }

            // 現在のマッチにオレンジハイライト（上書き）
            if currentIndex >= 0, currentIndex < ranges.count {
                let currentRange = ranges[currentIndex]
                guard currentRange.location + currentRange.length <= textStorage.length else { continue }
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: Self.currentMatchHighlightColor,
                    forCharacterRange: currentRange
                )
            }
        }
    }

    /// 現在のマッチインデックスだけ更新（全体のハイライトは維持）
    func updateCurrentMatch(index: Int) {
        guard let textStorage = textStorage else { return }
        guard !highlightedRanges.isEmpty else { return }

        let oldIndex = currentMatchIndex
        currentMatchIndex = index

        for layoutManager in textStorage.layoutManagers {
            // 旧マッチを通常ハイライトに戻す
            if oldIndex >= 0, oldIndex < highlightedRanges.count {
                let oldRange = highlightedRanges[oldIndex]
                if oldRange.location + oldRange.length <= textStorage.length {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: Self.matchHighlightColor,
                        forCharacterRange: oldRange
                    )
                }
            }

            // 新マッチを現在のマッチハイライトに変更
            if index >= 0, index < highlightedRanges.count {
                let newRange = highlightedRanges[index]
                if newRange.location + newRange.length <= textStorage.length {
                    layoutManager.addTemporaryAttribute(
                        .backgroundColor,
                        value: Self.currentMatchHighlightColor,
                        forCharacterRange: newRange
                    )
                }
            }
        }
    }

    /// 全ハイライトをクリア
    func clearAllHighlights() {
        guard let textStorage = textStorage else { return }
        let length = textStorage.length
        guard length > 0 else {
            highlightedRanges = []
            currentMatchIndex = -1
            return
        }

        // ハイライト済みの範囲のみを安全に除去する
        // （全範囲一括だと layoutManager の glyph 同期前にクラッシュする場合がある）
        if !highlightedRanges.isEmpty {
            for layoutManager in textStorage.layoutManagers {
                for range in highlightedRanges {
                    if range.location < length {
                        let safeRange = NSRange(location: range.location,
                                                length: min(range.length, length - range.location))
                        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: safeRange)
                    }
                }
            }
        } else {
            // highlightedRanges が空でも念のため全範囲をクリア
            let safeRange = NSRange(location: 0, length: length)
            for layoutManager in textStorage.layoutManagers {
                layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: safeRange)
            }
        }

        highlightedRanges = []
        currentMatchIndex = -1
    }
}
