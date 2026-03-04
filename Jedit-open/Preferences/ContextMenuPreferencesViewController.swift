//
//  ContextMenuPreferencesViewController.swift
//  Jedit-open
//
//  コンテキストメニューに表示する項目を選択する設定ペイン
//

import Cocoa

class ContextMenuPreferencesViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    // MARK: - Known Menu Items (static, locale-independent)

    /// 既知のコンテキストメニュー項目定義
    private struct KnownMenuItem {
        let displayTitle: String     // 設定画面に表示する名前
        let identifier: String       // 永続化に使うキー（ロケール不変）
        let isSubmenu: Bool
        /// サブメニューの場合、子項目にこのアクションが含まれていれば同一と判定
        let submenuDetectionAction: String?
    }

    /// デフォルトメニュー項目（super.menu(for:) が提供するシステム標準項目）
    private static let defaultMenuItems: [KnownMenuItem] = [
        KnownMenuItem(displayTitle: "Look Up".localized,               identifier: "action:define",                 isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Translate".localized,             identifier: "action:translate",              isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Search with Google".localized,    identifier: "action:searchWithGoogle",       isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Cut".localized,                   identifier: "cut:",                          isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Copy".localized,                  identifier: "copy:",                         isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Paste".localized,                 identifier: "paste:",                        isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Paste and Match Style".localized, identifier: "pasteAsPlainText:",             isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Font".localized,                  identifier: "submenu:font",                  isSubmenu: true,  submenuDetectionAction: "orderFrontFontPanel:"),
        KnownMenuItem(displayTitle: "Show Writing Tools".localized,    identifier: "action:showWritingTools",       isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Proofread".localized,             identifier: "action:proofread",              isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Rewrite".localized,               identifier: "action:rewrite",                isSubmenu: false, submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Spelling and Grammar".localized,  identifier: "submenu:spellingAndGrammar",    isSubmenu: true,  submenuDetectionAction: "showGuessPanel:"),
        KnownMenuItem(displayTitle: "Substitutions".localized,         identifier: "submenu:substitutions",         isSubmenu: true,  submenuDetectionAction: "toggleAutomaticQuoteSubstitution:"),
        KnownMenuItem(displayTitle: "Transformations".localized,       identifier: "submenu:transformations",       isSubmenu: true,  submenuDetectionAction: "uppercaseWord:"),
        KnownMenuItem(displayTitle: "Speech".localized,                identifier: "submenu:speech",                isSubmenu: true,  submenuDetectionAction: "startSpeaking:"),
        KnownMenuItem(displayTitle: "Share".localized,                 identifier: "submenu:share",                 isSubmenu: true,  submenuDetectionAction: nil),
        KnownMenuItem(displayTitle: "Layout Orientation".localized,    identifier: "submenu:layoutOrientation",     isSubmenu: true,  submenuDetectionAction: "changeLayoutOrientation:"),
    ]

    /// Jedit カスタムメニュー項目
    private static let jeditMenuItems: [KnownMenuItem] = [
        KnownMenuItem(displayTitle: "Styles".localized,                identifier: "submenu:styles",                isSubmenu: true,  submenuDetectionAction: "applyTextStyle:"),
        KnownMenuItem(displayTitle: "Change Image Size…".localized,    identifier: "changeImageSize:",              isSubmenu: false, submenuDetectionAction: nil),
    ]

    /// 全既知項目（identifierForMenuItem で使用）
    private static let knownMenuItems: [KnownMenuItem] = defaultMenuItems + jeditMenuItems

    /// サブメニューのタイトルから識別子へのフォールバックマップ
    /// （遅延読み込みで子項目が空の場合に使用、英語・日本語対応）
    private static let submenuTitleFallback: [String: String] = [
        // English
        "Font":                  "submenu:font",
        "Spelling and Grammar":  "submenu:spellingAndGrammar",
        "Substitutions":         "submenu:substitutions",
        "Transformations":       "submenu:transformations",
        "Speech":                "submenu:speech",
        "Share":                 "submenu:share",
        "Share…":                "submenu:share",
        "Layout Orientation":    "submenu:layoutOrientation",
        "Styles":                "submenu:styles",
        // 日本語
        "フォント":               "submenu:font",
        "スペルと文法":            "submenu:spellingAndGrammar",
        "自動置換":                "submenu:substitutions",
        "変換":                   "submenu:transformations",
        "スピーチ":               "submenu:speech",
        "共有":                   "submenu:share",
        "共有…":                  "submenu:share",
        "レイアウトの方向":         "submenu:layoutOrientation",
        "スタイル":               "submenu:styles",
    ]

    /// アクション項目のタイトルから安定した識別子へのフォールバックマップ
    /// （Apple Intelligence 等、非公開セレクタを使う項目用）
    private static let actionTitleFallback: [String: String] = [
        // English
        "Show Writing Tools":   "action:showWritingTools",
        "Proofread":            "action:proofread",
        "Rewrite":              "action:rewrite",
        // 日本語
        "作文ツールを表示":         "action:showWritingTools",
        "校正":                  "action:proofread",
        "書き直し":               "action:rewrite",
    ]

    /// 動的タイトル（選択テキストを含む等）から安定した識別子を返す
    /// 例: 'Look Up "hello"' → "action:define", '"hello"を翻訳' → "action:translate"
    private static func identifierForDynamicTitle(_ title: String) -> String? {
        // Look Up / 調べる
        if title.hasPrefix("Look Up") || title.hasSuffix("を調べる") {
            return "action:define"
        }
        // Translate / 翻訳
        if title.hasPrefix("Translate") || title.hasSuffix("を翻訳") {
            return "action:translate"
        }
        // Search With Google / Google で検索（大文字・小文字両対応）
        let lower = title.lowercased()
        if lower.hasPrefix("search with google") || (title.contains("Google") && title.contains("検索")) {
            return "action:searchWithGoogle"
        }
        // Share / 共有（サブメニュー検出が失敗した場合のフォールバック）
        if title == "Share" || title == "Share..." || title == "Share…" ||
           title == "共有" || title == "共有..." || title == "共有…" {
            return "submenu:share"
        }
        return nil
    }

    /// 実行時にメニュー項目から安定した識別子を返す（ロケール不変）
    static func identifierForMenuItem(_ item: NSMenuItem) -> String {
        // サブメニューの判定を先に行う（システムが submenuAction: を設定するため）
        if item.hasSubmenu, let submenu = item.submenu {
            // 遅延読み込みのサブメニューを強制的にポピュレート
            submenu.update()
            let childActions = Set(submenu.items.compactMap { $0.action.map(NSStringFromSelector) })
            for known in knownMenuItems where known.isSubmenu {
                if let detectionAction = known.submenuDetectionAction,
                   childActions.contains(detectionAction) {
                    return known.identifier
                }
            }
            // 子項目検出が失敗した場合、タイトルでフォールバック
            if let identifier = submenuTitleFallback[item.title] {
                return identifier
            }
        }
        // タイトルフォールバック（Apple Intelligence 等、アクションが nil や非公開セレクタの項目対策）
        if let identifier = actionTitleFallback[item.title] {
            return identifier
        }
        // 動的タイトル項目（Look Up "xxx", Translate "xxx" 等）
        if let identifier = identifierForDynamicTitle(item.title) {
            return identifier
        }
        // アクションがある項目はセレクタ名で一意に識別
        if let action = item.action {
            return NSStringFromSelector(action)
        }
        // 未知の項目はタイトルでフォールバック
        return "unknown:\(item.title)"
    }

    // MARK: - Data Model

    /// テーブル表示用のデータ
    private struct MenuItemEntry {
        let title: String
        let identifier: String
        let hasSubmenu: Bool
        var isVisible: Bool
    }

    private var defaultEntries: [MenuItemEntry] = []
    private var showDefaultMenu: Bool = true

    // MARK: - UI

    private var showDefaultCheckbox: NSButton!
    private var tableView: NSTableView!
    private var scrollView: NSScrollView!
    private var stylesCheckbox: NSButton!
    private var changeImageSizeCheckbox: NSButton!

    // MARK: - Lifecycle

    override func loadView() {
        self.view = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 390))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadEntries()
        setupUI()
    }

    // MARK: - Menu Item Loading

    /// 設定を読み込む
    private func loadEntries() {
        let defaults = UserDefaults.standard
        let hiddenActions = Set(defaults.stringArray(forKey: UserDefaults.Keys.hiddenContextMenuActions) ?? [])
        // dontShowContextMenuDefaultItems: true → デフォルトメニューを非表示
        showDefaultMenu = !defaults.bool(forKey: UserDefaults.Keys.dontShowContextMenuDefaultItems)

        defaultEntries = Self.defaultMenuItems.map { known in
            MenuItemEntry(
                title: known.displayTitle,
                identifier: known.identifier,
                hasSubmenu: known.isSubmenu,
                isVisible: !hiddenActions.contains(known.identifier)
            )
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        // マスタートグル: デフォルトメニュー項目の表示
        showDefaultCheckbox = NSButton(checkboxWithTitle: "Show Default Menu Items".localized, target: self, action: #selector(showDefaultToggled(_:)))
        showDefaultCheckbox.state = showDefaultMenu ? .on : .off
        showDefaultCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        showDefaultCheckbox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(showDefaultCheckbox)

        // デフォルトメニュー項目のテーブルビュー
        tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.rowHeight = 22
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self

        let checkColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        checkColumn.width = 24
        checkColumn.minWidth = 24
        checkColumn.maxWidth = 24
        tableView.addTableColumn(checkColumn)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        nameColumn.width = 260
        nameColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(nameColumn)

        scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .bezelBorder
        view.addSubview(scrollView)

        // Jedit メニュー項目セクション
        let jeditLabel = NSTextField(labelWithString: "Jedit Menu Items:".localized)
        jeditLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium)
        jeditLabel.textColor = .secondaryLabelColor
        jeditLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(jeditLabel)

        let hiddenActions = Set(UserDefaults.standard.stringArray(forKey: UserDefaults.Keys.hiddenContextMenuActions) ?? [])

        stylesCheckbox = NSButton(checkboxWithTitle: "Styles".localized + "  \u{25B8}", target: self, action: #selector(jeditItemToggled(_:)))
        stylesCheckbox.state = hiddenActions.contains("submenu:styles") ? .off : .on
        stylesCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        stylesCheckbox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stylesCheckbox)

        changeImageSizeCheckbox = NSButton(checkboxWithTitle: "Change Image Size…".localized, target: self, action: #selector(jeditItemToggled(_:)))
        changeImageSizeCheckbox.state = hiddenActions.contains("changeImageSize:") ? .off : .on
        changeImageSizeCheckbox.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        changeImageSizeCheckbox.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(changeImageSizeCheckbox)

        // Revert to Default ボタン
        let revertButton = NSButton(title: "Revert to Default".localized, target: self, action: #selector(revertToDefault(_:)))
        revertButton.controlSize = .regular
        revertButton.bezelStyle = .rounded
        revertButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(revertButton)

        // レイアウト（下から上へ定義）
        NSLayoutConstraint.activate([
            // マスタートグル
            showDefaultCheckbox.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            showDefaultCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            showDefaultCheckbox.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            // デフォルトメニュー項目テーブル（インデント）
            scrollView.topAnchor.constraint(equalTo: showDefaultCheckbox.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.heightAnchor.constraint(equalToConstant: 260),

            // Jedit セクション（テーブルのすぐ下に配置）
            jeditLabel.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 14),
            jeditLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),

            stylesCheckbox.topAnchor.constraint(equalTo: jeditLabel.bottomAnchor, constant: 6),
            stylesCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),

            changeImageSizeCheckbox.topAnchor.constraint(equalTo: stylesCheckbox.bottomAnchor, constant: 4),
            changeImageSizeCheckbox.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),

            // Revert ボタン（ペイン下部に配置）
            revertButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            revertButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
        ])

        updateDefaultItemsAppearance()
    }

    /// デフォルト項目テーブルの有効/無効の外観を更新
    private func updateDefaultItemsAppearance() {
        scrollView.alphaValue = showDefaultMenu ? 1.0 : 0.5
        tableView.reloadData()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        return defaultEntries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < defaultEntries.count else { return nil }
        let entry = defaultEntries[row]

        if tableColumn?.identifier.rawValue == "check" {
            let checkBox = NSButton(checkboxWithTitle: "", target: self, action: #selector(defaultItemToggled(_:)))
            checkBox.state = entry.isVisible ? .on : .off
            checkBox.tag = row
            checkBox.isEnabled = showDefaultMenu
            return checkBox
        } else {
            let cell = NSTextField(labelWithString: "")
            var title = entry.title
            if entry.hasSubmenu {
                title += "  \u{25B8}"  // ▸ サブメニュー矢印
            }
            cell.stringValue = title
            cell.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            cell.textColor = showDefaultMenu ? .labelColor : .disabledControlTextColor
            cell.lineBreakMode = .byTruncatingTail
            return cell
        }
    }

    // MARK: - Actions

    /// デフォルトメニュー全体の表示トグル
    @objc private func showDefaultToggled(_ sender: NSButton) {
        showDefaultMenu = (sender.state == .on)
        // dontShowContextMenuDefaultItems は反転ロジック
        UserDefaults.standard.set(!showDefaultMenu, forKey: UserDefaults.Keys.dontShowContextMenuDefaultItems)
        updateDefaultItemsAppearance()
    }

    /// デフォルトメニュー個別項目のトグル
    @objc private func defaultItemToggled(_ sender: NSButton) {
        let row = sender.tag
        guard row < defaultEntries.count else { return }
        defaultEntries[row].isVisible = (sender.state == .on)
        saveHiddenActions()
    }

    /// Jedit カスタム項目のトグル
    @objc private func jeditItemToggled(_ sender: NSButton) {
        saveHiddenActions()
    }

    /// 全設定をデフォルトに戻す
    @objc private func revertToDefault(_ sender: Any?) {
        // デフォルトメニューを表示
        showDefaultMenu = true
        showDefaultCheckbox.state = .on
        UserDefaults.standard.set(false, forKey: UserDefaults.Keys.dontShowContextMenuDefaultItems)

        // 全デフォルト項目を表示
        for i in defaultEntries.indices {
            defaultEntries[i].isVisible = true
        }

        // Jedit 項目も全て表示
        stylesCheckbox.state = .on
        changeImageSizeCheckbox.state = .on

        // 非表示リストをクリア
        UserDefaults.standard.set([String](), forKey: UserDefaults.Keys.hiddenContextMenuActions)
        updateDefaultItemsAppearance()
    }

    // MARK: - Persistence

    private func saveHiddenActions() {
        // デフォルト項目の非表示リスト
        var hiddenActions = defaultEntries.filter { !$0.isVisible }.map { $0.identifier }
        // Jedit 項目
        if stylesCheckbox.state == .off {
            hiddenActions.append("submenu:styles")
        }
        if changeImageSizeCheckbox.state == .off {
            hiddenActions.append("changeImageSize:")
        }
        UserDefaults.standard.set(hiddenActions, forKey: UserDefaults.Keys.hiddenContextMenuActions)
    }
}
