//
//  JeditTextView+LineCursor.swift
//  Jedit-open
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

// MARK: - Line Cursor (現在行ハイライト)

extension Notification.Name {
    /// 一般設定 > 詳細 のラインカーソルチェックボックスが切り替わったときに送信される。
    static let lineCursorPreferenceDidChange = Notification.Name("lineCursorPreferenceDidChange")
}

extension JeditTextView {

    /// UserDefaults でラインカーソルが有効か。
    private var isLineCursorEnabled: Bool {
        return UserDefaults.standard.bool(forKey: UserDefaults.Keys.lineCursorEnabled)
    }

    /// 「現在アクティブなカーソル位置」を返す。ページ表示モードでは複数の JeditTextView が
    /// 同じ layoutManager を共有しつつ独立した selectedRanges を持つため、自分の selectedRanges
    /// は古いままで「実際の挿入位置」とは異なることがある。そこでウィンドウの first responder
    /// になっている JeditTextView (= ユーザが見ているカーソル) の selectedRanges を一次ソースに使う。
    private func activeCursorRange() -> NSRange? {
        // ページ表示時の真ソース: ウィンドウの first responder textView
        if let activeTV = window?.firstResponder as? JeditTextView,
           activeTV.layoutManager === self.layoutManager {
            let ranges = activeTV.selectedRanges
            if ranges.count == 1, let r = ranges.first?.rangeValue, r.length == 0 {
                return r
            }
            return nil
        }
        // フォールバック: 連続モードや first responder が JeditTextView でないとき
        let ranges = selectedRanges
        guard ranges.count == 1, let r = ranges.first?.rangeValue, r.length == 0 else {
            return nil
        }
        return r
    }

    /// 現在の挿入ポイントが属する行フラグメントの矩形 (テキストビュー座標)。
    /// 自分の textContainer 上にカーソルがあるときだけ矩形を返し、それ以外 (他ページ等) は nil。
    private func currentLineFragmentRectInView() -> NSRect? {
        guard let range = activeCursorRange() else {
            return nil
        }
        guard let layoutManager = self.layoutManager,
              let textContainer = self.textContainer else {
            return nil
        }

        let originX = textContainerOrigin.x
        let originY = textContainerOrigin.y
        let charLen = textStorage?.length ?? 0

        // 文末 / 空ドキュメント。優先順位:
        //   1. extraLineFragmentRect (書類が改行で終わるとき) → そのコンテナの末尾余白行
        //   2. 空ドキュメント → ダミー矩形
        //   3. 改行で終わらない書類で挿入点が末尾 (=charLen) → 最後のグリフの行を採用
        if range.location >= charLen {
            let extra = layoutManager.extraLineFragmentRect
            if !extra.isEmpty,
               let extraContainer = layoutManager.extraLineFragmentTextContainer,
               extraContainer === textContainer {
                return extra.offsetBy(dx: originX, dy: originY)
            }
            if charLen == 0 {
                // 空ドキュメント: 1 行ぶんのダミー矩形。
                let fontHeight = (typingAttributes[.font] as? NSFont)?.boundingRectForFont.height
                    ?? (font?.boundingRectForFont.height ?? 16)
                return NSRect(x: originX, y: originY, width: textContainer.size.width, height: fontHeight)
            }
            // 改行で終わらない書類: 挿入点 (charLen) は最終文字と同じ行にある。
            // 最後の文字 (charLen - 1) の行フラグメントを採用する。
            let lastGlyph = layoutManager.glyphIndexForCharacter(at: charLen - 1)
            let lastGlyphContainer = layoutManager.textContainer(forGlyphAt: lastGlyph, effectiveRange: nil)
            guard lastGlyphContainer === textContainer else { return nil }
            let lastFragRect = layoutManager.lineFragmentRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            guard !lastFragRect.isEmpty else { return nil }
            return lastFragRect.offsetBy(dx: originX, dy: originY)
        }

        // 挿入点に対応するグリフを取得する。レイアウトは必要に応じて誘発されるが、
        // 通常は setSelectedRanges 直後に NSTextView 自身が caret 配置のために
        // 当該位置のレイアウトを完了させているため再 layout はほぼ走らない。
        // ページ表示モードでの addPage 配列同期の問題は addPage 側で解決済み。
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: range.location)

        // 自分の container 上のグリフでなければ描画対象外 (ページ表示時の他ページ)。
        let glyphContainer = layoutManager.textContainer(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard glyphContainer === textContainer else { return nil }

        let fragRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard !fragRect.isEmpty else { return nil }
        return fragRect.offsetBy(dx: originX, dy: originY)
    }

    /// 描画用に「ビュー全幅に伸ばしたライン矩形」を返す。
    private func fullWidthLineCursorRect() -> NSRect? {
        guard isLineCursorEnabled, let line = currentLineFragmentRectInView() else {
            return nil
        }
        return NSRect(x: bounds.minX, y: line.minY, width: bounds.width, height: line.height)
    }

    /// drawBackground(in:) からフックされる現在行ハイライト描画。
    /// JeditTextView.draw(_:) からも呼べるよう internal にしておく。
    @objc internal func drawLineCursorHighlight(in dirtyRect: NSRect) {
        guard let lineRect = fullWidthLineCursorRect() else {
            // 描画対象なし。dirtyRect が旧 highlight を完全に覆っていれば
            // super.drawBackground が既にビットマップを消去済みなので追跡をクリア。
            if let old = lineCursorLastDrawnRect, dirtyRect.contains(old) {
                lineCursorLastDrawnRect = nil
            }
            return
        }
        let drawRect = lineRect.intersection(dirtyRect)
        guard !drawRect.isEmpty else { return }

        // 挿入ポイント色を低アルファで使う (薄い帯)。
        // ライト/ダーク両方で違和感が出ないよう alpha = 0.10 を採用。
        let baseColor = self.insertionPointColor ?? NSColor.textColor
        baseColor.withAlphaComponent(0.10).setFill()
        drawRect.fill()

        // lineRect 全体が dirtyRect でカバーされた場合は「実際にビットマップに
        // 描かれている矩形」が確定するので追跡を更新する。スクロール等で
        // 部分描画になった場合は、cursor 位置が変わっていない限り
        // lineCursorLastDrawnRect は既に同じ値のはずなので、上書きしない。
        if dirtyRect.contains(lineRect) {
            lineCursorLastDrawnRect = lineRect
        }
    }

    /// 選択変更や設定変更で「直前のハイライト矩形」と「新しいハイライト矩形」の
    /// 和集合に対して再描画を予約する。
    ///
    /// 旧実装は最後に `lineCursorLastDrawnRect = newRect` で無条件に更新していたが、
    /// トラックパッドのタップ等で setSelectedRanges が一瞬 length>0 の中間状態を
    /// 経由するケースで newRect が nil になり、ビットマップ上に残っている旧
    /// highlight 矩形の追跡が失われていた。結果として後続 invalidate で旧位置の
    /// クリア命令が出ず、画面に残像が累積する。
    /// 現在は draw 側で「実際に描いた矩形」を追跡し、ここでは
    /// `setNeedsDisplay` だけ行う。
    @objc internal func invalidateLineCursorRegion() {
        let newRect = fullWidthLineCursorRect()

        var dirty = NSRect.zero
        if let old = lineCursorLastDrawnRect {
            dirty = old
        }
        if let n = newRect {
            dirty = dirty.isEmpty ? n : dirty.union(n)
        }
        if !dirty.isEmpty {
            setNeedsDisplay(dirty)
        }
    }

    /// 同ウィンドウのすべての JeditTextView で invalidateLineCursorRegion を呼ぶ。
    /// ページ表示モードで複数 textView がカーソル位置を共有するため、選択変更/responder 変化の
    /// たびにブロードキャストすることで、旧 textView のハイライトクリアと新 textView の描画を
    /// 同時に成立させる。
    @objc internal func invalidateLineCursorAcrossWindow() {
        if let wc = window?.windowController as? EditorWindowController {
            wc.invalidateAllLineCursors()
        } else {
            invalidateLineCursorRegion()
        }
    }

    // 通知購読は EditorWindowController に集約 (各 textView ごとに observer を持つと
    // init/deinit override が必要になり、そこで NSTextView 内部の初期化フローと
    // 競合するリスクがある。ページ表示モードでの printInfo 取扱とぶつかった経緯がある)。
}

// 注: 直前のライン矩形 (lineCursorLastDrawnRect) は NSRect が ObjC ブリッジ非対応
// な値型のため Associated Object に格納すると `as? NSRect` キャストが失敗する。
// JeditTextView 本体クラスの stored property として保持する。
