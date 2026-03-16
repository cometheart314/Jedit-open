//
//  FindBarViewController.swift
//  Jedit-open
//
//  Xcode 風のカスタム Find Bar。検索・置換・正規表現・検索履歴・パターン保存をサポート。
//

import Cocoa

// MARK: - FindBarDelegate

protocol FindBarDelegate: AnyObject {
    func findBarCurrentTextView() -> NSTextView?
    func findBarTextStorage() -> NSTextStorage?
    func findBarAllLayoutManagers() -> [NSLayoutManager]
    func findBarDidClose()
}

// MARK: - FindBarViewController

class FindBarViewController: NSViewController, NSSearchFieldDelegate, NSTextFieldDelegate {

    // MARK: - UI Elements

    private let containerView = NSView()
    private let findRow = NSView()
    private let replaceRow = NSView()

    // Find row
    private let searchField = NSSearchField()
    private let insertPatternButton = NSButton()
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let matchCountLabel = NSTextField(labelWithString: "")
    private let caseSensitiveToggle = NSButton()
    private let regexToggle = NSButton()
    private let regexHelpButton = NSButton()
    private let wholeWordToggle = NSButton()
    private let wrapAroundToggle = NSButton()
    private let doneButton = NSButton()

    // Replace row
    private let replaceField = NSTextField()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let replaceAndFindButton = NSButton()

    // MARK: - State

    private(set) var isReplaceMode: Bool = false
    private(set) var currentResult: FindResult = .empty

    // MARK: - Dependencies

    weak var delegate: FindBarDelegate?
    private let findEngine = FindEngine()
    private let highlightManager = FindHighlightManager()
    private let historyManager = SearchHistoryManager.shared

    // MARK: - Layout

    private var barHeightConstraint: NSLayoutConstraint!
    private var replaceRowHeightConstraint: NSLayoutConstraint!
    private static let findRowHeight: CGFloat = 28
    private static let replaceRowHeight: CGFloat = 28
    private static let verticalPadding: CGFloat = 4

    // MARK: - Help Window

    private static var regexHelpPanel: NSPanel?

    // MARK: - Text Change Observation

    private var textStorageObserver: Any?

    // MARK: - Lifecycle

    override func loadView() {
        // NSVisualEffectView でダークモード対応の背景を実現
        let effectView = NSVisualEffectView()
        effectView.translatesAutoresizingMaskIntoConstraints = false
        effectView.material = .titlebar
        effectView.blendingMode = .withinWindow
        effectView.state = .followsWindowActiveState
        view = effectView

        setupFindRow()
        setupReplaceRow()
        setupLayout()
        setupSearchFieldMenu()
        loadSavedOptions()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    deinit {
        if let observer = textStorageObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Public Interface

    func setReplaceMode(_ enabled: Bool) {
        isReplaceMode = enabled
        updateReplaceRowVisibility(animated: false)
        setupSearchFieldMenu()
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
        performIncrementalSearch()
    }

    /// Help 検索用: 大文字小文字を区別せず、正規表現オフでテキストを設定して検索
    func setSearchTextCaseInsensitive(_ text: String) {
        findEngine.options.caseSensitive = false
        caseSensitiveToggle.state = .off
        updateToggleAppearance(caseSensitiveToggle)

        findEngine.options.useRegex = false
        regexToggle.state = .off
        wholeWordToggle.isEnabled = true
        updateToggleAppearance(regexToggle)

        searchField.stringValue = text
        performIncrementalSearch()
    }

    /// 現在のマッチ位置へスクロールして選択・点滅表示する
    func scrollToCurrentMatch() {
        guard !currentResult.isEmpty, let textView = delegate?.findBarCurrentTextView() else { return }
        let range = currentResult.ranges[currentResult.currentIndex]

        // テキストレイアウトを強制してスクロール位置を確定させる
        if let layoutManager = textView.layoutManager, let _ = textView.textContainer {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.ensureLayout(forGlyphRange: glyphRange)
        }

        selectAndScrollTo(range: range, in: textView)
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
        // フォーカス後にインクリメンタル検索を確実に実行
        // （既存の検索文字列がある場合にハイライトを表示するため）
        DispatchQueue.main.async { [weak self] in
            self?.updateSearchFieldAppearance()
            self?.performIncrementalSearch()
        }
    }

    func clearSearch() {
        highlightManager.clearAllHighlights()
        currentResult = .empty
        updateMatchCountLabel()

        // テキスト変更の監視を解除（検索バーを閉じた後にインクリメンタルサーチが発動するのを防止）
        if let observer = textStorageObserver {
            NotificationCenter.default.removeObserver(observer)
            textStorageObserver = nil
        }
    }

    // MARK: - Actions

    @objc func findNext(_ sender: Any? = nil) {
        guard let textView = delegate?.findBarCurrentTextView() else { return }
        let searchText = searchField.stringValue
        guard !searchText.isEmpty else { return }

        addToRecentSearches(searchText)
        findEngine.searchText = searchText

        let startLocation = NSMaxRange(textView.selectedRange())
        if let range = findEngine.findNext(in: textView.string, from: startLocation) {
            selectAndScrollTo(range: range, in: textView)
            updateCurrentMatchIndex(for: range)
        } else {
            NSSound.beep()
            updateMatchCountLabel()
        }
    }

    @objc func findPrevious(_ sender: Any? = nil) {
        guard let textView = delegate?.findBarCurrentTextView() else { return }
        let searchText = searchField.stringValue
        guard !searchText.isEmpty else { return }

        addToRecentSearches(searchText)
        findEngine.searchText = searchText

        let startLocation = textView.selectedRange().location
        if let range = findEngine.findPrevious(in: textView.string, from: startLocation) {
            selectAndScrollTo(range: range, in: textView)
            updateCurrentMatchIndex(for: range)
        } else {
            NSSound.beep()
            updateMatchCountLabel()
        }
    }

    @objc private func replaceOne(_ sender: Any?) {
        guard let textView = delegate?.findBarCurrentTextView() else { return }
        let selectedRange = textView.selectedRange()

        // 選択範囲が現在のマッチと一致する場合のみ置換
        if let currentRange = currentResult.currentRange,
           NSEqualRanges(selectedRange, currentRange) {
            findEngine.replaceText = replaceField.stringValue
            historyManager.addReplaceTerm(replaceField.stringValue)

            if findEngine.replaceMatch(in: textView, at: selectedRange) != nil {
                // 置換後に次のマッチへ移動
                performIncrementalSearch()
                findNext()
            }
        } else {
            // 現在のマッチが選択されていなければ、まず次を検索
            findNext()
        }
    }

    @objc private func replaceAll(_ sender: Any?) {
        guard let textView = delegate?.findBarCurrentTextView() else { return }
        let searchText = searchField.stringValue
        guard !searchText.isEmpty else { return }

        findEngine.searchText = searchText
        findEngine.replaceText = replaceField.stringValue
        addToRecentSearches(searchText)
        historyManager.addReplaceTerm(replaceField.stringValue)

        let count = findEngine.replaceAll(in: textView)
        performIncrementalSearch()

        // 置換結果を一時的にラベルに表示
        if count > 0 {
            matchCountLabel.stringValue = "\(count) replaced"
        }
    }

    @objc private func replaceAndFind(_ sender: Any?) {
        replaceOne(sender)
    }

    @objc private func toggleCaseSensitive(_ sender: NSButton) {
        findEngine.options.caseSensitive = (sender.state == .on)
        UserDefaults.standard.set(sender.state == .on, forKey: UserDefaults.Keys.findCaseSensitive)
        updateToggleAppearance(sender)
        performIncrementalSearch()
    }

    @objc private func toggleRegex(_ sender: NSButton) {
        findEngine.options.useRegex = (sender.state == .on)
        UserDefaults.standard.set(sender.state == .on, forKey: UserDefaults.Keys.findUseRegex)
        updateToggleAppearance(sender)

        // 正規表現 ON → Whole Word を無効化
        if sender.state == .on {
            findEngine.options.wholeWord = false
            wholeWordToggle.state = .off
            wholeWordToggle.isEnabled = false
            updateToggleAppearance(wholeWordToggle)
        } else {
            wholeWordToggle.isEnabled = true
        }

        updateSearchFieldAppearance()
        performIncrementalSearch()
    }

    @objc private func toggleWholeWord(_ sender: NSButton) {
        findEngine.options.wholeWord = (sender.state == .on)
        UserDefaults.standard.set(sender.state == .on, forKey: UserDefaults.Keys.findWholeWord)
        updateToggleAppearance(sender)
        performIncrementalSearch()
    }

    @objc private func toggleWrapAround(_ sender: NSButton) {
        findEngine.options.wrapAround = (sender.state == .on)
        UserDefaults.standard.set(sender.state == .on, forKey: UserDefaults.Keys.findWrapAround)
        updateToggleAppearance(sender)
    }

    /// NSSearchField のアクション（Recent Searches メニューから選択された時に呼ばれる）
    @objc private func searchFieldAction(_ sender: NSSearchField) {
        updateSearchFieldAppearance()
        performIncrementalSearch()
    }

    @objc private func closeFindBar(_ sender: Any?) {
        clearSearch()
        delegate?.findBarDidClose()
    }

    @objc private func showInsertPatternMenu(_ sender: NSButton) {
        let menu = NSMenu()

        // --- 特殊文字セクション ---
        let specialHeader = NSMenuItem(title: "Special Characters".localized, action: nil, keyEquivalent: "")
        specialHeader.isEnabled = false
        menu.addItem(specialHeader)

        let specialCharacters: [(symbol: String, title: String, insertion: String)] = [
            ("▸", "Tab", "\\t"),
            ("↩", "Return", "\\n"),
            ("↓", "Line Break", "\\x{2028}"),
            ("╍", "Page Break", "\\f"),
        ]

        for item in specialCharacters {
            let menuItem = NSMenuItem()
            menuItem.attributedTitle = makePatternMenuTitle(symbol: item.symbol, title: item.title)
            menuItem.representedObject = item.insertion
            menuItem.target = self
            menuItem.action = #selector(insertRegexPatternFromMenu(_:))
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        // --- 正規表現パターンセクション ---
        let regexHeader = NSMenuItem(title: "Regex Patterns".localized, action: nil, keyEquivalent: "")
        regexHeader.isEnabled = false
        menu.addItem(regexHeader)

        let regexPatterns: [(symbol: String, title: String, insertion: String)] = [
            ("Any", "Any Characters", "."),
            ("Word", "Any Word Characters", "\\w"),
            ("Break", "Word Break", "\\b"),
            ("", "White Space", "\\s"),
            ("#", "Digits", "\\d"),
        ]

        for item in regexPatterns {
            let menuItem = NSMenuItem()
            menuItem.attributedTitle = makePatternMenuTitle(symbol: item.symbol, title: item.title)
            menuItem.representedObject = item.insertion
            menuItem.target = self
            menuItem.action = #selector(insertRegexPatternFromMenu(_:))
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        // --- 定型パターンセクション ---
        let templatePatterns: [(symbol: String, title: String, insertion: String)] = [
            ("Email Address", "Email Address", "[a-zA-Z0-9._%+\\-]+@[a-zA-Z0-9.\\-]+\\.[a-zA-Z]{2,}"),
            ("URL", "Web Address", "https?://[\\w\\-]+(\\.[\\w\\-]+)+[\\w.,@?^=%&:/~+#\\-]*"),
            ("Phone #", "Phone Number", "[\\d\\-().+\\s]{7,}"),
        ]

        for item in templatePatterns {
            let menuItem = NSMenuItem()
            menuItem.attributedTitle = makePatternMenuTitle(symbol: item.symbol, title: item.title)
            menuItem.representedObject = item.insertion
            menuItem.target = self
            menuItem.action = #selector(insertRegexPatternFromMenu(_:))
            menu.addItem(menuItem)
        }

        // ボタンの下にメニューを表示
        let point = NSPoint(x: 0, y: sender.bounds.maxY + 2)
        menu.popUp(positioning: nil, at: point, in: sender)
    }

    /// メニュー項目のシンボル + タイトルの属性付き文字列を生成
    private func makePatternMenuTitle(symbol: String, title: String) -> NSAttributedString {
        let result = NSMutableAttributedString()

        // シンボル部分（固定幅フォント、グレー）
        let symbolAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let symbolStr = NSAttributedString(string: symbol.padding(toLength: max(symbol.count, 8), withPad: " ", startingAt: 0), attributes: symbolAttrs)
        result.append(symbolStr)

        // スペース
        result.append(NSAttributedString(string: "  "))

        // タイトル部分
        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuFont(ofSize: 13),
        ]
        result.append(NSAttributedString(string: title, attributes: titleAttrs))

        return result
    }

    @objc private func insertPatternFromMenu(_ sender: NSMenuItem) {
        guard let pattern = sender.representedObject as? String else { return }

        // 現在フォーカスのあるフィールドに挿入
        let targetField: NSControl
        if let firstResponder = view.window?.firstResponder as? NSTextView,
           firstResponder == replaceField.currentEditor() {
            targetField = replaceField
        } else {
            targetField = searchField
        }

        // フィールドエディタを取得して挿入
        if let fieldEditor = targetField.currentEditor() as? NSTextView {
            let selectedRange = fieldEditor.selectedRange()
            fieldEditor.insertText(pattern, replacementRange: selectedRange)
        } else {
            // フィールドエディタがない場合は末尾に追加
            if targetField === searchField {
                searchField.stringValue += pattern
            } else {
                replaceField.stringValue += pattern
            }
        }

        // 検索フィールドの場合はインクリメンタル検索を実行
        if targetField === searchField {
            updateSearchFieldAppearance()
            performIncrementalSearch()
        }
    }

    @objc private func insertRegexPatternFromMenu(_ sender: NSMenuItem) {
        // 正規表現オプションを自動的にオンにする
        if !findEngine.options.useRegex {
            findEngine.options.useRegex = true
            UserDefaults.standard.set(true, forKey: UserDefaults.Keys.findUseRegex)
            regexToggle.state = .on
            updateToggleAppearance(regexToggle)

            // Whole Word を無効化
            findEngine.options.wholeWord = false
            UserDefaults.standard.set(false, forKey: UserDefaults.Keys.findWholeWord)
            wholeWordToggle.state = .off
            wholeWordToggle.isEnabled = false
            updateToggleAppearance(wholeWordToggle)
        }

        // パターンを挿入（共通処理を呼び出し）
        insertPatternFromMenu(sender)
    }

    @objc private func showRegexHelp(_ sender: Any?) {
        // 既にヘルプウィンドウが開いていたら前面に持ってくる
        if let existingPanel = Self.regexHelpPanel, existingPanel.isVisible {
            existingPanel.makeKeyAndOrderFront(nil)
            return
        }

        guard let helpURL = Bundle.main.url(forResource: "RegExpHelp", withExtension: "rtf") else {
            NSSound.beep()
            return
        }

        // RTF ファイルを読み込み
        guard let rtfData = try? Data(contentsOf: helpURL),
              let attributedString = NSAttributedString(rtf: rtfData, documentAttributes: nil) else {
            NSSound.beep()
            return
        }

        // ヘルプパネルを作成（フローティング、閉じるボタンのみ）
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: true
        )
        panel.title = "Regular Expression Help".localized
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 360, height: 300)

        // スクロールビュー + テキストビュー
        let scrollView = NSScrollView(frame: panel.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false

        let textView = NSTextView(frame: scrollView.contentView.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textStorage?.setAttributedString(attributedString)

        scrollView.documentView = textView
        panel.contentView = scrollView

        // ウィンドウを画面中央に表示
        panel.center()
        panel.makeKeyAndOrderFront(nil)

        Self.regexHelpPanel = panel
    }

    @objc private func toggleReplaceMode(_ sender: Any?) {
        let savedSearchText = searchField.stringValue
        isReplaceMode.toggle()
        updateReplaceRowVisibility(animated: true)
        setupSearchFieldMenu()

        // NSSearchField のメニューから呼ばれた場合、stringValue が上書きされるため復元
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.searchField.stringValue != savedSearchText {
                self.searchField.stringValue = savedSearchText
                self.updateSearchFieldAppearance()
                self.performIncrementalSearch()
            }
        }
    }

    // MARK: - Save / Load Patterns

    @objc private func saveCurrentPattern(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Save Search Pattern".localized
        alert.informativeText = "Enter a name for this pattern:".localized
        alert.addButton(withTitle: "Save".localized)
        alert.addButton(withTitle: "Cancel".localized)

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        nameField.placeholderString = "Pattern name".localized
        alert.accessoryView = nameField

        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn,
                  let self = self else { return }
            let name = nameField.stringValue
            guard !name.isEmpty else { return }

            let pattern = SavedPattern(
                name: name,
                searchText: self.searchField.stringValue,
                replaceText: self.replaceField.stringValue,
                caseSensitive: self.findEngine.options.caseSensitive,
                useRegex: self.findEngine.options.useRegex,
                wholeWord: self.findEngine.options.wholeWord
            )
            self.historyManager.savePattern(pattern)
            self.setupSearchFieldMenu()
        }
    }

    @objc private func loadSavedPattern(_ sender: NSMenuItem) {
        guard let pattern = sender.representedObject as? SavedPattern else { return }

        // Option キーが押されている場合は削除
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            historyManager.deletePattern(named: pattern.name)
            setupSearchFieldMenu()
            return
        }

        // Replace 文字列の有無に応じて Replace 行を開閉
        let shouldShowReplace = !pattern.replaceText.isEmpty
        if isReplaceMode != shouldShowReplace {
            isReplaceMode = shouldShowReplace
            updateReplaceRowVisibility(animated: true)
            setupSearchFieldMenu()
        }

        findEngine.options.caseSensitive = pattern.caseSensitive
        findEngine.options.useRegex = pattern.useRegex
        findEngine.options.wholeWord = pattern.useRegex ? false : pattern.wholeWord

        caseSensitiveToggle.state = findEngine.options.caseSensitive ? .on : .off
        regexToggle.state = findEngine.options.useRegex ? .on : .off
        wholeWordToggle.state = findEngine.options.wholeWord ? .on : .off
        wholeWordToggle.isEnabled = !findEngine.options.useRegex

        updateToggleAppearance(caseSensitiveToggle)
        updateToggleAppearance(regexToggle)
        updateToggleAppearance(wholeWordToggle)

        // NSSearchField がメニュー選択後に stringValue を上書きするため、
        // 次のランループで値を再設定する
        let searchText = pattern.searchText
        let replaceText = pattern.replaceText
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.searchField.stringValue = searchText
            self.replaceField.stringValue = replaceText
            self.updateSearchFieldAppearance()
            self.performIncrementalSearch()
        }
    }

    @objc private func loadRecentSearchEntry(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? RecentSearchEntry else { return }

        // Option キーが押されている場合は削除
        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            historyManager.removeSearchEntry(searchText: entry.searchText)
            setupSearchFieldMenu()
            return
        }

        let searchText = entry.searchText
        let replaceText = entry.replaceText

        // Replace 文字列の有無に応じて Replace 行を開閉
        let shouldShowReplace = !replaceText.isEmpty
        if isReplaceMode != shouldShowReplace {
            isReplaceMode = shouldShowReplace
            updateReplaceRowVisibility(animated: true)
            setupSearchFieldMenu()
        }

        // NSSearchField がメニュー選択後に stringValue を上書きするため、
        // 次のランループで値を再設定する
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.searchField.stringValue = searchText
            self.replaceField.stringValue = replaceText
            self.updateSearchFieldAppearance()
            self.performIncrementalSearch()
        }
    }

    @objc private func clearRecentSearchEntries(_ sender: Any?) {
        let savedSearchText = searchField.stringValue
        historyManager.clearSearchEntries()
        historyManager.clearSearchHistory()
        historyManager.clearReplaceHistory()
        searchField.recentSearches = []
        setupSearchFieldMenu()

        // NSSearchField のメニューから呼ばれた場合、stringValue が上書きされるため復元
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.searchField.stringValue != savedSearchText {
                self.searchField.stringValue = savedSearchText
                self.performIncrementalSearch()
            }
        }
    }

    @objc private func deleteSavedPattern(_ sender: NSMenuItem) {
        let savedSearchText = searchField.stringValue
        guard let name = sender.representedObject as? String else { return }
        historyManager.deletePattern(named: name)
        setupSearchFieldMenu()

        // NSSearchField のメニューから呼ばれた場合、stringValue が上書きされるため復元
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if self.searchField.stringValue != savedSearchText {
                self.searchField.stringValue = savedSearchText
                self.performIncrementalSearch()
            }
        }
    }

    // MARK: - NSSearchFieldDelegate / NSTextFieldDelegate

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSControl else { return }

        if field === searchField {
            updateSearchFieldAppearance()
            performIncrementalSearch()
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSControl else { return }

        if field === searchField {
            let text = searchField.stringValue
            if !text.isEmpty {
                addToRecentSearches(text)
            }
        } else if field === replaceField {
            let text = replaceField.stringValue
            if !text.isEmpty {
                historyManager.addReplaceTerm(text)
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            if control === searchField {
                // Enter → Find Next, Shift+Enter → Find Previous
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    findPrevious()
                } else {
                    findNext()
                }
                return true
            } else if control === replaceField {
                replaceAndFind(nil)
                return true
            }
        }

        if commandSelector == #selector(cancelOperation(_:)) {
            closeFindBar(nil)
            return true
        }

        if commandSelector == #selector(insertTab(_:)) {
            if control === searchField && isReplaceMode {
                view.window?.makeFirstResponder(replaceField)
                return true
            }
        }

        if commandSelector == #selector(insertBacktab(_:)) {
            if control === replaceField {
                view.window?.makeFirstResponder(searchField)
                return true
            }
        }

        return false
    }

    // MARK: - Text Storage Observation

    func observeTextStorage(_ textStorage: NSTextStorage?) {
        if let observer = textStorageObserver {
            NotificationCenter.default.removeObserver(observer)
            textStorageObserver = nil
        }

        highlightManager.setTextStorage(textStorage)

        guard let textStorage = textStorage else { return }

        textStorageObserver = NotificationCenter.default.addObserver(
            forName: NSTextStorage.didProcessEditingNotification,
            object: textStorage,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let ts = notification.object as? NSTextStorage,
                  ts.editedMask.contains(.editedCharacters) else { return }
            // テキスト変更時にハイライトを再計算
            // didProcessEditing 通知内では layoutManager の glyph ストレージが
            // まだ同期されていないため、次のランループで実行する
            DispatchQueue.main.async { [weak self] in
                self?.performIncrementalSearch()
            }
        }
    }

    // MARK: - Private: Recent Searches

    /// SearchHistoryManager に find/replace ペアを登録し、メニューを更新
    private func addToRecentSearches(_ term: String) {
        guard !term.isEmpty else { return }
        let replaceText = replaceField.stringValue
        historyManager.addSearchEntry(searchText: term, replaceText: replaceText)
        historyManager.addSearchTerm(term)
        if !replaceText.isEmpty {
            historyManager.addReplaceTerm(replaceText)
        }
        setupSearchFieldMenu()
    }

    // MARK: - Private: Incremental Search

    private func performIncrementalSearch() {
        let searchText = searchField.stringValue
        findEngine.searchText = searchText

        guard !searchText.isEmpty else {
            highlightManager.clearAllHighlights()
            currentResult = .empty
            updateMatchCountLabel()
            return
        }

        // 正規表現バリデーション
        if findEngine.options.useRegex && !findEngine.validateRegex() {
            highlightManager.clearAllHighlights()
            currentResult = .empty
            matchCountLabel.stringValue = "Invalid regex".localized
            matchCountLabel.textColor = .systemRed
            return
        }

        guard let textView = delegate?.findBarCurrentTextView() else { return }

        let matches = findEngine.findAllMatches(in: textView.string)

        if matches.isEmpty {
            highlightManager.clearAllHighlights()
            currentResult = FindResult(ranges: [], currentIndex: -1)
            updateMatchCountLabel()

            // 赤背景でマッチなし表示
            searchField.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
            return
        }

        searchField.layer?.backgroundColor = nil

        // 現在のカーソル位置に最も近いマッチを current にする
        let cursorLocation = textView.selectedRange().location
        var bestIndex = 0
        for (i, range) in matches.enumerated() {
            if range.location >= cursorLocation {
                bestIndex = i
                break
            }
            if i == matches.count - 1 {
                bestIndex = 0 // ラップアラウンド
            }
        }

        currentResult = FindResult(ranges: matches, currentIndex: bestIndex)
        highlightManager.highlightMatches(matches, currentIndex: bestIndex)
        updateMatchCountLabel()
    }

    private func updateCurrentMatchIndex(for range: NSRange) {
        guard !currentResult.isEmpty else { return }

        if let index = currentResult.ranges.firstIndex(where: { NSEqualRanges($0, range) }) {
            currentResult = FindResult(ranges: currentResult.ranges, currentIndex: index)
            highlightManager.updateCurrentMatch(index: index)
            updateMatchCountLabel()
        }
    }

    private func selectAndScrollTo(range: NSRange, in textView: NSTextView) {
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)

        // 見つかった箇所を黄色で一時的に点滅表示（macOS 標準のバウンスアニメーション）
        textView.showFindIndicator(for: range)

        // Find Pasteboard にコピー（macOS 標準動作）
        let findPasteboard = NSPasteboard(name: .find)
        findPasteboard.clearContents()
        findPasteboard.setString(searchField.stringValue, forType: .string)
    }

    // MARK: - Private: UI Update

    private func updateMatchCountLabel() {
        matchCountLabel.textColor = .secondaryLabelColor

        if searchField.stringValue.isEmpty {
            matchCountLabel.stringValue = ""
        } else if currentResult.isEmpty {
            matchCountLabel.stringValue = "No matches".localized
            matchCountLabel.textColor = .systemRed
        } else {
            let current = currentResult.currentIndex + 1
            let total = currentResult.count
            matchCountLabel.stringValue = "\(current) / \(total)"
        }
    }

    private func updateSearchFieldAppearance() {
        searchField.wantsLayer = true

        if findEngine.options.useRegex {
            // 正規表現モードの場合、バリデーション
            if !searchField.stringValue.isEmpty && !findEngine.validateRegex() {
                searchField.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
            } else {
                searchField.layer?.backgroundColor = nil
            }
            // シンタックスカラーリングを適用
            applyRegexSyntaxColoring()
        } else {
            searchField.layer?.backgroundColor = nil
            // 通常モードではカラーリングをクリア
            clearRegexSyntaxColoring()
        }
    }

    /// フィールドエディタの textStorage にシンタックスカラーリングを適用
    private func applyRegexSyntaxColoring() {
        guard let fieldEditor = searchField.currentEditor() as? NSTextView else { return }
        let text = searchField.stringValue
        guard !text.isEmpty else { return }

        let defaultColor: NSColor
        if searchField.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
            defaultColor = .white
        } else {
            defaultColor = .controlTextColor
        }

        let highlighted = RegexSyntaxHighlighter.highlight(
            text,
            font: searchField.font ?? NSFont.systemFont(ofSize: 12),
            defaultColor: defaultColor
        )

        // フィールドエディタの textStorage に属性を適用
        let storage = fieldEditor.textStorage!
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        // 先にforegroundColorだけクリア
        storage.removeAttribute(.foregroundColor, range: fullRange)
        // カラーリング属性を適用
        highlighted.enumerateAttributes(in: NSRange(location: 0, length: highlighted.length)) { attrs, range, _ in
            if let color = attrs[.foregroundColor] {
                if range.location + range.length <= storage.length {
                    storage.addAttribute(.foregroundColor, value: color, range: range)
                }
            }
        }
        storage.endEditing()
    }

    /// フィールドエディタのカラーリングをクリア
    private func clearRegexSyntaxColoring() {
        guard let fieldEditor = searchField.currentEditor() as? NSTextView else { return }
        let storage = fieldEditor.textStorage!
        guard storage.length > 0 else { return }
        let fullRange = NSRange(location: 0, length: storage.length)
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: NSColor.controlTextColor, range: fullRange)
        storage.endEditing()
    }

    private func updateReplaceRowVisibility(animated: Bool) {
        let targetHeight = isReplaceMode ? Self.replaceRowHeight : 0

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                replaceRowHeightConstraint.animator().constant = targetHeight
                barHeightConstraint.animator().constant = isReplaceMode
                    ? Self.findRowHeight + Self.replaceRowHeight + Self.verticalPadding * 3
                    : Self.findRowHeight + Self.verticalPadding * 2
            }
        } else {
            replaceRowHeightConstraint.constant = targetHeight
            barHeightConstraint.constant = isReplaceMode
                ? Self.findRowHeight + Self.replaceRowHeight + Self.verticalPadding * 3
                : Self.findRowHeight + Self.verticalPadding * 2
        }

        replaceRow.isHidden = !isReplaceMode
    }

    // MARK: - Private: Load Saved Options

    private func loadSavedOptions() {
        let defaults = UserDefaults.standard
        findEngine.options.caseSensitive = defaults.bool(forKey: UserDefaults.Keys.findCaseSensitive)
        findEngine.options.useRegex = defaults.bool(forKey: UserDefaults.Keys.findUseRegex)
        findEngine.options.wholeWord = defaults.bool(forKey: UserDefaults.Keys.findWholeWord)
        findEngine.options.wrapAround = defaults.bool(forKey: UserDefaults.Keys.findWrapAround)

        // 正規表現 ON なら Whole Word を強制 OFF
        if findEngine.options.useRegex {
            findEngine.options.wholeWord = false
        }

        caseSensitiveToggle.state = findEngine.options.caseSensitive ? .on : .off
        regexToggle.state = findEngine.options.useRegex ? .on : .off
        wholeWordToggle.state = findEngine.options.wholeWord ? .on : .off
        wholeWordToggle.isEnabled = !findEngine.options.useRegex
        wrapAroundToggle.state = findEngine.options.wrapAround ? .on : .off

        updateToggleAppearance(caseSensitiveToggle)
        updateToggleAppearance(regexToggle)
        updateToggleAppearance(wholeWordToggle)
        updateToggleAppearance(wrapAroundToggle)

        // Find Pasteboard から検索テキストを読み込み
        if let findString = NSPasteboard(name: .find).string(forType: .string) {
            searchField.stringValue = findString
        }
    }

    // MARK: - Private: Setup UI

    private func setupFindRow() {
        findRow.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(findRow)

        // Search Field
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search".localized
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.controlSize = .small
        searchField.wantsLayer = true
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        findRow.addSubview(searchField)

        // Insert Pattern Button（検索フィールド右隣のポップアップ）
        insertPatternButton.translatesAutoresizingMaskIntoConstraints = false
        insertPatternButton.bezelStyle = .recessed
        insertPatternButton.isBordered = false
        insertPatternButton.image = NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "Insert Pattern")
        insertPatternButton.imagePosition = .imageOnly
        insertPatternButton.controlSize = .small
        insertPatternButton.target = self
        insertPatternButton.action = #selector(showInsertPatternMenu(_:))
        insertPatternButton.toolTip = "Insert Pattern".localized
        insertPatternButton.setContentHuggingPriority(.required, for: .horizontal)
        findRow.addSubview(insertPatternButton)

        // Previous Button
        configureButton(previousButton, image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!, action: #selector(findPrevious(_:)), toolTip: "Find Previous (Shift+Enter)".localized)
        findRow.addSubview(previousButton)

        // Next Button
        configureButton(nextButton, image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!, action: #selector(findNext(_:)), toolTip: "Find Next (Enter)".localized)
        findRow.addSubview(nextButton)

        // Match Count Label
        matchCountLabel.translatesAutoresizingMaskIntoConstraints = false
        matchCountLabel.font = NSFont.systemFont(ofSize: 11)
        matchCountLabel.textColor = .secondaryLabelColor
        matchCountLabel.alignment = .center
        matchCountLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        matchCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        findRow.addSubview(matchCountLabel)

        // Wrap Around Toggle（SF Symbol アイコン）
        configureToggle(wrapAroundToggle, title: "", action: #selector(toggleWrapAround(_:)), toolTip: "Wrap Around".localized)
        if let wrapImage = NSImage(systemSymbolName: "arrow.2.squarepath", accessibilityDescription: "Wrap Around") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            wrapAroundToggle.image = wrapImage.withSymbolConfiguration(config)
            wrapAroundToggle.imagePosition = .imageOnly
        }
        findRow.addSubview(wrapAroundToggle)

        // Case Sensitive Toggle
        configureToggle(caseSensitiveToggle, title: "Aa", action: #selector(toggleCaseSensitive(_:)), toolTip: "Match Case".localized)
        findRow.addSubview(caseSensitiveToggle)

        // Whole Word Toggle（正規表現の左隣）
        configureToggle(wholeWordToggle, title: "W", action: #selector(toggleWholeWord(_:)), toolTip: "Whole Word".localized)
        findRow.addSubview(wholeWordToggle)

        // Regex Toggle
        configureToggle(regexToggle, title: ".*", action: #selector(toggleRegex(_:)), toolTip: "Regular Expression".localized)
        findRow.addSubview(regexToggle)

        // Regex Help Button
        regexHelpButton.translatesAutoresizingMaskIntoConstraints = false
        regexHelpButton.bezelStyle = .helpButton
        regexHelpButton.controlSize = .small
        regexHelpButton.target = self
        regexHelpButton.action = #selector(showRegexHelp(_:))
        regexHelpButton.toolTip = "Regular Expression Help".localized
        regexHelpButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        findRow.addSubview(regexHelpButton)

        // Done Button
        configureButton(doneButton, title: "Done".localized, action: #selector(closeFindBar(_:)), toolTip: nil)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        findRow.addSubview(doneButton)
    }

    private func setupReplaceRow() {
        replaceRow.translatesAutoresizingMaskIntoConstraints = false
        replaceRow.isHidden = true
        view.addSubview(replaceRow)

        // Replace Field
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.placeholderString = "Replace".localized
        replaceField.delegate = self
        replaceField.font = NSFont.systemFont(ofSize: 12)
        replaceField.controlSize = .small
        replaceRow.addSubview(replaceField)

        // Replace Button
        configureButton(replaceButton, title: "Replace".localized, action: #selector(replaceOne(_:)), toolTip: nil)
        replaceRow.addSubview(replaceButton)

        // Replace All Button
        configureButton(replaceAllButton, title: "All".localized, action: #selector(replaceAll(_:)), toolTip: "Replace All".localized)
        replaceRow.addSubview(replaceAllButton)
    }

    private func setupLayout() {
        // Bar height constraint
        barHeightConstraint = view.heightAnchor.constraint(equalToConstant: Self.findRowHeight + Self.verticalPadding * 2)
        barHeightConstraint.isActive = true

        // Bottom separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(separator)

        // Find Row constraints
        NSLayoutConstraint.activate([
            findRow.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.verticalPadding),
            findRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            findRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            findRow.heightAnchor.constraint(equalToConstant: Self.findRowHeight),
        ])

        // Find Row internal layout
        // searchField は伸縮可能（hugging を低く、compression を低めに設定）
        searchField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        searchField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // matchCountLabel も縮小を許可
        matchCountLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: findRow.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            insertPatternButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 2),
            insertPatternButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            insertPatternButton.widthAnchor.constraint(equalToConstant: 20),

            previousButton.leadingAnchor.constraint(equalTo: insertPatternButton.trailingAnchor, constant: 2),
            previousButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 24),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 24),

            matchCountLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 6),
            matchCountLabel.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            matchCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 30),

            wrapAroundToggle.leadingAnchor.constraint(equalTo: matchCountLabel.trailingAnchor, constant: 6),
            wrapAroundToggle.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),

            caseSensitiveToggle.leadingAnchor.constraint(equalTo: wrapAroundToggle.trailingAnchor, constant: 2),
            caseSensitiveToggle.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),

            wholeWordToggle.leadingAnchor.constraint(equalTo: caseSensitiveToggle.trailingAnchor, constant: 2),
            wholeWordToggle.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),

            regexToggle.leadingAnchor.constraint(equalTo: wholeWordToggle.trailingAnchor, constant: 2),
            regexToggle.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),

            regexHelpButton.leadingAnchor.constraint(equalTo: regexToggle.trailingAnchor, constant: 2),
            regexHelpButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),

            doneButton.leadingAnchor.constraint(greaterThanOrEqualTo: regexHelpButton.trailingAnchor, constant: 6),
            doneButton.trailingAnchor.constraint(equalTo: findRow.trailingAnchor),
            doneButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
        ])

        // Search field flexible width（右側要素に押されて縮む）
        let searchFieldTrailing = searchField.trailingAnchor.constraint(equalTo: insertPatternButton.leadingAnchor, constant: -2)
        searchFieldTrailing.priority = .defaultHigh
        searchFieldTrailing.isActive = true

        // Replace Row constraints
        replaceRowHeightConstraint = replaceRow.heightAnchor.constraint(equalToConstant: 0)
        replaceRowHeightConstraint.isActive = true

        NSLayoutConstraint.activate([
            replaceRow.topAnchor.constraint(equalTo: findRow.bottomAnchor, constant: Self.verticalPadding),
            replaceRow.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            replaceRow.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
        ])

        // Replace Row internal layout
        replaceField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        replaceField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        NSLayoutConstraint.activate([
            replaceField.leadingAnchor.constraint(equalTo: replaceRow.leadingAnchor),
            replaceField.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            replaceButton.trailingAnchor.constraint(equalTo: replaceAllButton.leadingAnchor, constant: -4),
            replaceButton.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            replaceAllButton.trailingAnchor.constraint(equalTo: replaceRow.trailingAnchor),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            replaceField.trailingAnchor.constraint(equalTo: replaceButton.leadingAnchor, constant: -4),
        ])

        // Separator constraints
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    // MARK: - Private: Search Field Menu

    private func setupSearchFieldMenu() {
        let menu = NSMenu()

        // Replace Mode toggle (top item)
        let replaceTitle = isReplaceMode
            ? "Hide Replace".localized
            : "Replace".localized
        let replaceItem = NSMenuItem(title: replaceTitle, action: #selector(toggleReplaceMode(_:)), keyEquivalent: "")
        replaceItem.image = NSImage(systemSymbolName: "arrow.right.square", accessibilityDescription: "Replace")
        replaceItem.target = self
        menu.addItem(replaceItem)

        menu.addItem(.separator())

        // Recent Searches section (custom: find/replace pairs)
        let recentEntries = historyManager.recentSearchEntries
        if recentEntries.isEmpty {
            let noRecentsItem = NSMenuItem(title: "No Recent Searches".localized, action: nil, keyEquivalent: "")
            noRecentsItem.isEnabled = false
            menu.addItem(noRecentsItem)
        } else {
            for entry in recentEntries {
                let title = Self.searchEntryMenuTitle(searchText: entry.searchText, replaceText: entry.replaceText)
                let item = NSMenuItem(title: "", action: #selector(loadRecentSearchEntry(_:)), keyEquivalent: "")
                item.attributedTitle = title
                item.target = self
                item.representedObject = entry
                menu.addItem(item)
            }

            menu.addItem(.separator())
            let clearItem = NSMenuItem(title: "Clear Recent Searches".localized, action: #selector(clearRecentSearchEntries(_:)), keyEquivalent: "")
            clearItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")
            clearItem.target = self
            menu.addItem(clearItem)
        }

        // Saved Patterns section
        let savedPatterns = historyManager.savedPatterns
        if !savedPatterns.isEmpty {
            menu.addItem(.separator())

            for pattern in savedPatterns {
                let item = NSMenuItem(title: pattern.name, action: #selector(loadSavedPattern(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pattern
                // ToolTip に検索・置換文字列を表示
                if pattern.replaceText.isEmpty {
                    item.toolTip = pattern.searchText
                } else {
                    item.toolTip = "\(pattern.searchText) → \(pattern.replaceText)"
                }
                // サブメニューに削除オプション
                let submenu = NSMenu()
                let deleteItem = NSMenuItem(title: "", action: #selector(deleteSavedPattern(_:)), keyEquivalent: "")
                deleteItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Delete")
                deleteItem.target = self
                deleteItem.representedObject = pattern.name
                submenu.addItem(deleteItem)
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        // Save Current Pattern
        menu.addItem(.separator())
        let saveItem = NSMenuItem(title: "Save Current Pattern…".localized, action: #selector(saveCurrentPattern(_:)), keyEquivalent: "")
        saveItem.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: "Save")
        saveItem.target = self
        menu.addItem(saveItem)

        searchField.searchMenuTemplate = menu
    }

    /// Recent Search / Saved Pattern メニュー項目のタイトルを生成
    /// replaceText が空の場合は searchText のみ、そうでなければ "searchText → replaceText" 形式
    private static func searchEntryMenuTitle(searchText: String, replaceText: String) -> NSAttributedString {
        if replaceText.isEmpty {
            return NSAttributedString(string: searchText)
        }
        let full = "\(searchText) → \(replaceText)"
        let attr = NSMutableAttributedString(string: full)
        // "→ replaceText" 部分をグレーで表示
        let arrowRange = (full as NSString).range(of: " → \(replaceText)")
        if arrowRange.location != NSNotFound {
            attr.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: arrowRange)
        }
        return attr
    }

    // MARK: - Private: Button Configuration

    private func configureButton(_ button: NSButton, image: NSImage? = nil, title: String? = nil, action: Selector, toolTip: String?) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .recessed
        button.controlSize = .small
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        if let image = image {
            button.image = image
            button.imagePosition = .imageOnly
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            button.image = image.withSymbolConfiguration(config)
        }
        if let title = title {
            button.title = title
            button.font = NSFont.systemFont(ofSize: 11)
        }
    }

    private func configureToggle(_ button: NSButton, title: String, action: Selector, toolTip: String) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setButtonType(.toggle)
        button.bezelStyle = .toolbar
        button.controlSize = .small
        button.title = title
        button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        button.target = self
        button.action = action
        button.toolTip = toolTip
        button.isBordered = true
        button.wantsLayer = true
        button.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        updateToggleAppearance(button)
    }

    /// トグルボタンの見た目を ON/OFF 状態に合わせて更新
    private func updateToggleAppearance(_ button: NSButton) {
        button.wantsLayer = true
        button.layer?.cornerRadius = 4

        if button.state == .on {
            button.contentTintColor = .controlAccentColor
            button.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        } else {
            button.contentTintColor = .secondaryLabelColor
            button.layer?.backgroundColor = nil
        }
    }
}
