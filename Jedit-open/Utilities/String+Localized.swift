//
//  String+Localized.swift
//  Jedit-open
//
//  Created by 松本慧 on 2025/12/25.
//

import Foundation

extension String {
    var localized: String {
        return NSLocalizedString(self, comment: "")
    }
}
