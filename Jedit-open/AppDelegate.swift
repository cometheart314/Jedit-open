//
//  AppDelegate.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    private var preferencesWindowController: PreferencesWindowController?
    private var hasHandledStartup = false

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // UserDefaultsのデフォルト値を登録
        UserDefaults.registerDefaults()

        // 外観設定を適用
        let appearanceOption = UserDefaults.standard.integer(forKey: UserDefaults.Keys.appearanceOption)
        AppDelegate.applyAppearance(appearanceOption)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
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
}

