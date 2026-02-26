//
//  StyleManager.swift
//  Jedit-open
//
//  Created by Claude on 2026/02/26.
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// スタイルが追加・削除・変更された時に送信される通知
    static let textStylesDidChange = Notification.Name("textStylesDidChange")
}

// MARK: - StyleManager

class StyleManager {
    static let shared = StyleManager()

    private(set) var styles: [TextStyle] = []

    private init() {
        loadStyles()
    }

    // MARK: - File Path

    /// ~/Library/Application Support/Jedit-open/Styles.json
    private var stylesFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = appSupport.appendingPathComponent("Jedit-open")

        // ディレクトリが存在しなければ作成
        if !FileManager.default.fileExists(atPath: appDir.path) {
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        }

        return appDir.appendingPathComponent("Styles.json")
    }

    // MARK: - Load / Save

    func loadStyles() {
        let url = stylesFileURL

        if FileManager.default.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           let collection = try? JSONDecoder().decode(StyleCollection.self, from: data) {
            // マージ: ビルトインスタイルは常に存在、ユーザー追加スタイルを追加
            var result: [TextStyle] = []

            // ビルトインスタイルを追加（保存されたデータで上書き可能）
            for builtIn in TextStyle.builtInStyles {
                if let saved = collection.styles.first(where: { $0.id == builtIn.id }) {
                    result.append(saved)
                } else {
                    result.append(builtIn)
                }
            }

            // ユーザー追加スタイルを追加
            for style in collection.styles where !style.isBuiltIn {
                result.append(style)
            }

            styles = result
        } else {
            // 初回起動時はビルトインスタイルのみ
            styles = TextStyle.builtInStyles
        }
    }

    func saveStyles() {
        let collection = StyleCollection(styles: styles)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(collection) else { return }
        try? data.write(to: stylesFileURL, options: .atomic)
    }

    // MARK: - CRUD Operations

    func addStyle(name: String, basedOn style: TextStyle? = nil) -> TextStyle {
        var newStyle: TextStyle
        if let base = style {
            newStyle = base
            newStyle.id = UUID()
            newStyle.name = name
            newStyle.isBuiltIn = false
            newStyle.keyEquivalent = nil
        } else {
            newStyle = TextStyle(name: name)
        }
        styles.append(newStyle)
        saveStyles()
        notifyStylesDidChange()
        return newStyle
    }

    func updateStyle(_ style: TextStyle) {
        if let index = styles.firstIndex(where: { $0.id == style.id }) {
            styles[index] = style
            saveStyles()
            notifyStylesDidChange()
        }
    }

    func deleteStyle(at index: Int) {
        guard index >= 0 && index < styles.count else { return }
        let style = styles[index]

        // ビルトインスタイルは削除不可
        guard !style.isBuiltIn else { return }

        styles.remove(at: index)
        saveStyles()
        notifyStylesDidChange()
    }

    func deleteStyle(id: UUID) {
        if let index = styles.firstIndex(where: { $0.id == id }) {
            deleteStyle(at: index)
        }
    }

    func moveStyle(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < styles.count,
              destinationIndex >= 0 && destinationIndex <= styles.count,
              sourceIndex != destinationIndex else { return }

        let style = styles.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        styles.insert(style, at: adjustedDestination)
        saveStyles()
        notifyStylesDidChange()
    }

    func style(at index: Int) -> TextStyle? {
        guard index >= 0 && index < styles.count else { return nil }
        return styles[index]
    }

    func revertToDefault(at index: Int) {
        guard index >= 0 && index < styles.count else { return }
        let style = styles[index]

        // ビルトインスタイルのみリセット可能
        guard style.isBuiltIn else { return }

        if let builtIn = TextStyle.builtInStyles.first(where: { $0.id == style.id }) {
            styles[index] = builtIn
            saveStyles()
            notifyStylesDidChange()
        }
    }

    // MARK: - Notification

    private func notifyStylesDidChange() {
        NotificationCenter.default.post(name: .textStylesDidChange, object: self)
    }
}
