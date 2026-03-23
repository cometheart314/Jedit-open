//
//  PreferencesWindowController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
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

class PreferencesWindowController: NSWindowController {
    
    private var splitView: NSSplitView!
    private var outlineView: NSOutlineView!
    private var contentView: NSView!
    private var preferenceItems: [PreferenceCategory] = []
    private var currentViewController: NSViewController?
    
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings".localized
        window.minSize = NSSize(width: 740, height: 480)
        window.center()
        
        self.init(window: window)
        setupPreferenceItems()
        setupUI()
    }
    
    private func setupPreferenceItems() {
        preferenceItems = [
            PreferenceCategory(
                title: "General".localized,
                icon: NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)!,
                identifier: "general"
            ),
            PreferenceCategory(
                title: "NewDocuments".localized,
                icon: NSImage(systemSymbolName: "document.on.document", accessibilityDescription: nil)!,
                identifier: "newDocuments"
            ),
            PreferenceCategory(
                title: "Encodings".localized,
                icon: NSImage(named: "encodingIcon") ?? NSImage(systemSymbolName: "textformat", accessibilityDescription: nil)!,
                identifier: "encodings"
            ),
            PreferenceCategory(
                title: "Line Breaking".localized,
                icon: NSImage(systemSymbolName: "return", accessibilityDescription: nil)!,
                identifier: "lineBreaking"
            ),
            PreferenceCategory(
                title: "Styles".localized,
                icon: NSImage(systemSymbolName: "jacket", accessibilityDescription: nil)!,
                identifier: "styles"
            ),
            PreferenceCategory(
                title: "Context Menu".localized,
                icon: NSImage(systemSymbolName: "contextualmenu.and.cursorarrow", accessibilityDescription: nil)!,
                identifier: "contextMenu"
            )
        ]
    }
    
    private func setupUI() {
        guard let window = window else { return }
        
        // Split View
        splitView = NSSplitView(frame: window.contentView!.bounds)
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]
        
        // Left Sidebar
        let sidebarContainer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 180, height: 500))
        sidebarContainer.hasVerticalScroller = true
        sidebarContainer.autohidesScrollers = true
        sidebarContainer.borderType = .noBorder
        
        outlineView = NSOutlineView(frame: sidebarContainer.bounds)
        outlineView.headerView = nil
        outlineView.focusRingType = .none
        outlineView.rowSizeStyle = .medium
        outlineView.style = .sourceList
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PreferenceColumn"))
        column.width = 240
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        outlineView.dataSource = self
        outlineView.delegate = self
        
        sidebarContainer.documentView = outlineView
        
        // Right Content View
        let contentContainer = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 500))
        contentView = NSView(frame: contentContainer.bounds)
        contentView.autoresizingMask = [.width, .height]
        contentContainer.addSubview(contentView)
        
        splitView.addArrangedSubview(sidebarContainer)
        splitView.addArrangedSubview(contentContainer)
        
        window.contentView = splitView
        
        // Set sidebar width
        splitView.setPosition(240, ofDividerAt: 0)
        
        // Select first item
        DispatchQueue.main.async {
            self.outlineView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            self.showPreferencePane(at: 0)
        }
    }
    
    private func showPreferencePane(at index: Int) {
        guard index < preferenceItems.count else { return }
        
        // Remove current view controller
        currentViewController?.view.removeFromSuperview()
        
        // Create new view controller
        let item = preferenceItems[index]
        let viewController = createViewController(for: item.identifier)
        
        viewController.view.frame = contentView.bounds
        viewController.view.autoresizingMask = [.width, .height]
        contentView.addSubview(viewController.view)
        
        currentViewController = viewController
        
        // Update window title
        window?.title = "Settings".localized + " - " + item.title
    }
    
    private func createViewController(for identifier: String) -> NSViewController {
        switch identifier {
        case "general":
            // XIBから読み込む
            return GeneralPreferencesViewController(nibName: "GeneralPreferences", bundle: nil)
        case "newDocuments":
            return NewDocumentsPreferencesViewController(nibName: "NewDocumentsPreferences", bundle: nil)
        case "encodings":
            return EncodingsPreferencesViewController(nibName: "EncodingsPreferences", bundle: nil)
        case "lineBreaking":
            return LineBreakingPreferencesViewController(nibName: "LineBreakingPreferences", bundle: nil)
        case "styles":
            return StylesPreferencesViewController()
        case "contextMenu":
            return ContextMenuPreferencesViewController()
        default:
            return NSViewController()
        }
    }

    /// 指定されたidentifierのカテゴリを選択して表示
    func selectCategory(identifier: String) {
        guard let index = preferenceItems.firstIndex(where: { $0.identifier == identifier }) else { return }
        outlineView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        showPreferencePane(at: index)
    }
}

// MARK: - NSOutlineViewDataSource

extension PreferencesWindowController: NSOutlineViewDataSource {
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        return item == nil ? preferenceItems.count : 0
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        return preferenceItems[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return false
    }
}

// MARK: - NSOutlineViewDelegate

extension PreferencesWindowController: NSOutlineViewDelegate {
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let preferenceItem = item as? PreferenceCategory else { return nil }
        
        let cellIdentifier = NSUserInterfaceItemIdentifier("PreferenceCell")
        var cellView = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? NSTableCellView
        
        if cellView == nil {
            cellView = NSTableCellView(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
            cellView?.identifier = cellIdentifier
            
            let imageView = NSImageView(frame: NSRect(x: 8, y: 2, width: 20, height: 20))
            imageView.imageScaling = .scaleProportionallyDown
            cellView?.addSubview(imageView)
            cellView?.imageView = imageView
            
            let textField = NSTextField(labelWithString: "")
            textField.frame = NSRect(x: 36, y: 4, width: 200, height: 16)
            textField.font = .systemFont(ofSize: 13)
            cellView?.addSubview(textField)
            cellView?.textField = textField
        }
        
        cellView?.imageView?.image = preferenceItem.icon
        cellView?.textField?.stringValue = preferenceItem.title
        
        return cellView
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        return true
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selectedRow = outlineView.selectedRow
        guard selectedRow >= 0 else { return }
        showPreferencePane(at: selectedRow)
    }
}

// MARK: - PreferenceCategory Model

struct PreferenceCategory {
    let title: String
    let icon: NSImage
    let identifier: String
}
