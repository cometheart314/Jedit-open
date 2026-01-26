//
//  AppDelegate.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {

    private var preferencesWindowController: PreferencesWindowController?
    private var hasHandledStartup = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // UserDefaultsのデフォルト値を登録
        UserDefaults.registerDefaults()

        // 外観設定を適用
        let appearanceOption = UserDefaults.standard.integer(forKey: UserDefaults.Keys.appearanceOption)
        AppDelegate.applyAppearance(appearanceOption)

        // File > New サブメニューを構築
        setupNewDocumentSubmenu()

        // Format > Font メニューに Basic Font... 項目を追加
        setupBasicFontMenuItem()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // 全ての開いているドキュメントの presetData を保存
        saveAllDocumentsPresetData()
    }

    /// 全ての開いているドキュメントの presetData を拡張属性に保存
    private func saveAllDocumentsPresetData() {
        let documentController = NSDocumentController.shared
        for document in documentController.documents {
            guard let doc = document as? Document,
                  let url = doc.fileURL,
                  doc.presetData != nil else { continue }

            // ウィンドウフレームを更新
            if let windowController = doc.windowControllers.first as? EditorWindowController,
               let window = windowController.window {
                let frame = window.frame
                doc.presetData?.view.windowX = frame.origin.x
                doc.presetData?.view.windowY = frame.origin.y
                doc.presetData?.view.windowWidth = frame.size.width
                doc.presetData?.view.windowHeight = frame.size.height
            }

            // 拡張属性に保存
            doc.savePresetDataToExtendedAttribute(at: url)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Application Open Handling

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // 起動時のオプションに応じて処理
        if !hasHandledStartup {
            hasHandledStartup = true
            return handleStartupOption()
        }
        // 起動後は applicationShouldHandleReopen で処理するため false を返す
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 既にウィンドウが表示されている場合は何もしない（デフォルト動作）
        if flag {
            return true
        }

        // ウィンドウがない場合、startupOption に従って処理
        return handleStartupOption()
    }

    /// startupOption に応じた処理を実行
    /// - Returns: 新規書類を開くべきかどうか
    private func handleStartupOption() -> Bool {
        let startupOption = UserDefaults.standard.integer(forKey: UserDefaults.Keys.startupOption)
        switch startupOption {
        case 0: // Do Nothing
            return false
        case 1: // Open New Document
            return true
        case 2: // Show Open Panel
            DispatchQueue.main.async {
                NSDocumentController.shared.openDocument(nil)
            }
            return false
        default:
            return false
        }
    }

    // MARK: - Preferences

    @IBAction func showPreferences(_ sender: Any?) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(sender)
        preferencesWindowController?.window?.makeKeyAndOrderFront(sender)
    }

    // MARK: - Appearance

    /// 外観設定を適用
    static func applyAppearance(_ option: Int) {
        switch option {
        case 0: // System
            NSApp.appearance = nil
        case 1: // Light
            NSApp.appearance = NSAppearance(named: .aqua)
        case 2: // Dark
            NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
            NSApp.appearance = nil
        }
    }

    // MARK: - Basic Font Menu Item

    /// Format > Font メニューに Basic Font... 項目を追加
    private func setupBasicFontMenuItem() {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = mainMenu.item(withTitle: "Format")?.submenu,
              let fontMenuItem = formatMenu.item(withTitle: "Font"),
              let fontSubmenu = fontMenuItem.submenu else {
            return
        }

        // セパレータを追加
        fontSubmenu.addItem(NSMenuItem.separator())

        // Basic Font... メニュー項目を追加
        let basicFontItem = NSMenuItem(
            title: NSLocalizedString("Basic Font...", comment: "Menu item for Basic Font"),
            action: #selector(EditorWindowController.showBasicFont(_:)),
            keyEquivalent: ""
        )
        fontSubmenu.addItem(basicFontItem)
    }

    // MARK: - New Document Submenu

    /// File > New サブメニューを構築（カスタムプリセットを追加）
    private func setupNewDocumentSubmenu() {
        rebuildNewDocumentSubmenu()
    }

    /// File > New サブメニューを再構築（カスタムプリセットを動的に追加）
    func rebuildNewDocumentSubmenu() {
        guard let mainMenu = NSApp.mainMenu,
              let fileMenu = mainMenu.item(withTitle: "File")?.submenu,
              let newMenuItem = fileMenu.item(withTitle: "New"),
              let newSubmenu = newMenuItem.submenu else {
            return
        }

        // XIBで定義されたビルトイン項目（Default, Plain Text, Rich Text）以外を削除
        // tag 0, 1, 2 はビルトインプリセット
        let builtInCount = 3
        while newSubmenu.items.count > builtInCount {
            newSubmenu.removeItem(at: builtInCount)
        }

        // DocumentPresetManagerからカスタムプリセットを取得して追加
        let presets = DocumentPresetManager.shared.presets

        // カスタムプリセット（index 3以降）を追加
        for index in builtInCount..<presets.count {
            let preset = presets[index]
            let menuItem = NSMenuItem(
                title: preset.name,
                action: #selector(newDocumentWithPreset(_:)),
                keyEquivalent: ""
            )
            menuItem.tag = index
            menuItem.target = self
            newSubmenu.addItem(menuItem)
        }
    }

    /// プリセットを使用して新規書類を作成
    @IBAction func newDocumentWithPreset(_ sender: NSMenuItem) {
        let presetIndex = sender.tag
        guard let preset = DocumentPresetManager.shared.preset(at: presetIndex) else {
            // プリセットが見つからない場合はデフォルトの新規書類を作成
            NSDocumentController.shared.newDocument(sender)
            return
        }

        // 新規ドキュメントを作成
        do {
            let document = try NSDocumentController.shared.makeUntitledDocument(ofType: "public.plain-text") as? Document
            if let document = document {
                // プリセットデータを適用
                document.applyPresetData(preset.data)

                // ドキュメントをDocumentControllerに追加
                NSDocumentController.shared.addDocument(document)

                // ウィンドウを表示
                document.makeWindowControllers()
                document.showWindows()

                // showWindows()の後にウィンドウフレームを再設定
                // （showWindows()がウィンドウ位置を変更することがあるため）
                if let windowController = document.windowControllers.first as? EditorWindowController {
                    windowController.applyWindowFrameFromPreset()
                }
            }
        } catch {
            print("Error creating document: \(error)")
            // エラー時はデフォルトの新規書類を作成
            NSDocumentController.shared.newDocument(sender)
        }
    }

    // MARK: - NSMenuItemValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(newDocumentWithPreset(_:)) {
            return true
        }
        return true
    }
}

