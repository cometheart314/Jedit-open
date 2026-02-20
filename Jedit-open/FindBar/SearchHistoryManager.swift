//
//  SearchHistoryManager.swift
//  Jedit-open
//
//  検索履歴とよく使うパターンの永続化管理。
//

import Foundation

// MARK: - Recent Search Entry (find/replace pair)

struct RecentSearchEntry: Codable, Equatable {
    var searchText: String
    var replaceText: String
}

// MARK: - Saved Pattern

struct SavedPattern: Codable, Equatable {
    var name: String
    var searchText: String
    var replaceText: String
    var caseSensitive: Bool
    var useRegex: Bool
    var wholeWord: Bool
}

// MARK: - Search History Manager

class SearchHistoryManager {

    static let shared = SearchHistoryManager()
    static let maxHistoryItems = 20

    // MARK: - Notifications

    static let historyDidChangeNotification = Notification.Name("SearchHistoryDidChange")
    static let savedPatternsDidChangeNotification = Notification.Name("SavedPatternsDidChange")

    private init() {}

    // MARK: - Search History

    var recentSearches: [String] {
        get { UserDefaults.standard.stringArray(forKey: UserDefaults.Keys.findSearchHistory) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaults.Keys.findSearchHistory) }
    }

    func addSearchTerm(_ term: String) {
        guard !term.isEmpty else { return }
        var history = recentSearches
        // 重複を削除して先頭に追加
        history.removeAll { $0 == term }
        history.insert(term, at: 0)
        // 最大数を超えたら切り捨て
        if history.count > Self.maxHistoryItems {
            history = Array(history.prefix(Self.maxHistoryItems))
        }
        recentSearches = history
        NotificationCenter.default.post(name: Self.historyDidChangeNotification, object: self)
    }

    func clearSearchHistory() {
        recentSearches = []
        NotificationCenter.default.post(name: Self.historyDidChangeNotification, object: self)
    }

    // MARK: - Replace History

    var recentReplacements: [String] {
        get { UserDefaults.standard.stringArray(forKey: UserDefaults.Keys.findReplaceHistory) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaults.Keys.findReplaceHistory) }
    }

    func addReplaceTerm(_ term: String) {
        guard !term.isEmpty else { return }
        var history = recentReplacements
        history.removeAll { $0 == term }
        history.insert(term, at: 0)
        if history.count > Self.maxHistoryItems {
            history = Array(history.prefix(Self.maxHistoryItems))
        }
        recentReplacements = history
    }

    func clearReplaceHistory() {
        recentReplacements = []
    }

    // MARK: - Recent Search Entries (find/replace pairs)

    var recentSearchEntries: [RecentSearchEntry] {
        get {
            guard let data = UserDefaults.standard.data(forKey: UserDefaults.Keys.findRecentSearchEntries) else {
                return []
            }
            return (try? JSONDecoder().decode([RecentSearchEntry].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: UserDefaults.Keys.findRecentSearchEntries)
            NotificationCenter.default.post(name: Self.historyDidChangeNotification, object: self)
        }
    }

    func addSearchEntry(searchText: String, replaceText: String) {
        guard !searchText.isEmpty else { return }
        let entry = RecentSearchEntry(searchText: searchText, replaceText: replaceText)
        var entries = recentSearchEntries
        // 同じ検索文字列のエントリを削除して先頭に追加
        entries.removeAll { $0.searchText == searchText }
        entries.insert(entry, at: 0)
        if entries.count > Self.maxHistoryItems {
            entries = Array(entries.prefix(Self.maxHistoryItems))
        }
        recentSearchEntries = entries
    }

    func removeSearchEntry(searchText: String) {
        var entries = recentSearchEntries
        entries.removeAll { $0.searchText == searchText }
        recentSearchEntries = entries
    }

    func clearSearchEntries() {
        recentSearchEntries = []
    }

    // MARK: - Saved Patterns

    var savedPatterns: [SavedPattern] {
        get {
            guard let data = UserDefaults.standard.data(forKey: UserDefaults.Keys.findSavedPatterns) else {
                return []
            }
            return (try? JSONDecoder().decode([SavedPattern].self, from: data)) ?? []
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            UserDefaults.standard.set(data, forKey: UserDefaults.Keys.findSavedPatterns)
            NotificationCenter.default.post(name: Self.savedPatternsDidChangeNotification, object: self)
        }
    }

    func savePattern(_ pattern: SavedPattern) {
        var patterns = savedPatterns
        // 同名のパターンがあれば上書き
        if let index = patterns.firstIndex(where: { $0.name == pattern.name }) {
            patterns[index] = pattern
        } else {
            patterns.append(pattern)
        }
        savedPatterns = patterns
    }

    func deletePattern(at index: Int) {
        var patterns = savedPatterns
        guard index >= 0, index < patterns.count else { return }
        patterns.remove(at: index)
        savedPatterns = patterns
    }

    func deletePattern(named name: String) {
        var patterns = savedPatterns
        patterns.removeAll { $0.name == name }
        savedPatterns = patterns
    }
}
