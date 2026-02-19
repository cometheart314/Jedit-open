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
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let matchCountLabel = NSTextField(labelWithString: "")
    private let caseSensitiveToggle = NSButton()
    private let regexToggle = NSButton()
    private let regexHelpButton = NSButton()
    private let wholeWordToggle = NSButton()
    private let doneButton = NSButton()

    // Replace row
    private let replaceField = NSTextField()
    private let replaceButton = NSButton()
    private let replaceAllButton = NSButton()
    private let replaceAndFindButton = NSButton()

    // MARK: - State

    private(set) var isReplaceMode: Bool = false
    private var currentResult: FindResult = .empty

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
    }

    func setSearchText(_ text: String) {
        searchField.stringValue = text
        performIncrementalSearch()
    }

    func focusSearchField() {
        view.window?.makeFirstResponder(searchField)
    }

    func clearSearch() {
        highlightManager.clearAllHighlights()
        currentResult = .empty
        updateMatchCountLabel()
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

    /// NSSearchField のアクション（Recent Searches メニューから選択された時に呼ばれる）
    @objc private func searchFieldAction(_ sender: NSSearchField) {
        updateSearchFieldAppearance()
        performIncrementalSearch()
    }

    @objc private func closeFindBar(_ sender: Any?) {
        clearSearch()
        delegate?.findBarDidClose()
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
        panel.title = NSLocalizedString("Regular Expression Help", comment: "")
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
        isReplaceMode.toggle()
        updateReplaceRowVisibility(animated: true)
    }

    // MARK: - Save / Load Patterns

    @objc private func saveCurrentPattern(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Save Search Pattern", comment: "")
        alert.informativeText = NSLocalizedString("Enter a name for this pattern:", comment: "")
        alert.addButton(withTitle: NSLocalizedString("Save", comment: ""))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))

        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 250, height: 24))
        nameField.placeholderString = NSLocalizedString("Pattern name", comment: "")
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

        searchField.stringValue = pattern.searchText
        replaceField.stringValue = pattern.replaceText

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
        updateSearchFieldAppearance()
        performIncrementalSearch()
    }

    @objc private func deleteSavedPattern(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        historyManager.deletePattern(named: name)
        setupSearchFieldMenu()
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
            self.performIncrementalSearch()
        }
    }

    // MARK: - Private: Recent Searches

    /// SearchHistoryManager と NSSearchField.recentSearches の両方に登録
    private func addToRecentSearches(_ term: String) {
        guard !term.isEmpty else { return }
        historyManager.addSearchTerm(term)

        // NSSearchField の recentSearches に追加（メニューに反映される）
        var recents = searchField.recentSearches
        recents.removeAll { $0 == term }
        recents.insert(term, at: 0)
        if recents.count > SearchHistoryManager.maxHistoryItems {
            recents = Array(recents.prefix(SearchHistoryManager.maxHistoryItems))
        }
        searchField.recentSearches = recents
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
            matchCountLabel.stringValue = NSLocalizedString("Invalid regex", comment: "")
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
            matchCountLabel.stringValue = NSLocalizedString("No matches", comment: "")
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

        updateToggleAppearance(caseSensitiveToggle)
        updateToggleAppearance(regexToggle)
        updateToggleAppearance(wholeWordToggle)

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
        searchField.placeholderString = NSLocalizedString("Search", comment: "")
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.font = NSFont.systemFont(ofSize: 14)
        searchField.controlSize = .small
        searchField.wantsLayer = true
        searchField.target = self
        searchField.action = #selector(searchFieldAction(_:))
        findRow.addSubview(searchField)

        // Previous Button
        configureButton(previousButton, image: NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Previous")!, action: #selector(findPrevious(_:)), toolTip: NSLocalizedString("Find Previous (Shift+Enter)", comment: ""))
        findRow.addSubview(previousButton)

        // Next Button
        configureButton(nextButton, image: NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Next")!, action: #selector(findNext(_:)), toolTip: NSLocalizedString("Find Next (Enter)", comment: ""))
        findRow.addSubview(nextButton)

        // Match Count Label
        matchCountLabel.translatesAutoresizingMaskIntoConstraints = false
        matchCountLabel.font = NSFont.systemFont(ofSize: 11)
        matchCountLabel.textColor = .secondaryLabelColor
        matchCountLabel.alignment = .center
        matchCountLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        matchCountLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        findRow.addSubview(matchCountLabel)

        // Case Sensitive Toggle
        configureToggle(caseSensitiveToggle, title: "Aa", action: #selector(toggleCaseSensitive(_:)), toolTip: NSLocalizedString("Match Case", comment: ""))
        findRow.addSubview(caseSensitiveToggle)

        // Whole Word Toggle（正規表現の左隣）
        configureToggle(wholeWordToggle, title: "W", action: #selector(toggleWholeWord(_:)), toolTip: NSLocalizedString("Whole Word", comment: ""))
        findRow.addSubview(wholeWordToggle)

        // Regex Toggle
        configureToggle(regexToggle, title: ".*", action: #selector(toggleRegex(_:)), toolTip: NSLocalizedString("Regular Expression", comment: ""))
        findRow.addSubview(regexToggle)

        // Regex Help Button
        regexHelpButton.translatesAutoresizingMaskIntoConstraints = false
        regexHelpButton.bezelStyle = .helpButton
        regexHelpButton.controlSize = .small
        regexHelpButton.target = self
        regexHelpButton.action = #selector(showRegexHelp(_:))
        regexHelpButton.toolTip = NSLocalizedString("Regular Expression Help", comment: "")
        regexHelpButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        findRow.addSubview(regexHelpButton)

        // Done Button
        configureButton(doneButton, title: NSLocalizedString("Done", comment: ""), action: #selector(closeFindBar(_:)), toolTip: nil)
        doneButton.setContentHuggingPriority(.required, for: .horizontal)
        findRow.addSubview(doneButton)
    }

    private func setupReplaceRow() {
        replaceRow.translatesAutoresizingMaskIntoConstraints = false
        replaceRow.isHidden = true
        view.addSubview(replaceRow)

        // Replace Field
        replaceField.translatesAutoresizingMaskIntoConstraints = false
        replaceField.placeholderString = NSLocalizedString("Replace", comment: "")
        replaceField.delegate = self
        replaceField.font = NSFont.systemFont(ofSize: 12)
        replaceField.controlSize = .small
        replaceRow.addSubview(replaceField)

        // Replace Button
        configureButton(replaceButton, title: NSLocalizedString("Replace", comment: ""), action: #selector(replaceOne(_:)), toolTip: nil)
        replaceRow.addSubview(replaceButton)

        // Replace All Button
        configureButton(replaceAllButton, title: NSLocalizedString("All", comment: ""), action: #selector(replaceAll(_:)), toolTip: NSLocalizedString("Replace All", comment: ""))
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
        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: findRow.leadingAnchor),
            searchField.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),

            previousButton.leadingAnchor.constraint(equalTo: searchField.trailingAnchor, constant: 4),
            previousButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            previousButton.widthAnchor.constraint(equalToConstant: 24),

            nextButton.leadingAnchor.constraint(equalTo: previousButton.trailingAnchor, constant: 2),
            nextButton.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            nextButton.widthAnchor.constraint(equalToConstant: 24),

            matchCountLabel.leadingAnchor.constraint(equalTo: nextButton.trailingAnchor, constant: 6),
            matchCountLabel.centerYAnchor.constraint(equalTo: findRow.centerYAnchor),
            matchCountLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 50),

            caseSensitiveToggle.leadingAnchor.constraint(equalTo: matchCountLabel.trailingAnchor, constant: 6),
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

        // Search field flexible width
        let searchFieldTrailing = searchField.trailingAnchor.constraint(equalTo: previousButton.leadingAnchor, constant: -4)
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
        NSLayoutConstraint.activate([
            replaceField.leadingAnchor.constraint(equalTo: replaceRow.leadingAnchor),
            replaceField.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),
            replaceField.widthAnchor.constraint(equalTo: searchField.widthAnchor),

            replaceButton.leadingAnchor.constraint(equalTo: replaceField.trailingAnchor, constant: 4),
            replaceButton.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),

            replaceAllButton.leadingAnchor.constraint(equalTo: replaceButton.trailingAnchor, constant: 4),
            replaceAllButton.centerYAnchor.constraint(equalTo: replaceRow.centerYAnchor),
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

        // Recent Searches header
        let recentHeader = NSMenuItem(title: NSLocalizedString("Recent Searches", comment: ""), action: nil, keyEquivalent: "")
        recentHeader.tag = Int(NSSearchField.recentsTitleMenuItemTag)
        menu.addItem(recentHeader)

        // Recent Searches items (auto-managed by NSSearchField)
        let recentItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        recentItem.tag = Int(NSSearchField.recentsMenuItemTag)
        menu.addItem(recentItem)

        // Clear Recents
        let clearItem = NSMenuItem(title: NSLocalizedString("Clear Recent Searches", comment: ""), action: nil, keyEquivalent: "")
        clearItem.tag = Int(NSSearchField.clearRecentsMenuItemTag)
        menu.addItem(clearItem)

        // No Recents
        let noRecentsItem = NSMenuItem(title: NSLocalizedString("No Recent Searches", comment: ""), action: nil, keyEquivalent: "")
        noRecentsItem.tag = Int(NSSearchField.noRecentsMenuItemTag)
        menu.addItem(noRecentsItem)

        // Saved Patterns section
        let savedPatterns = historyManager.savedPatterns
        if !savedPatterns.isEmpty {
            menu.addItem(.separator())

            let patternsHeader = NSMenuItem(title: NSLocalizedString("Saved Patterns", comment: ""), action: nil, keyEquivalent: "")
            patternsHeader.isEnabled = false
            menu.addItem(patternsHeader)

            for pattern in savedPatterns {
                let item = NSMenuItem(title: pattern.name, action: #selector(loadSavedPattern(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = pattern
                // サブメニューに削除オプション
                let submenu = NSMenu()
                let deleteItem = NSMenuItem(title: NSLocalizedString("Delete", comment: ""), action: #selector(deleteSavedPattern(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = pattern.name
                submenu.addItem(deleteItem)
                item.submenu = submenu
                menu.addItem(item)
            }
        }

        // Save Current Pattern
        menu.addItem(.separator())
        let saveItem = NSMenuItem(title: NSLocalizedString("Save Current Pattern…", comment: ""), action: #selector(saveCurrentPattern(_:)), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        // Replace Mode toggle
        menu.addItem(.separator())
        let replaceItem = NSMenuItem(title: NSLocalizedString("Find and Replace", comment: ""), action: #selector(toggleReplaceMode(_:)), keyEquivalent: "")
        replaceItem.target = self
        replaceItem.state = isReplaceMode ? .on : .off
        menu.addItem(replaceItem)

        searchField.searchMenuTemplate = menu
        searchField.recentsAutosaveName = "JeditFindBarSearchHistory"
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
