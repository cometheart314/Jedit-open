//
//  ScriptMenuController.swift
//  Jedit-open
//
//  Script メニューの構築・管理を担当
//  ~/Library/Application Scripts/<bundle-id>/ フォルダ内のスクリプトを一覧表示・実行する
//

import Cocoa

/// Script メニューの構築と管理を行うシングルトンクラス
class ScriptMenuController: NSObject, NSMenuDelegate {

    static let shared = ScriptMenuController()

    /// スクリプトフォルダのURL
    private var scriptsFolderURL: URL {
        let appScriptsDir: URL
        if let url = FileManager.default.urls(for: .applicationScriptsDirectory, in: .userDomainMask).first {
            appScriptsDir = url
        } else {
            // フォールバック: 手動でパスを構築
            let home = FileManager.default.homeDirectoryForCurrentUser
            let bundleID = Bundle.main.bundleIdentifier ?? "jp.co.artman21.Jedit-open"
            appScriptsDir = home.appendingPathComponent("Library/Application Scripts/\(bundleID)")
        }
        return appScriptsDir
    }

    /// スクリプトファイルの対象拡張子
    private let scriptExtensions: Set<String> = ["scpt", "applescript", "scptd"]

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
        let helpMenuIndex = mainMenu.indexOfItem(withTitle: "Help")
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

        // スクリプトフォルダを確保
        ensureScriptsFolderExists()

        // スクリプトファイルを一覧表示
        let scriptItems = buildScriptItems(for: scriptsFolderURL)
        if !scriptItems.isEmpty {
            for item in scriptItems {
                menu.addItem(item)
            }
        } else {
            let noScriptsItem = NSMenuItem(title: NSLocalizedString("No Scripts", comment: ""), action: nil, keyEquivalent: "")
            noScriptsItem.isEnabled = false
            menu.addItem(noScriptsItem)
        }

        // セパレータ
        menu.addItem(NSMenuItem.separator())

        // Open Scripts Folder
        let openFolderItem = NSMenuItem(
            title: NSLocalizedString("Open Scripts Folder", comment: "Script menu item"),
            action: #selector(openScriptsFolder(_:)),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

        // Open Script Editor
        let openEditorItem = NSMenuItem(
            title: NSLocalizedString("Open Script Editor", comment: "Script menu item"),
            action: #selector(openScriptEditor(_:)),
            keyEquivalent: ""
        )
        openEditorItem.target = self
        menu.addItem(openEditorItem)

        // Open Script Dictionaries サブメニュー
        let dictItem = NSMenuItem(
            title: NSLocalizedString("Open Script Dictionaries", comment: "Script menu item"),
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

            if isDirectory && ext != "scptd" {
                // 通常のフォルダ: サブメニューとして展開
                let folderItem = NSMenuItem(
                    title: url.lastPathComponent,
                    action: nil,
                    keyEquivalent: ""
                )
                let submenu = NSMenu(title: url.lastPathComponent)
                let subItems = buildScriptItems(for: url)
                if subItems.isEmpty {
                    let emptyItem = NSMenuItem(title: NSLocalizedString("No Scripts", comment: ""), action: nil, keyEquivalent: "")
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
                // スクリプトファイル
                let name = url.deletingPathExtension().lastPathComponent
                let menuItem = NSMenuItem(
                    title: name,
                    action: #selector(runScript(_:)),
                    keyEquivalent: ""
                )
                menuItem.target = self
                menuItem.representedObject = url
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

    /// スクリプトフォルダが存在しない場合は作成する
    private func ensureScriptsFolderExists() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: scriptsFolderURL.path) {
            try? fileManager.createDirectory(at: scriptsFolderURL, withIntermediateDirectories: true)
        }
    }

    // MARK: - Actions

    /// スクリプトを実行する（Option キー押下時はスクリプトエディタで開く）
    @objc private func runScript(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }

        // Option キーが押されている場合はスクリプトエディタで開く
        if NSEvent.modifierFlags.contains(.option) {
            openInScriptEditor(url)
            return
        }

        // NSUserAppleScriptTask でスクリプトを実行
        executeScript(at: url)
    }

    /// NSUserAppleScriptTask を使ってスクリプトを実行する
    private func executeScript(at url: URL) {
        let fileName = url.lastPathComponent

        do {
            let task = try NSUserAppleScriptTask(url: url)
            task.execute(withAppleEvent: nil) { result, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self.showScriptError(fileName: fileName, error: error)
                    }
                }
            }
        } catch {
            showScriptError(fileName: fileName, error: error)
        }
    }

    /// スクリプト実行エラーを表示
    private func showScriptError(fileName: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Script Error", comment: "Alert title")
        alert.informativeText = "\(fileName):\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
        alert.runModal()
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
        ensureScriptsFolderExists()
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
