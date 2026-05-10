//
//  EditorWindowController+SidebarPane.swift
//  Jedit-open
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

//
//  エディタウィンドウの左サイドバーに SidebarPaneProvider のビューを差し込む。
//  Phase 4.1 の MVP として、外側 NSSplitView は使わず、contentView 上で
//  「sidebarContainer | splitView」と並べる方式（既存 splitView の leading 制約だけ
//  付け替えれば済むので、find bar のレイアウトと衝突しない）。
//

import Cocoa

extension EditorWindowController {

    // MARK: - Notifications

    /// サイドバーの表示/非表示が切り替わった時に投げる通知。
    /// (toolbar/menu の有効状態を更新するため)
    static let sidebarPaneVisibilityDidChangeNotification =
        Notification.Name("SidebarPaneVisibilityDidChange")

    // MARK: - Width persistence

    private static let widthDefaultsKey = "SidebarPaneWidth.v1"
    private static let widthMin: CGFloat = 120
    private static let widthMax: CGFloat = 500
    private static let widthDefault: CGFloat = 220

    /// UserDefaults に保存された幅 (なければ widthDefault)
    static var persistedSidebarPaneWidth: CGFloat {
        let raw = UserDefaults.standard.double(forKey: widthDefaultsKey)
        if raw <= 0 { return widthDefault }
        return min(max(CGFloat(raw), widthMin), widthMax)
    }

    static func setPersistedSidebarPaneWidth(_ width: CGFloat) {
        let clamped = min(max(width, widthMin), widthMax)
        UserDefaults.standard.set(Double(clamped), forKey: widthDefaultsKey)
    }

    // MARK: - Install

    /// 起動時、windowDidLoad の最後で呼ぶ。
    /// providers が空、または既に設置済みなら何もしない。
    func installSidebarPaneIfNeeded() {
        guard !isSidebarPaneInstalled else { return }
        let providers = FeatureProviderRegistry.shared.sidebarPaneProviders
        guard !providers.isEmpty,
              let document = textDocument,
              let contentView = window?.contentView,
              let splitView = self.splitView else { return }

        // 既存の splitView.leading = contentView.leading 制約を見つけて差し替える
        let existingLeading = findExistingLeadingConstraint(splitView: splitView,
                                                            contentView: contentView)

        // sidebar コンテナ
        let sidebar = NSView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.wantsLayer = true
        sidebar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.addSubview(sidebar, positioned: .below, relativeTo: splitView)

        let widthConstraint = sidebar.widthAnchor.constraint(equalToConstant: 0)
        widthConstraint.priority = .required

        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: splitView.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: splitView.bottomAnchor),
            widthConstraint,
        ])

        // sidebar の右端にドラッグ可能なハンドルを配置。
        // 視覚的には 1pt の境界線、ヒット領域は 5pt 確保してリサイズ操作を受け付ける。
        let handle = SidebarPaneDragHandle()
        handle.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            handle.topAnchor.constraint(equalTo: sidebar.topAnchor),
            handle.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            handle.widthAnchor.constraint(equalToConstant: 5),
        ])
        handle.onDrag = { [weak self] deltaX in
            self?.adjustSidebarPaneWidth(by: deltaX)
        }
        handle.onDragEnd = { [weak self] in
            guard let self = self,
                  let constraint = self.sidebarPaneWidthConstraint else { return }
            EditorWindowController.setPersistedSidebarPaneWidth(constraint.constant)
        }

        existingLeading?.isActive = false
        splitView.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor).isActive = true

        // プロバイダーごとの VC を縦積み
        var lastBottomAnchor: NSLayoutYAxisAnchor = sidebar.topAnchor
        var lastView: NSView?
        for provider in providers {
            let vc = provider.makeViewController(for: document)
            // NSWindowController は child VC を持たないため、辞書で参照保持する
            let v = vc.view
            v.translatesAutoresizingMaskIntoConstraints = false
            sidebar.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
                v.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
                v.topAnchor.constraint(equalTo: lastBottomAnchor),
            ])
            lastBottomAnchor = v.bottomAnchor
            lastView = v

            sidebarPaneViews[provider.identifier] = v
            sidebarPaneViewControllers[provider.identifier] = vc
            sidebarPaneProviders[provider.identifier] = provider
            sidebarPaneOrder.append(provider.identifier)
        }
        // 最後のビューの bottom を sidebar の bottom に揃える
        // （複数プロバイダーがある場合は最後のビューが残り領域を埋める）
        lastView?.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor).isActive = true

        sidebarPaneContainer = sidebar
        sidebarPaneWidthConstraint = widthConstraint
        isSidebarPaneInstalled = true

        // 初期可視状態を復元
        applyInitialSidebarVisibility()
    }

    private func findExistingLeadingConstraint(splitView: NSView,
                                               contentView: NSView) -> NSLayoutConstraint? {
        for c in contentView.constraints {
            if let first = c.firstItem as? NSView, first === splitView,
               c.firstAttribute == .leading {
                return c
            }
            if let second = c.secondItem as? NSView, second === splitView,
               c.secondAttribute == .leading {
                return c
            }
        }
        return nil
    }

    // MARK: - Visibility

    private func transientKey() -> String? {
        guard let document = self.textDocument else { return nil }
        return ObjectIdentifier(document).debugDescription
    }

    /// 指定プロバイダーが現在表示状態か。未設置なら false。
    func isSidebarPaneVisible(providerIdentifier: String) -> Bool {
        guard isSidebarPaneInstalled,
              let view = sidebarPaneViews[providerIdentifier] else { return false }
        return !view.isHidden
    }

    /// プロバイダー単位での表示切替。
    /// 状態は SidebarVisibilityStore に保存して書類ごとに永続化する。
    func setSidebarPaneVisible(_ visible: Bool, providerIdentifier: String) {
        guard isSidebarPaneInstalled,
              let view = sidebarPaneViews[providerIdentifier] else { return }
        view.isHidden = !visible

        SidebarVisibilityStore.setVisible(visible,
                                          forFileURL: textDocument?.fileURL,
                                          transientKey: transientKey(),
                                          providerIdentifier: providerIdentifier)

        updateSidebarContainerWidth()
        NotificationCenter.default.post(
            name: Self.sidebarPaneVisibilityDidChangeNotification,
            object: self
        )
    }

    /// 設置済みプロバイダーのうち少なくとも 1 つでも表示なら sidebar を広げる。
    /// 完全に非表示の時はコンテナごと isHidden=true にして、右端の境界線も
    /// エディタ領域に染み出さないようにする。
    private func updateSidebarContainerWidth() {
        guard let widthConstraint = sidebarPaneWidthConstraint else { return }
        let anyVisible = sidebarPaneViews.values.contains { !$0.isHidden }
        widthConstraint.constant = anyVisible ? Self.persistedSidebarPaneWidth : 0
        sidebarPaneContainer?.isHidden = !anyVisible
    }

    /// ドラッグハンドルの移動量に応じて sidebar 幅を更新する。永続化はドラッグ終了時。
    fileprivate func adjustSidebarPaneWidth(by deltaX: CGFloat) {
        guard let constraint = sidebarPaneWidthConstraint else { return }
        // 非表示状態でのドラッグは無視
        guard sidebarPaneContainer?.isHidden == false else { return }
        let newWidth = min(max(constraint.constant + deltaX, Self.widthMin), Self.widthMax)
        constraint.constant = newWidth
    }

    /// 起動直後にストアから初期状態を復元する。
    /// 既定値はオフ（最初の起動・未保存書類は非表示）。
    func applyInitialSidebarVisibility() {
        guard isSidebarPaneInstalled else { return }
        for (id, view) in sidebarPaneViews {
            let visible = SidebarVisibilityStore.isVisible(
                forFileURL: textDocument?.fileURL,
                transientKey: transientKey(),
                providerIdentifier: id
            )
            view.isHidden = !visible
        }
        updateSidebarContainerWidth()
    }

    // MARK: - Actions

    /// メニュー / ツールバーから呼ばれる。プロバイダー識別子の取得経路:
    ///  - NSMenuItem.representedObject (String)
    ///  - NSToolbarItem.itemIdentifier.rawValue（プロバイダー識別子をそのまま使う）
    /// いずれも取れなければ最初に登録されているプロバイダーをトグルする。
    @IBAction func toggleSidebarPane(_ sender: Any?) {
        let id: String? = {
            if let menuItem = sender as? NSMenuItem,
               let s = menuItem.representedObject as? String {
                return s
            }
            if let toolbarItem = sender as? NSToolbarItem {
                return toolbarItem.itemIdentifier.rawValue
            }
            return nil
        }()

        let resolvedID: String
        if let id = id, sidebarPaneProviders[id] != nil {
            resolvedID = id
        } else if let first = FeatureProviderRegistry.shared.sidebarPaneProviders.first {
            resolvedID = first.identifier
        } else {
            return
        }
        let currently = isSidebarPaneVisible(providerIdentifier: resolvedID)
        setSidebarPaneVisible(!currently, providerIdentifier: resolvedID)
    }
}

// MARK: - Drag handle

/// サイドバーの右端に重ねるドラッグハンドル。
/// 視覚的には trailing 1pt にセパレーター線を描画し、ヒット領域は 5pt 確保。
/// マウスドラッグの dx を `onDrag` で渡し、ドラッグ終了時に `onDragEnd` を呼ぶ。
final class SidebarPaneDragHandle: NSView {

    var onDrag: ((CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?

    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // 透過背景。境界線は draw(_:) で 1pt 描画する。
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        NSCursor.resizeLeftRight.set()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        // AppKit のドラッグ処理は mouseDown 内でモーダルに nextEvent を回す
        // パターンが安定。mouseDragged を別メソッドで受けるとレイアウト
        // 更新と event の取り回しでカーソルが追随しなくなる。
        guard let window = window else { return }
        NSCursor.resizeLeftRight.set()
        var lastLocation = event.locationInWindow
        var keepTracking = true

        while keepTracking {
            guard let next = window.nextEvent(
                matching: [.leftMouseDragged, .leftMouseUp]
            ) else { break }

            switch next.type {
            case .leftMouseDragged:
                let current = next.locationInWindow
                let dx = current.x - lastLocation.x
                lastLocation = current
                if dx != 0 {
                    onDrag?(dx)
                    // ドラッグ中もカーソル形状を維持（イベントループで再設定）
                    NSCursor.resizeLeftRight.set()
                    // 制約変更をその場で反映してハンドルが追随するようにする
                    window.contentView?.layoutSubtreeIfNeeded()
                }
            case .leftMouseUp:
                keepTracking = false
                onDragEnd?()
            default:
                break
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // 右端 1pt にセパレーター線を描画
        NSColor.separatorColor.setFill()
        let line = NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height)
        line.fill()
    }
}
