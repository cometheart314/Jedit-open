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

        // Format > Font メニューに Character Fore Color / Back Color サブメニューを追加
        setupCharacterColorMenus()
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

    // MARK: - Character Color Menus

    /// Format > Font メニューに Character Fore Color / Back Color サブメニューを追加
    private func setupCharacterColorMenus() {
        guard let mainMenu = NSApp.mainMenu,
              let formatMenu = mainMenu.item(withTitle: "Format")?.submenu,
              let fontMenuItem = formatMenu.item(withTitle: "Font"),
              let fontSubmenu = fontMenuItem.submenu else {
            return
        }

        // セパレータを追加
        fontSubmenu.addItem(NSMenuItem.separator())

        // Character Fore Color サブメニューを追加
        let foreColorItem = NSMenuItem(
            title: NSLocalizedString("Character Fore Color", comment: "Menu item for character foreground color"),
            action: nil,
            keyEquivalent: ""
        )
        let foreColorSubmenu = NSMenu(title: "Character Fore Color")
        setupCharForeColorMenu(foreColorSubmenu)
        foreColorItem.submenu = foreColorSubmenu
        fontSubmenu.addItem(foreColorItem)

        // Character Back Color サブメニューを追加
        let backColorItem = NSMenuItem(
            title: NSLocalizedString("Character Back Color", comment: "Menu item for character background color"),
            action: nil,
            keyEquivalent: ""
        )
        let backColorSubmenu = NSMenu(title: "Character Back Color")
        setupCharBackColorMenu(backColorSubmenu)
        backColorItem.submenu = backColorSubmenu
        fontSubmenu.addItem(backColorItem)
    }

    /// Character Fore Color サブメニューを構築
    private func setupCharForeColorMenu(_ menu: NSMenu) {
        let colorNames = ["Black", "Gray", "Silver", "White", "Maroon",
                          "Red", "Purple", "Fuchsia", "Green", "Lime",
                          "Olive", "Yellow", "Navy", "Blue", "Teal", "Aqua"]

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 0),                      // Black
            (0.5, 0.5, 0.5),                // Gray
            (0.75, 0.75, 0.75),             // Silver
            (1, 1, 1),                      // White
            (0.5, 0, 0),                    // Maroon
            (1, 0, 0),                      // Red
            (0.5, 0, 0.5),                  // Purple
            (1, 0, 1),                      // Fuchsia
            (0, 0.5, 0),                    // Green
            (0, 1, 0),                      // Lime
            (0.5, 0.5, 0),                  // Olive
            (1, 1, 0),                      // Yellow
            (0, 0, 0.5),                    // Navy
            (0, 0, 1),                      // Blue
            (0, 0.5, 0.5),                  // Teal
            (0, 1, 1)                       // Aqua
        ]

        for (index, name) in colorNames.enumerated() {
            let item = NSMenuItem(
                title: NSLocalizedString(name, comment: "Color name"),
                action: #selector(ImageClickableTextView.changeForeColor(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            let (r, g, b) = colors[index]
            let color = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
            item.representedObject = color
            item.image = createColorSwatchImage(color: color)
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let otherItem = NSMenuItem(
            title: NSLocalizedString("Other Color...", comment: "Other color menu item"),
            action: #selector(ImageClickableTextView.orderFrontForeColorPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(otherItem)
    }

    /// Character Back Color サブメニューを構築
    private func setupCharBackColorMenu(_ menu: NSMenu) {
        let colorNames = ["Clear", "Salmon", "Carnation", "Lavender", "Ice", "Flora", "Banana"]

        let colors: [(CGFloat, CGFloat, CGFloat)] = [
            (1, 1, 1),                      // Clear (White)
            (1, 0.75, 0.75),                // Salmon
            (1, 0.75, 1),                   // Carnation
            (0.75, 0.75, 1),                // Lavender
            (0.75, 1, 1),                   // Ice
            (0.75, 1, 0.75),                // Flora
            (1, 1, 0.75)                    // Banana
        ]

        for (index, name) in colorNames.enumerated() {
            let item = NSMenuItem(
                title: NSLocalizedString(name, comment: "Color name"),
                action: #selector(ImageClickableTextView.changeBackColor(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            let (r, g, b) = colors[index]
            let color = NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
            // Clear の場合は nil を設定（背景色なし）
            item.representedObject = (name == "Clear") ? nil : color
            item.image = createColorSwatchImage(color: color)
            menu.addItem(item)

            // Clear の後にセパレータを追加
            if name == "Clear" {
                menu.addItem(NSMenuItem.separator())
            }
        }

        menu.addItem(NSMenuItem.separator())

        let otherItem = NSMenuItem(
            title: NSLocalizedString("Other Color...", comment: "Other color menu item"),
            action: #selector(ImageClickableTextView.orderFrontBackColorPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(otherItem)
    }

    /// カラースウォッチ画像を作成
    private func createColorSwatchImage(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 20, height: 12))
        image.lockFocus()
        color.set()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: 20, height: 12))
        NSColor.black.set()
        NSBezierPath.stroke(NSRect(x: 0, y: 0, width: 20, height: 12))
        image.unlockFocus()
        return image
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

