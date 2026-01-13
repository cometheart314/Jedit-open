//
//  GeneralPreferencesViewController.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/29.
//

import Cocoa
import ServiceManagement

// MARK: - UserDefaults Keys

extension UserDefaults {
    enum Keys {
        static let autoStartOption = "autoStartOption"
        static let startupOption = "startupOption"
        static let appearanceOption = "appearanceOption"
    }

    /// デフォルト値を登録
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.autoStartOption: false,
            Keys.startupOption: 0,
            Keys.appearanceOption: 0
        ])
    }
}

// MARK: - GeneralPreferencesViewController

class GeneralPreferencesViewController: NSViewController {

    @IBOutlet weak var autoStartCheckBox: NSButton!
    @IBOutlet weak var startupOptionPopupButton: NSPopUpButton!
    @IBOutlet weak var appearancePopupButton: NSPopUpButton!

    private let defaults = UserDefaults.standard

    override func viewDidLoad() {
        super.viewDidLoad()
        loadPreferences()
    }

    /// UserDefaultsから設定を読み込んでUIに反映
    private func loadPreferences() {
        // Auto Start at Login
        let autoStart = defaults.bool(forKey: UserDefaults.Keys.autoStartOption)
        autoStartCheckBox?.state = autoStart ? .on : .off

        // Startup Option (0: Do Nothing, 1: Open New Document, 2: Show Open Panel)
        let startupOption = defaults.integer(forKey: UserDefaults.Keys.startupOption)
        startupOptionPopupButton?.selectItem(withTag: startupOption)

        // Appearance (0: System, 1: Light, 2: Dark)
        let appearanceOption = defaults.integer(forKey: UserDefaults.Keys.appearanceOption)
        appearancePopupButton?.selectItem(withTag: appearanceOption)
    }

    @IBAction func autoStartCheckBoxClicked(_ sender: Any) {
        guard let button = sender as? NSButton else { return }
        let isOn = button.state == .on

        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            defaults.set(isOn, forKey: UserDefaults.Keys.autoStartOption)
        } catch {
            // エラー時はチェック状態を元に戻す
            button.state = isOn ? .off : .on

            // ユーザーにアラートを表示
            let alert = NSAlert()
            alert.messageText = "Login Item Error"
            alert.informativeText = "Could not configure login item. This feature requires the app to be properly signed and sandboxed.\n\nError: \(error.localizedDescription)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let window = self.view.window {
                alert.beginSheetModal(for: window, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }

    @IBAction func startupOptionSelected(_ sender: Any) {
        guard let popup = sender as? NSPopUpButton else { return }
        let selectedTag = popup.selectedTag()
        defaults.set(selectedTag, forKey: UserDefaults.Keys.startupOption)
    }

    @IBAction func appearancePopupSelected(_ sender: Any) {
        guard let popup = sender as? NSPopUpButton else { return }
        let selectedTag = popup.selectedTag()
        defaults.set(selectedTag, forKey: UserDefaults.Keys.appearanceOption)

        // 外観を即座に適用
        AppDelegate.applyAppearance(selectedTag)
    }
}
