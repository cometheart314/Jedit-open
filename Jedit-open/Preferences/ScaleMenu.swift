//
//  ScaleMenu.swift
//  Jedit-open
//
//  Created by Claude on 2025/01/16.
//

import Cocoa

/// スケールメニューの選択を通知するプロトコル
protocol ScaleMenuDelegate: AnyObject {
    func scaleMenuDidSelectScale(_ scale: Int)
}

/// 動的にスケールメニュー項目を生成するNSMenuサブクラス
class ScaleMenu: NSMenu, NSMenuDelegate {

    // MARK: - Properties

    weak var scaleMenuDelegate: ScaleMenuDelegate?
    private weak var parentView: NSView?
    private var otherScalePanel: OtherScalePanel?

    // MARK: - Initialization

    override func awakeFromNib() {
        super.awakeFromNib()
        self.delegate = self
    }

    /// 親ビューを設定（シートパネル表示用）
    func setParentView(_ view: NSView) {
        self.parentView = view
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let scalesArray = UserDefaults.standard.array(forKey: UserDefaults.Keys.scaleMenuArray) as? [Int]
            ?? UserDefaults.defaultScaleMenuArray

        // スケール項目を追加
        for scale in scalesArray {
            let item = menu.addItem(
                withTitle: "\(scale)%",
                action: #selector(scaleMenuSelected(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = scale
        }

        // セパレータを追加
        menu.addItem(NSMenuItem.separator())

        // "Add Other Scale..." メニュー項目
        let addOtherItem = menu.addItem(
            withTitle: NSLocalizedString("Add Other Scale...", comment: ""),
            action: #selector(addOtherScaleSelected(_:)),
            keyEquivalent: ""
        )
        addOtherItem.target = self

        // "Revert to Default..." メニュー項目
        let revertItem = menu.addItem(
            withTitle: NSLocalizedString("Revert to Default...", comment: ""),
            action: #selector(revertScaleMenu(_:)),
            keyEquivalent: ""
        )
        revertItem.target = self
    }

    // MARK: - Actions

    @objc private func scaleMenuSelected(_ sender: NSMenuItem) {
        let scale = sender.tag

        // Option キーが押されている場合は削除
        if NSEvent.modifierFlags.contains(.option) {
            removeScale(scale)
        } else {
            scaleMenuDelegate?.scaleMenuDidSelectScale(scale)
        }
    }

    @objc private func addOtherScaleSelected(_ sender: Any) {
        guard let parentView = parentView,
              let window = parentView.window else {
            NSSound.beep()
            return
        }

        if otherScalePanel == nil {
            otherScalePanel = OtherScalePanel()
        }

        otherScalePanel?.beginSheet(for: window) { [weak self] scale in
            if let scale = scale {
                self?.addScale(scale)
                self?.scaleMenuDelegate?.scaleMenuDidSelectScale(scale)
            }
        }
    }

    @objc private func revertScaleMenu(_ sender: Any) {
        UserDefaults.standard.set(UserDefaults.defaultScaleMenuArray, forKey: UserDefaults.Keys.scaleMenuArray)
    }

    // MARK: - Scale Management

    /// 新しいスケールを追加（ソート順を維持）
    func addScale(_ newScale: Int) {
        guard newScale >= 25 && newScale <= 999 else { return }

        var scalesArray = UserDefaults.standard.array(forKey: UserDefaults.Keys.scaleMenuArray) as? [Int]
            ?? UserDefaults.defaultScaleMenuArray

        // 既に存在する場合は何もしない
        if scalesArray.contains(newScale) {
            return
        }

        // ソート順を維持して挿入
        var insertIndex = 0
        for (index, scale) in scalesArray.enumerated() {
            if newScale < scale {
                break
            }
            insertIndex = index + 1
        }

        scalesArray.insert(newScale, at: insertIndex)
        UserDefaults.standard.set(scalesArray, forKey: UserDefaults.Keys.scaleMenuArray)
    }

    /// スケールを削除
    private func removeScale(_ scale: Int) {
        var scalesArray = UserDefaults.standard.array(forKey: UserDefaults.Keys.scaleMenuArray) as? [Int]
            ?? UserDefaults.defaultScaleMenuArray

        // デフォルトのスケールは削除不可（少なくとも1つは残す）
        if scalesArray.count <= 1 {
            NSSound.beep()
            return
        }

        scalesArray.removeAll { $0 == scale }
        UserDefaults.standard.set(scalesArray, forKey: UserDefaults.Keys.scaleMenuArray)
    }

    /// 指定されたスケールがメニューに存在しない場合、追加する
    func adjustMenu(for newScale: Int) {
        addScale(newScale)
    }
}
