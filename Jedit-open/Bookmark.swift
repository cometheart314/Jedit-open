//
//  Bookmark.swift
//  Jedit-open
//
//  ブックマークモデルクラス。
//  階層構造のブックマークツリーにおける個々のノードを表す。
//  各ブックマークは textStorage 内のアンカー属性に対応する UUID を持つ。
//

import Cocoa

/// ブックマークモデルクラス。
/// テキスト内のアンカー属性と対応する UUID を持ち、階層構造でツリーを形成する。
class Bookmark: NSObject {

    // MARK: - Properties

    /// このブックマークの一意識別子。
    /// フォーマット: "JEDITANCHOR:<UUID>" — textStorage のアンカー属性値と一致する。
    var uuid: String

    /// アウトラインビューに表示される表示名。
    var displayName: String

    /// ソート用の読み（日本語テキストのソートに使用）。
    var yomi: String

    /// 親ブックマーク（ツリー構造での循環参照を防ぐため weak）。
    weak var parentBookmark: Bookmark?

    /// 子ブックマークの配列。ツリーの階層構造を形成する。
    var childBookmarks: [Bookmark] = []

    /// このブックマークが参照する textStorage 内の範囲。
    var range: NSRange

    // MARK: - Initialization

    init(uuid: String, displayName: String, range: NSRange) {
        self.uuid = uuid
        self.displayName = displayName
        self.yomi = ""
        self.range = range
        super.init()
    }

    /// UUID を自動生成する便利イニシャライザ。
    convenience init(displayName: String, range: NSRange) {
        let anchorUUID = "JEDITANCHOR:\(UUID().uuidString)"
        self.init(uuid: anchorUUID, displayName: displayName, range: range)
    }

    // MARK: - Tree Operations

    /// 子ブックマークを末尾に追加する。
    func addChild(_ bookmark: Bookmark) {
        bookmark.parentBookmark = self
        childBookmarks.append(bookmark)
    }

    /// 指定した兄弟の後に子ブックマークを挿入する。
    /// 兄弟が nil または見つからない場合は末尾に追加する。
    func insertChild(_ bookmark: Bookmark, after afterSibling: Bookmark?) {
        bookmark.parentBookmark = self
        if let sibling = afterSibling,
           let index = childBookmarks.firstIndex(where: { $0 === sibling }) {
            childBookmarks.insert(bookmark, at: index + 1)
        } else {
            childBookmarks.append(bookmark)
        }
    }

    /// 指定したインデックスに子ブックマークを挿入する。
    /// インデックスが範囲外の場合は末尾に追加する。
    func insertChild(_ bookmark: Bookmark, at index: Int) {
        bookmark.parentBookmark = self
        if index >= 0 && index <= childBookmarks.count {
            childBookmarks.insert(bookmark, at: index)
        } else {
            childBookmarks.append(bookmark)
        }
    }

    /// 親の childBookmarks から自分自身を削除する。
    func removeFromParent() {
        parentBookmark?.childBookmarks.removeAll(where: { $0 === self })
        parentBookmark = nil
    }

    /// このブックマークのサブツリーの最大深度を返す。
    var childDepth: Int {
        if childBookmarks.isEmpty { return 0 }
        return 1 + (childBookmarks.map { $0.childDepth }.max() ?? 0)
    }

    /// 指定されたブックマークがこのブックマークの祖先かどうかを判定する。
    func isAncestor(_ bookmark: Bookmark) -> Bool {
        var current = parentBookmark
        while let parent = current {
            if parent === bookmark { return true }
            current = parent.parentBookmark
        }
        return false
    }

    /// 子ブックマークを表示名でソートする（再帰的）。
    func sortByName() {
        childBookmarks.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        for child in childBookmarks {
            child.sortByName()
        }
    }

    /// 子ブックマークを位置でソートする（再帰的）。
    func sortByLocation() {
        childBookmarks.sort { $0.range.location < $1.range.location }
        for child in childBookmarks {
            child.sortByLocation()
        }
    }

    /// 指定した UUID を持つブックマークをこのサブツリー内から再帰的に検索する。
    func findBookmark(withUUID targetUUID: String) -> Bookmark? {
        if uuid == targetUUID { return self }
        for child in childBookmarks {
            if let found = child.findBookmark(withUUID: targetUUID) {
                return found
            }
        }
        return nil
    }
}
