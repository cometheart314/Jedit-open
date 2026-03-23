//
//  CalendarDateHelper.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/16.
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

import Foundation

/// 日付・時刻フォーマットのヘルパークラス
class CalendarDateHelper {

    // MARK: - Date Format Types

    enum DateFormatType: Int, CaseIterable {
        case systemShort = 0          // System Short Date Format
        case systemMedium = 1         // System Medium Date Format
        case systemLong = 2           // System Long Date Format
        case systemFull = 3           // System Full Date Format
        case systemShortDateTime = 4  // System Short Date&Time Format
        case systemMediumDateTime = 5 // System Medium Date&Time Format
        case systemLongDateTime = 6   // System Long Date&Time Format
        case systemFullDateTime = 7   // System Full Date&Time Format
        case custom = 8               // Custom Format

        var localizedName: String {
            switch self {
            case .systemShort:
                return "System Short Date Format".localized
            case .systemMedium:
                return "System Medium Date Format".localized
            case .systemLong:
                return "System Long Date Format".localized
            case .systemFull:
                return "System Full Date Format".localized
            case .systemShortDateTime:
                return "System Short Date&Time Format".localized
            case .systemMediumDateTime:
                return "System Medium Date&Time Format".localized
            case .systemLongDateTime:
                return "System Long Date&Time Format".localized
            case .systemFullDateTime:
                return "System Full Date&Time Format".localized
            case .custom:
                let format = UserDefaults.standard.string(forKey: UserDefaults.Keys.customDateFormat) ?? "yyyy-MM-dd"
                return "Custom (\(format))"
            }
        }

        func formattedDate(_ date: Date = Date()) -> String {
            switch self {
            case .systemShort:
                return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .none)
            case .systemMedium:
                return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
            case .systemLong:
                return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .none)
            case .systemFull:
                return DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none)
            case .systemShortDateTime:
                return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
            case .systemMediumDateTime:
                return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .medium)
            case .systemLongDateTime:
                return DateFormatter.localizedString(from: date, dateStyle: .long, timeStyle: .long)
            case .systemFullDateTime:
                return DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .full)
            case .custom:
                let format = UserDefaults.standard.string(forKey: UserDefaults.Keys.customDateFormat) ?? "yyyy-MM-dd"
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale.current
                return formatter.string(from: date)
            }
        }
    }

    // MARK: - Time Format Types

    enum TimeFormatType: Int, CaseIterable {
        case systemShort = 0   // System Short Time Format
        case systemMedium = 1  // System Medium Time Format
        case systemLong = 2    // System Long Time Format
        case systemFull = 3    // System Full Time Format
        case custom = 4        // Custom Format

        var localizedName: String {
            switch self {
            case .systemShort:
                return "System Short Time Format".localized
            case .systemMedium:
                return "System Medium Time Format".localized
            case .systemLong:
                return "System Long Time Format".localized
            case .systemFull:
                return "System Full Time Format".localized
            case .custom:
                let format = UserDefaults.standard.string(forKey: UserDefaults.Keys.customTimeFormat) ?? "HH:mm:ss"
                return "Custom (\(format))"
            }
        }

        func formattedTime(_ date: Date = Date()) -> String {
            switch self {
            case .systemShort:
                return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
            case .systemMedium:
                return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .medium)
            case .systemLong:
                return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .long)
            case .systemFull:
                return DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .full)
            case .custom:
                let format = UserDefaults.standard.string(forKey: UserDefaults.Keys.customTimeFormat) ?? "HH:mm:ss"
                let formatter = DateFormatter()
                formatter.dateFormat = format
                formatter.locale = Locale.current
                return formatter.string(from: date)
            }
        }
    }

    // MARK: - Class Methods

    static var numberOfDateTypes: Int {
        return DateFormatType.allCases.count
    }

    static var numberOfTimeTypes: Int {
        return TimeFormatType.allCases.count
    }

    static func nameOfDateType(_ index: Int) -> String {
        guard let type = DateFormatType(rawValue: index) else { return "" }
        return type.localizedName
    }

    static func nameOfTimeType(_ index: Int) -> String {
        guard let type = TimeFormatType(rawValue: index) else { return "" }
        return type.localizedName
    }

    static func descriptionOfDateType(_ index: Int) -> String {
        guard let type = DateFormatType(rawValue: index) else { return "" }
        return type.formattedDate()
    }

    static func descriptionOfTimeType(_ index: Int) -> String {
        guard let type = TimeFormatType(rawValue: index) else { return "" }
        return type.formattedTime()
    }
}
