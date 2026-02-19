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
    private var isTerminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // NSDocumentController.shared が初めてアクセスされる前にサブクラスをインスタンス化する。
        // NSDocumentController の init が自身を shared として登録する。
        _ = JeditDocumentController()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // AppleScript print コマンドの Apple Event ハンドラを登録
        // Cocoa Scripting の handlePrintScriptCommand: ルーティングが機能しないため、
        // Apple Event レベルで直接 print イベントを処理する
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handlePrintAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kCoreEventClass),
            andEventID: AEEventID(kAEPrintDocuments)
        )

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

        // Edit > Import from iPhone or iPad メニューを設定
        setupImportFromDeviceMenuItem()

        // Script メニューを設定
        ScriptMenuController.shared.setupMenu()

        // Continuity Camera用: アプリが画像を受け取れることをServicesに登録
        let imageReturnTypes = NSImage.imageTypes.map { NSPasteboard.PasteboardType($0) }
        NSApp.registerServicesMenuSendTypes([.string, .rtf, .rtfd], returnTypes: imageReturnTypes + [.tiff, .png])

        // サービスメニューの「Jedit: Open Selection」用にプロバイダを登録
        NSApp.servicesProvider = self

        // プリセット変更通知を監視
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(presetsDidChange(_:)),
            name: .documentPresetsDidChange,
            object: nil
        )

        // ドキュメントの開閉を監視して、開いているドキュメントのURLリストを随時保存
        // （強制終了やクラッシュ時にも復元できるようにするため）
        // また、Document Info パネルの内容を自動更新する
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentListDidChange(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentListDidChange(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowDidChange(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowDidChange(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(documentWindowDidChange(_:)),
            name: Document.documentTypeDidChangeNotification,
            object: nil
        )

        // 前回開いていたドキュメントを復元
        let didRestore = restoreOpenDocuments()

        // startup 処理済みフラグをセット
        hasHandledStartup = true

        // 復元ドキュメントがない場合のみ startupOption を処理
        if !didRestore {
            let startupResult = handleStartupOption()
            if startupResult == .newDocument {
                // Default プリセットで新規書類を作成
                let menuItem = NSMenuItem()
                menuItem.tag = 0
                newDocumentWithPreset(menuItem)
            } else if startupResult == .openPanel {
                // ユーザーが startupOption で Open Panel を指定した場合は
                // suppressOpenPanel を解除してから開く
                (NSDocumentController.shared as? JeditDocumentController)?.suppressOpenPanel = false
                DispatchQueue.main.async {
                    NSDocumentController.shared.openDocument(nil)
                }
            }
        }

        // 起動時の Open Panel 抑制を解除
        // macOS の State Restoration（_reopenWindowsAsNecessaryIncludingRestorableState:）が
        // 非同期の完了ハンドラ内から _doOpenUntitled → openDocument: を呼ぶため、
        // applicationDidFinishLaunching 完了後もしばらく待つ必要がある。
        // runModalOpenPanel にも抑制チェックを入れているため、二重の安全策となる。
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            (NSDocumentController.shared as? JeditDocumentController)?.suppressOpenPanel = false
        }
    }

    // MARK: - AppleScript Print Command

    /// AppleScript の print コマンドを Apple Event レベルで処理する。
    /// print document 1 [with properties {copies:2}] [print dialog true/false]
    @objc func handlePrintAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        // direct-parameter からドキュメントを解決
        let document: Document? = {
            guard let directParam = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
                return nil
            }
            // object specifier → NSScriptObjectSpecifier → evaluate
            if let specifier = NSScriptObjectSpecifier(descriptor: directParam),
               let doc = specifier.objectsByEvaluatingSpecifier as? Document {
                return doc
            }
            return nil
        }()

        // ドキュメントが解決できない場合は最前面ドキュメントにフォールバック
        guard let targetDocument = document ?? NSDocumentController.shared.documents.first as? Document else {
            return
        }

        // print dialog パラメータ（デフォルト: true）
        var showPrintDialog = true
        if let dialogDesc = event.paramDescriptor(forKeyword: AEKeyword(0x70646C67)) { // 'pdlg'
            showPrintDialog = dialogDesc.booleanValue
        }

        // print settings を取得
        // SDEF の record-type で定義されたキーワードコードと NSPrintInfo.AttributeKey の対応
        let keywordToAttributeKey: [AEKeyword: NSPrintInfo.AttributeKey] = [
            0x6C776370: .init(rawValue: "NSCopies"),           // 'lwcp' → copies
            0x6C77636C: .init(rawValue: "NSMustCollate"),      // 'lwcl' → collating
            0x6C776670: .init(rawValue: "NSFirstPage"),        // 'lwfp' → starting page
            0x6C776C70: .init(rawValue: "NSLastPage"),         // 'lwlp' → ending page
            0x6C776C61: .init(rawValue: "NSPagesAcross"),      // 'lwla' → pages across
            0x6C776C64: .init(rawValue: "NSPagesDown"),        // 'lwld' → pages down
            0x6C776568: .init(rawValue: "NSDetailedErrorReporting"), // 'lweh' → error handling
            0x6661786E: .init(rawValue: "NSFaxNumber"),        // 'faxn' → fax number
            0x74727072: .init(rawValue: "NSPrinterName"),      // 'trpr' → target printer
        ]
        var printSettings: [NSPrintInfo.AttributeKey: Any] = [:]
        if let settingsDesc = event.paramDescriptor(forKeyword: AEKeyword(0x70726474)) { // 'prdt'
            let count = settingsDesc.numberOfItems
            for i in 1...max(count, 1) {
                guard count > 0 else { break }
                let keyword = settingsDesc.keywordForDescriptor(at: i)
                guard keyword != 0, let valueDesc = settingsDesc.atIndex(i),
                      let attrKey = keywordToAttributeKey[keyword] else { continue }
                // 型に応じて値を変換
                if let intVal = valueDesc.coerce(toDescriptorType: typeSInt32) {
                    printSettings[attrKey] = Int(intVal.int32Value)
                } else if let boolVal = valueDesc.coerce(toDescriptorType: typeBoolean) {
                    printSettings[attrKey] = boolVal.booleanValue
                } else if let strVal = valueDesc.stringValue {
                    printSettings[attrKey] = strVal
                }
            }
        }

        // 印刷を実行
        targetDocument.print(withSettings: printSettings,
                            showPrintPanel: showPrintDialog,
                            delegate: nil,
                            didPrint: nil,
                            contextInfo: nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 終了処理開始：ウィンドウが閉じられてもURLリストを上書きしないようにする
        isTerminating = true

        // 終了前に現在開いているドキュメントのURLを保存
        saveOpenDocumentURLs()

        return .terminateNow
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

    /// ドキュメントの開閉時に呼ばれる（開いているドキュメントのURLリストを更新）
    @objc private func documentListDidChange(_ notification: Notification) {
        // アプリ終了処理中はスキップ（ウィンドウが順次閉じられてリストが空になるのを防ぐ）
        guard !isTerminating else { return }
        saveOpenDocumentURLs()
    }

    /// 開いているドキュメントのURLをUserDefaultsに保存
    private func saveOpenDocumentURLs() {
        let urls = NSDocumentController.shared.documents.compactMap { document -> String? in
            guard let doc = document as? Document,
                  let url = doc.fileURL else { return nil }
            // セキュリティスコープ付きブックマークデータとしてURLを保存
            do {
                let bookmarkData = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                return bookmarkData.base64EncodedString()
            } catch {
                // ブックマークが作れない場合はパスで保存
                return url.path
            }
        }
        UserDefaults.standard.set(urls, forKey: UserDefaults.Keys.openDocumentURLs)
    }

    /// 前回開いていたドキュメントを復元
    /// - Returns: 復元すべきドキュメントがあり、復元処理を行った場合 true
    @discardableResult
    private func restoreOpenDocuments() -> Bool {
        guard let savedURLs = UserDefaults.standard.stringArray(forKey: UserDefaults.Keys.openDocumentURLs),
              !savedURLs.isEmpty else {
            return false
        }

        // 保存されたURLリストをクリア（復元は一度だけ）
        UserDefaults.standard.removeObject(forKey: UserDefaults.Keys.openDocumentURLs)

        // Shiftキーが押されている場合は復元をスキップ（壊れたファイルによるフリーズ対策）
        if NSEvent.modifierFlags.contains(.shift) {
            return false
        }

        for savedURL in savedURLs {
            // まずブックマークとして復元を試みる
            if let bookmarkData = Data(base64Encoded: savedURL) {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    _ = url.startAccessingSecurityScopedResource()
                    NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
                    continue
                }
            }

            // ブックマーク復元に失敗した場合はパスとして扱う
            let url = URL(fileURLWithPath: savedURL)
            if FileManager.default.fileExists(atPath: savedURL) {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    // MARK: - Application Open Handling

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        // 起動時は常に false を返す。
        // startupOption の処理は applicationDidFinishLaunching で
        // restoreOpenDocuments() の後に行う。
        // これにより、ドキュメント復元前にダイアログが表示される問題を防ぐ。
        if !hasHandledStartup {
            return false
        }
        // 起動後は applicationShouldHandleReopen で処理するため false を返す
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 既にウィンドウが表示されている場合は何もしない
        if flag {
            return false
        }

        // ウィンドウがない場合、startupOption に従って処理
        let action = handleStartupOption()
        switch action {
        case .newDocument:
            // Default プリセットで新規書類を作成
            let menuItem = NSMenuItem()
            menuItem.tag = 0
            newDocumentWithPreset(menuItem)
            return false
        case .openPanel:
            NSDocumentController.shared.openDocument(nil)
            return false
        case .doNothing:
            return false
        }
    }

    /// startupOption の処理結果
    private enum StartupAction {
        case doNothing
        case newDocument
        case openPanel
    }

    /// startupOption に応じた処理を決定
    /// - Returns: 実行すべきアクション
    private func handleStartupOption() -> StartupAction {
        let startupOption = UserDefaults.standard.integer(forKey: UserDefaults.Keys.startupOption)
        switch startupOption {
        case 0: // Do Nothing
            return .doNothing
        case 1: // Open New Document
            return .newDocument
        case 2: // Show Open Panel
            return .openPanel
        default:
            return .doNothing
        }
    }

    // MARK: - Document Info Panel

    @IBAction func showDocumentInfo(_ sender: Any?) {
        DocumentInfoPanelController.shared.showPanel()
    }

    /// ドキュメントウィンドウがメイン/キーになった時にDocument Info パネルを更新
    @objc private func documentWindowDidChange(_ notification: Notification) {
        // 通知元ウィンドウからドキュメントを直接取得して更新
        if let window = notification.object as? NSWindow,
           !(window is NSPanel),
           let windowController = window.windowController,
           let document = windowController.document as? Document {
            DocumentInfoPanelController.shared.updateForDocument(document)
        } else {
            // documentTypeDidChangeNotification など、ウィンドウ以外からの通知
            DocumentInfoPanelController.shared.updateForCurrentDocument()
        }
    }

    /// ドキュメントウィンドウが閉じられる時にDocument Info パネルを更新
    /// ウィンドウが閉じた後に次のドキュメントを反映するため少し遅延させる
    /// 全てのドキュメントウィンドウが閉じられた場合はパネルも閉じる
    @objc private func documentWindowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            // 残りのドキュメントウィンドウがあるか確認
            let hasDocumentWindow = NSApp.orderedWindows.contains { window in
                !(window is NSPanel)
                    && window.windowController?.document is Document
                    && window != notification.object as? NSWindow
            }

            if hasDocumentWindow {
                DocumentInfoPanelController.shared.updateForCurrentDocument()
            } else {
                // 全てのドキュメントウィンドウが閉じられた
                DocumentInfoPanelController.shared.closePanel()
            }
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

    /// Preferencesウィンドウを表示し、指定されたカテゴリを選択
    func showPreferencesWindow(selectingCategory identifier: String) {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController()
        }
        preferencesWindowController?.showWindow(nil)
        preferencesWindowController?.window?.makeKeyAndOrderFront(nil)
        preferencesWindowController?.selectCategory(identifier: identifier)
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

    // MARK: - Import from iPhone or iPad

    /// Edit > Import from iPhone or iPad メニュー項目をコードから追加
    private func setupImportFromDeviceMenuItem() {
        guard let mainMenu = NSApp.mainMenu,
              let editMenu = mainMenu.item(withTitle: "Edit")?.submenu else {
            return
        }

        // Insertサブメニューの後（セパレータの前）に挿入
        // セパレータ "attach-files-sep" の位置を探す
        var insertIndex = editMenu.numberOfItems
        for i in 0..<editMenu.numberOfItems {
            let item = editMenu.items[i]
            if item.isSeparatorItem,
               i > 0,
               editMenu.items[i - 1].title == "Insert" {
                insertIndex = i
                break
            }
        }

        // Import from iPhone or iPad メニュー項目を作成
        // standardImportFromDeviceMenuItem を使用（SidecarSubmenuを含む標準メニュー項目を取得）
        let sel = NSSelectorFromString("standardImportFromDeviceMenuItem")
        if NSMenuItem.responds(to: sel),
           let result = NSMenuItem.perform(sel),
           let importItem = result.takeUnretainedValue() as? NSMenuItem {
            editMenu.insertItem(importItem, at: insertIndex)
        } else {
            // フォールバック: 手動で作成
            let importItem = NSMenuItem(title: "Import from iPhone or iPad", action: nil, keyEquivalent: "")
            importItem.identifier = NSMenuItem.importFromDeviceIdentifier
            importItem.submenu = NSMenu()
            editMenu.insertItem(importItem, at: insertIndex)
        }
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
        let colorEntries: [(String, NSColor)] = [
            ("Text Color",  .textColor),
            ("Red",         .systemRed),
            ("Orange",      .systemOrange),
            ("Yellow",      .systemYellow),
            ("Green",       .systemGreen),
            ("Mint",        .systemMint),
            ("Teal",        .systemTeal),
            ("Cyan",        .systemCyan),
            ("Blue",        .systemBlue),
            ("Indigo",      .systemIndigo),
            ("Purple",      .systemPurple),
            ("Pink",        .systemPink),
            ("Brown",       .systemBrown),
            ("Gray",        .systemGray),
        ]

        for (index, (name, color)) in colorEntries.enumerated() {
            let item = NSMenuItem(
                title: "",
                action: #selector(JeditTextView.changeForeColor(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.representedObject = color
            item.image = createColorSwatchImage(color: color)

            // attributedTitle でシステムカラーを使ってタイトルを表示
            let localizedName = NSLocalizedString(name, comment: "Color name")
            let attrTitle = NSAttributedString(
                string: localizedName,
                attributes: [.foregroundColor: color]
            )
            item.attributedTitle = attrTitle
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())

        let otherItem = NSMenuItem(
            title: NSLocalizedString("Other Color...", comment: "Other color menu item"),
            action: #selector(JeditTextView.orderFrontForeColorPanel(_:)),
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
                action: #selector(JeditTextView.changeBackColor(_:)),
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
            action: #selector(JeditTextView.orderFrontBackColorPanel(_:)),
            keyEquivalent: ""
        )
        menu.addItem(otherItem)
    }

    /// カラースウォッチ画像を作成（ダイナミックカラー対応）
    private func createColorSwatchImage(color: NSColor) -> NSImage {
        let size = NSSize(width: 20, height: 12)
        let image = NSImage(size: size, flipped: false) { rect in
            color.setFill()
            NSBezierPath.fill(rect)
            NSColor.separatorColor.setStroke()
            NSBezierPath.stroke(rect)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: - New Document Submenu

    /// File > New サブメニューを構築（カスタムプリセットを追加）
    private func setupNewDocumentSubmenu() {
        rebuildNewDocumentSubmenu()
    }

    /// プリセット変更通知を受信した時の処理
    @objc private func presetsDidChange(_ notification: Notification) {
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

        // DocumentPresetManagerからプリセットを取得
        let presets = DocumentPresetManager.shared.presets

        // ビルトイン項目（tag 0, 1, 2）の名前を更新
        let builtInCount = 3
        for index in 0..<builtInCount {
            if index < presets.count,
               let menuItem = newSubmenu.item(withTag: index) {
                menuItem.title = presets[index].name
            }
        }

        // カスタムプリセット（index 3以降）を削除して再追加
        while newSubmenu.items.count > builtInCount {
            newSubmenu.removeItem(at: builtInCount)
        }

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

        // セパレータとClipboard項目を追加
        newSubmenu.addItem(NSMenuItem.separator())
        let clipboardItem = NSMenuItem(
            title: "Clipboard",
            action: #selector(newDocumentFromClipboard(_:)),
            keyEquivalent: ""
        )
        clipboardItem.target = self
        newSubmenu.addItem(clipboardItem)
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

    // MARK: - New Document from Clipboard

    /// クリップボードにテキストや画像がペースト可能かどうかを判定
    private func clipboardHasPasteableContent() -> Bool {
        let pasteboard = NSPasteboard.general
        let types: [NSPasteboard.PasteboardType] = [.rtfd, .rtf, .tiff, .png, .string]
        return pasteboard.availableType(from: types) != nil
    }

    /// クリップボードの内容から新規書類を作成
    @IBAction func newDocumentFromClipboard(_ sender: Any?) {
        let pasteboard = NSPasteboard.general

        // RTFD（画像含むリッチテキスト）を優先チェック
        if let rtfdData = pasteboard.data(forType: .rtfd),
           let attributedString = NSAttributedString(rtfd: rtfdData, documentAttributes: nil) {
            createRichTextDocument(with: attributedString)
            return
        }

        // RTF をチェック
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            createRichTextDocument(with: attributedString)
            return
        }

        // 画像データ（TIFF/PNG）をチェック
        if let imageData = pasteboard.data(forType: .tiff) ?? pasteboard.data(forType: .png),
           let image = NSImage(data: imageData) {
            let attachment = NSTextAttachment()
            let cell = NSTextAttachmentCell(imageCell: image)
            attachment.attachmentCell = cell
            let attributedString = NSAttributedString(attachment: attachment)
            createRichTextDocument(with: attributedString)
            return
        }

        // プレーンテキストをチェック
        if let string = pasteboard.string(forType: .string) {
            createPlainTextDocument(with: string)
            return
        }
    }

    /// Rich Text の新規書類を作成してAttributedStringを設定
    private func createRichTextDocument(with attributedString: NSAttributedString) {
        do {
            guard let document = try NSDocumentController.shared.makeUntitledDocument(ofType: "public.plain-text") as? Document else { return }

            document.applyPresetData(NewDocData.richText)
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()

            // ウィンドウ表示後にコンテンツを設定
            document.textStorage.setAttributedString(attributedString)

            if let windowController = document.windowControllers.first as? EditorWindowController {
                windowController.applyWindowFrameFromPreset()
            }
        } catch {
            print("Error creating rich text document from clipboard: \(error)")
        }
    }

    /// Plain Text の新規書類を作成してテキストを設定
    private func createPlainTextDocument(with text: String) {
        do {
            guard let document = try NSDocumentController.shared.makeUntitledDocument(ofType: "public.plain-text") as? Document else { return }

            document.applyPresetData(NewDocData.plainText)
            NSDocumentController.shared.addDocument(document)
            document.makeWindowControllers()
            document.showWindows()

            // ウィンドウ表示後にコンテンツを設定
            document.textStorage.replaceCharacters(in: NSRange(location: 0, length: document.textStorage.length), with: text)

            if let windowController = document.windowControllers.first as? EditorWindowController {
                windowController.applyWindowFrameFromPreset()
            }
        } catch {
            print("Error creating plain text document from clipboard: \(error)")
        }
    }

    // MARK: - Services Menu

    /// サービスメニュー「Jedit: Open Selection」のハンドラ
    /// 他のアプリケーションの選択テキストを新規書類で開く
    @objc func openSelection(_ pasteboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        // RTFD（画像含むリッチテキスト）を優先チェック
        if let rtfdData = pasteboard.data(forType: .rtfd),
           let attributedString = NSAttributedString(rtfd: rtfdData, documentAttributes: nil) {
            createRichTextDocument(with: attributedString)
            return
        }

        // RTF をチェック
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) {
            createRichTextDocument(with: attributedString)
            return
        }

        // プレーンテキストをチェック
        if let string = pasteboard.string(forType: .string) {
            createPlainTextDocument(with: string)
            return
        }

        error.pointee = "No suitable text data found on the pasteboard." as NSString
    }

    // MARK: - NSMenuItemValidation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(newDocumentWithPreset(_:)) {
            return true
        }
        if menuItem.action == #selector(newDocumentFromClipboard(_:)) {
            return clipboardHasPasteableContent()
        }
        if menuItem.action == #selector(showDocumentInfo(_:)) {
            // パネルが表示中ならチェックマークを付ける
            menuItem.state = DocumentInfoPanelController.shared.isPanelVisible ? .on : .off
            return true
        }
        return true
    }
}

