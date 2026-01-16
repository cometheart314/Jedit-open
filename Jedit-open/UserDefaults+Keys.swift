//
//  UserDefaults+Keys.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/13.
//

import Foundation

// MARK: - UserDefaults Keys

extension UserDefaults {
    enum Keys {
        static let autoStartOption = "autoStartOption"
        static let startupOption = "startupOption"
        static let appearanceOption = "appearanceOption"
        static let scaleMenuArray = "scaleMenuArray"
    }

    /// スケールメニューのデフォルト値
    static let defaultScaleMenuArray: [Int] = [25, 50, 75, 100, 125, 150, 200, 300, 400]

    /// デフォルト値を登録
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Keys.autoStartOption: false,
            Keys.startupOption: 0,
            Keys.appearanceOption: 0,
            Keys.scaleMenuArray: defaultScaleMenuArray
        ])
    }
}
