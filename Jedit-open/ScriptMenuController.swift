//
//  ScriptMenuController.swift
//  Jedit-open
//
//  Script メニューの構築・管理を担当
//  Application Support/<bundle-id>/Scripts/ フォルダ内のスクリプトを一覧表示・実行する
//  セキュリティスコープ付きブックマーク + NSAppleScript で実行する
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
import Compression

/// Script メニューの構築と管理を行うシングルトンクラス
class ScriptMenuController: NSObject, NSMenuDelegate {

    static let shared = ScriptMenuController()

    /// スクリプトフォルダのURL（Application Support/<bundle-id>/Scripts/）
    private var scriptsFolderURL: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "jp.co.artman21.Jedit-open"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(bundleID).appendingPathComponent("Scripts")
    }

    /// スクリプトファイルの対象拡張子（コンパイル済みスクリプトのみ）
    private let scriptExtensions: Set<String> = ["scpt", "scptd"]

    /// アプリケーションバンドルの拡張子
    private let appExtensions: Set<String> = ["app"]

    /// Script Editor のバンドルID
    private let scriptEditorBundleID = "com.apple.ScriptEditor2"

    private override init() {
        super.init()
    }

    // MARK: - Menu Setup

    /// メインメニューに Script メニューを挿入する
    /// - Returns: 作成した NSMenuItem（メインメニューに挿入済み）
    @discardableResult
    func setupMenu() -> NSMenuItem? {
        guard let mainMenu = NSApp.mainMenu else { return nil }

        // Script サブメニューを作成
        let scriptMenu = NSMenu(title: "Script")
        scriptMenu.delegate = self

        // メニューバーの項目を作成（アイコンのみ、タイトルなし）
        let scriptMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        if let image = NSImage(systemSymbolName: "applescript", accessibilityDescription: "Script") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
            scriptMenuItem.image = image.withSymbolConfiguration(config)
        }
        scriptMenuItem.submenu = scriptMenu

        // Help の左隣に挿入
        // メニュー順: Jedit(0), File(1), Edit(2), View(3), Format(4), Window, [Script], Help
        var helpMenuIndex = mainMenu.indexOfItem(withTitle: "Help")
        if helpMenuIndex < 0 {
            helpMenuIndex = mainMenu.indexOfItem(withTitle: "ヘルプ")
        }
        if helpMenuIndex >= 0 {
            mainMenu.insertItem(scriptMenuItem, at: helpMenuIndex)
        } else {
            // Help メニューが見つからない場合は末尾に挿入
            mainMenu.addItem(scriptMenuItem)
        }

        return scriptMenuItem
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    // MARK: - Menu Building

    /// メニューを再構築する
    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        // スクリプトファイルを一覧表示
        let scriptItems = buildScriptItems(for: scriptsFolderURL)
        if !scriptItems.isEmpty {
            for item in scriptItems {
                menu.addItem(item)
            }
        } else {
            let noScriptsItem = NSMenuItem(title: "No Scripts".localized, action: nil, keyEquivalent: "")
            noScriptsItem.isEnabled = false
            menu.addItem(noScriptsItem)
        }

        // セパレータ
        menu.addItem(NSMenuItem.separator())

        // Open Scripts Folder
        let openFolderItem = NSMenuItem(
            title: "Open Scripts Folder".localized,
            action: #selector(openScriptsFolder(_:)),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        // Open Script Editor
        let openEditorItem = NSMenuItem(
            title: "Open Script Editor".localized,
            action: #selector(openScriptEditor(_:)),
            keyEquivalent: ""
        )
        openEditorItem.target = self
        menu.addItem(openEditorItem)

        // Open Script Dictionaries サブメニュー
        let dictItem = NSMenuItem(
            title: "Open Script Dictionaries".localized,
            action: nil,
            keyEquivalent: ""
        )
        let dictSubmenu = NSMenu(title: "Open Script Dictionaries")
        dictSubmenu.addItem(createDictionaryMenuItem(title: "Jedit", tag: 0))
        dictSubmenu.addItem(createDictionaryMenuItem(title: "Standard Additions", tag: 1))
        dictSubmenu.addItem(createDictionaryMenuItem(title: "Finder", tag: 2))
        dictItem.submenu = dictSubmenu
        menu.addItem(dictItem)
    }

    /// 指定ディレクトリのスクリプトファイルからメニュー項目を構築
    private func buildScriptItems(for directoryURL: URL) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let fileManager = FileManager.default

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            return items
        }

        // 名前順にソート
        let sorted = contents.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for url in sorted {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let ext = url.pathExtension.lowercased()

            if isDirectory && appExtensions.contains(ext) {
                // .app バンドル: アプリケーションとして起動するメニュー項目
                let name = url.deletingPathExtension().lastPathComponent
                let menuItem = NSMenuItem(
                    title: name,
                    action: #selector(launchApp(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = url
                // アプリのアイコンを取得して表示
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)
                menuItem.image = icon
                items.append(menuItem)
            } else if isDirectory && ext != "scptd" {
                // 通常のフォルダ: サブメニューとして展開
                let folderItem = NSMenuItem(
                    title: url.lastPathComponent,
                    action: nil,
                    keyEquivalent: ""
                )
                let submenu = NSMenu(title: url.lastPathComponent)
                let subItems = buildScriptItems(for: url)
                if subItems.isEmpty {
                    let emptyItem = NSMenuItem(title: "No Scripts".localized, action: nil, keyEquivalent: "")
                    emptyItem.isEnabled = false
                    submenu.addItem(emptyItem)
                } else {
                    for subItem in subItems {
                        submenu.addItem(subItem)
                    }
                }
                folderItem.submenu = submenu
                items.append(folderItem)
            } else if scriptExtensions.contains(ext) {
                // スクリプトファイル — セキュリティスコープ付きブックマークを作成
                let name = url.deletingPathExtension().lastPathComponent
                let menuItem = NSMenuItem(
                    title: name,
                    action: #selector(runScript(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                do {
                    let bookmarkData = try url.bookmarkData(
                        options: .withSecurityScope,
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                    menuItem.representedObject = bookmarkData
                } catch {
                    #if DEBUG
                    Swift.print("buildScriptItems: failed to create bookmark for \(url.lastPathComponent): \(error)")
                    #endif
                    // ブックマーク作成に失敗した場合はURL をそのまま格納（フォールバック）
                    menuItem.representedObject = url
                }
                items.append(menuItem)
            }
        }

        return items
    }

    /// Open Script Dictionaries サブメニュー項目を作成
    private func createDictionaryMenuItem(title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(openScriptDictionary(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = tag
        return item
    }

    // MARK: - Scripts Folder Management

    /// スクリプトフォルダが空の場合にサンプルスクリプトを自動インストールする
    func installSampleScriptsIfNeeded() {
        guard isScriptsFolderEmpty() else { return }

        // Application Support はサンドボックスコンテナ内なので直接書き込み可能
        let targetURL = scriptsFolderURL
        do {
            try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
        } catch {
            #if DEBUG
            Swift.print("installSampleScriptsIfNeeded: failed to create directory: \(error)")
            #endif
            return
        }
        installSampleScripts(to: targetURL)
    }

    /// スクリプトフォルダにスクリプトファイルが存在しないかを判定
    private func isScriptsFolderEmpty() -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: scriptsFolderURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            // フォルダが存在しない場合も空とみなす
            return true
        }
        return !contents.contains {
            let ext = $0.pathExtension.lowercased()
            return scriptExtensions.contains(ext) || appExtensions.contains(ext)
        }
    }

    /// 指定されたフォルダにサンプルスクリプトを展開する
    private func installSampleScripts(to destFolderURL: URL) {
        guard let zipURL = Bundle.main.url(forResource: "JeditAppleScripts", withExtension: "zip"),
              let zipData = try? Data(contentsOf: zipURL) else { return }

        let fileManager = FileManager.default

        // 宛先フォルダが存在しない場合は作成
        if !fileManager.fileExists(atPath: destFolderURL.path) {
            try? fileManager.createDirectory(at: destFolderURL, withIntermediateDirectories: true)
        }

        let entries = parseZipEntries(from: zipData)

        for entry in entries {
            // __MACOSX や隠しファイル、.DS_Store をスキップ
            if entry.path.hasPrefix("__MACOSX/") || entry.path.contains("/.__") { continue }
            if entry.path.hasPrefix(".") || entry.path.hasSuffix(".DS_Store") { continue }

            let destURL = destFolderURL.appendingPathComponent(entry.path)

            if entry.isDirectory {
                try? fileManager.createDirectory(at: destURL, withIntermediateDirectories: true)
            } else {
                guard !fileManager.fileExists(atPath: destURL.path) else { continue }

                // 親ディレクトリを確保
                let parentDir = destURL.deletingLastPathComponent()
                if !fileManager.fileExists(atPath: parentDir.path) {
                    try? fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)
                }

                if let fileData = entry.extractedData(from: zipData) {
                    do {
                        try fileData.write(to: destURL)
                    } catch {
                        #if DEBUG
                        Swift.print("installSampleScripts: failed to write \(entry.path): \(error)")
                        #endif
                    }
                }
            }
        }
    }

    // MARK: - ZIP Parsing

    /// ZIP エントリ情報
    private struct ZipEntry {
        let path: String
        let isDirectory: Bool
        let compressionMethod: UInt16
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let dataOffset: Int  // ZIP ファイル内のデータ開始位置

        /// ZIP データからファイル内容を取得
        func extractedData(from zipData: Data) -> Data? {
            guard !isDirectory, uncompressedSize > 0 else { return nil }

            let compressedData = zipData[dataOffset..<(dataOffset + Int(compressedSize))]

            if compressionMethod == 0 {
                // Stored (無圧縮)
                return Data(compressedData)
            } else if compressionMethod == 8 {
                // Deflated
                return decompressDeflate(Data(compressedData), uncompressedSize: Int(uncompressedSize))
            }
            return nil
        }

        /// Deflate 圧縮データを解凍
        private func decompressDeflate(_ data: Data, uncompressedSize: Int) -> Data? {
            // compression_decode_buffer は raw deflate に対応
            let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: uncompressedSize)
            defer { destBuffer.deallocate() }

            let decodedSize = data.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) -> Int in
                guard let srcPointer = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    destBuffer, uncompressedSize,
                    srcPointer, data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            guard decodedSize > 0 else { return nil }
            return Data(bytes: destBuffer, count: decodedSize)
        }
    }

    /// ZIP データからエントリ一覧をパースする（Central Directory を使用）
    private func parseZipEntries(from data: Data) -> [ZipEntry] {
        let count = data.count

        // End of Central Directory Record (EOCD) を末尾から検索
        // EOCD signature = 0x06054b50
        guard let eocdOffset = findEOCDOffset(in: data) else { return [] }

        let cdOffset = Int(data.readUInt32(at: eocdOffset + 16))  // Central Directory の開始位置
        let cdEntryCount = Int(data.readUInt16(at: eocdOffset + 10))  // エントリ数

        var entries: [ZipEntry] = []
        var offset = cdOffset

        for _ in 0..<cdEntryCount {
            guard offset + 46 <= count else { break }

            // Central Directory File Header signature = 0x02014b50
            let sig = data.readUInt32(at: offset)
            guard sig == 0x02014b50 else { break }

            let compressionMethod = data.readUInt16(at: offset + 10)
            let compressedSize = data.readUInt32(at: offset + 20)
            let uncompressedSize = data.readUInt32(at: offset + 24)
            let fileNameLength = Int(data.readUInt16(at: offset + 28))
            let extraFieldLength = Int(data.readUInt16(at: offset + 30))
            let commentLength = Int(data.readUInt16(at: offset + 32))
            let localHeaderOffset = Int(data.readUInt32(at: offset + 42))

            let fileNameStart = offset + 46
            let fileNameEnd = fileNameStart + fileNameLength
            guard fileNameEnd <= count else { break }

            let fileNameData = data[fileNameStart..<fileNameEnd]
            let fileName = String(data: fileNameData, encoding: .utf8) ?? ""

            // ローカルファイルヘッダーからデータの開始位置を計算
            let localFileNameLength = Int(data.readUInt16(at: localHeaderOffset + 26))
            let localExtraFieldLength = Int(data.readUInt16(at: localHeaderOffset + 28))
            let dataOffset = localHeaderOffset + 30 + localFileNameLength + localExtraFieldLength

            let isDirectory = fileName.hasSuffix("/")

            let entry = ZipEntry(
                path: fileName,
                isDirectory: isDirectory,
                compressionMethod: compressionMethod,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                dataOffset: dataOffset
            )
            entries.append(entry)

            // 次の Central Directory エントリへ
            offset = fileNameEnd + extraFieldLength + commentLength
        }

        return entries
    }

    /// End of Central Directory Record の位置を検索
    private func findEOCDOffset(in data: Data) -> Int? {
        let count = data.count
        // EOCD は最小22バイト、末尾から検索（コメントがある場合は最大65535+22バイト後方）
        let searchStart = max(0, count - 65557)
        for i in stride(from: count - 22, through: searchStart, by: -1) {
            if data.readUInt32(at: i) == 0x06054b50 {
                return i
            }
        }
        return nil
    }

    // MARK: - Actions

    /// スクリプトを実行する（Option キー押下時はスクリプトエディタで開く）
    @objc private func runScript(_ sender: NSMenuItem) {
        // ブックマーク Data からスクリプト URL を解決
        if let bookmarkData = sender.representedObject as? Data {
            var isStale = false
            guard let secureURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else { return }

            // Option キーが押されている場合はスクリプトエディタで開く
            if NSEvent.modifierFlags.contains(.option) {
                openInScriptEditor(secureURL)
                return
            }

            executeScript(at: secureURL)
        } else if let url = sender.representedObject as? URL {
            // フォールバック: ブックマーク作成に失敗した場合の URL 直接使用
            if NSEvent.modifierFlags.contains(.option) {
                openInScriptEditor(url)
                return
            }
            executeScript(at: url)
        }
    }

    /// NSAppleScript + セキュリティスコープ付きリソースアクセスでスクリプトを実行する
    /// プライオリティインバージョンを避けるため独立スレッドで実行する
    private func executeScript(at url: URL) {
        let fileName = url.lastPathComponent
        let accessed = url.startAccessingSecurityScopedResource()

        // GCD の QoS 伝播を避けるため Thread.detachNewThread を使用
        Thread.detachNewThread { [weak self] in
            Thread.current.qualityOfService = .default
            defer {
                if accessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // コンパイル済みスクリプト (.scpt, .scptd) — NSAppleScript(contentsOf:) で実行
            var errorInfo: NSDictionary?
            guard let appleScript = NSAppleScript(contentsOf: url, error: &errorInfo) else {
                let message = errorInfo?[NSAppleScript.errorMessage] as? String ?? "Could not load script.".localized
                DispatchQueue.main.async {
                    self?.showScriptError(fileName: fileName, errorMessage: message)
                }
                return
            }
            appleScript.executeAndReturnError(&errorInfo)
            if let errorInfo = errorInfo {
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                DispatchQueue.main.async {
                    self?.showScriptError(fileName: fileName, errorMessage: message)
                }
            }
        }
    }

    /// スクリプト実行エラーを表示
    private func showScriptError(fileName: String, errorMessage: String) {
        let alert = NSAlert()
        alert.messageText = "Script Error".localized
        alert.informativeText = "\(fileName):\n\(errorMessage)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK".localized)
        alert.runModal()
    }

    /// .app バンドルをアプリケーションとして起動する（Option キー押下時は Finder で表示）
    @objc private func launchApp(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        if NSEvent.modifierFlags.contains(.option) {
            // Option キー: Finder で表示
            NSWorkspace.shared.activateFileViewerSelecting([url])
            return
        }

        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            if let error = error {
                DispatchQueue.main.async { [weak self] in
                    self?.showScriptError(
                        fileName: url.lastPathComponent,
                        errorMessage: error.localizedDescription
                    )
                }
            }
        }
    }

    /// スクリプトをスクリプトエディタで開く
    private func openInScriptEditor(_ url: URL) {
        guard let editorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scriptEditorBundleID) else { return }
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: editorURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    /// スクリプトフォルダを Finder で開く
    @objc private func openScriptsFolder(_ sender: Any?) {
        NSWorkspace.shared.open(scriptsFolderURL)
    }

    /// Script Editor を起動する
    @objc private func openScriptEditor(_ sender: Any?) {
        if let editorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scriptEditorBundleID) {
            NSWorkspace.shared.openApplication(at: editorURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// スクリプト辞書を開く
    @objc private func openScriptDictionary(_ sender: NSMenuItem) {
        let appURL: URL?

        switch sender.tag {
        case 0: // Jedit
            appURL = Bundle.main.bundleURL
        case 1: // Standard Additions
            // Standard Additions は /System/Library/ScriptingAdditions/StandardAdditions.osax
            appURL = URL(fileURLWithPath: "/System/Library/ScriptingAdditions/StandardAdditions.osax")
        case 2: // Finder
            appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.finder")
        default:
            return
        }

        guard let url = appURL,
              let editorURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: scriptEditorBundleID) else { return }

        // Script Editor でスクリプト辞書を開く
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: editorURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}

// MARK: - Data Extension for ZIP parsing

private extension Data {
    /// リトルエンディアンで UInt16 を読み取る（アライメント不要）
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        return UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    /// リトルエンディアンで UInt32 を読み取る（アライメント不要）
    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        return UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }
}
