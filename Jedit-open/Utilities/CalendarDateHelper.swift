//
//  CalendarDateHelper.swift
//  Jedit-open
//
//  Created by Claude on 2026/01/16.
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
                return NSLocalizedString("System Short Date Format", comment: "")
            case .systemMedium:
                return NSLocalizedString("System Medium Date Format", comment: "")
            case .systemLong:
                return NSLocalizedString("System Long Date Format", comment: "")
            case .systemFull:
                return NSLocalizedString("System Full Date Format", comment: "")
            case .systemShortDateTime:
                return NSLocalizedString("System Short Date&Time Format", comment: "")
            case .systemMediumDateTime:
                return NSLocalizedString("System Medium Date&Time Format", comment: "")
            case .systemLongDateTime:
                return NSLocalizedString("System Long Date&Time Format", comment: "")
            case .systemFullDateTime:
                return NSLocalizedString("System Full Date&Time Format", comment: "")
            case .custom:
                return UserDefaults.standard.string(forKey: UserDefaults.Keys.customDateFormat) ?? "yyyy-MM-dd"
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
                return NSLocalizedString("System Short Time Format", comment: "")
            case .systemMedium:
                return NSLocalizedString("System Medium Time Format", comment: "")
            case .systemLong:
                return NSLocalizedString("System Long Time Format", comment: "")
            case .systemFull:
                return NSLocalizedString("System Full Time Format", comment: "")
            case .custom:
                return UserDefaults.standard.string(forKey: UserDefaults.Keys.customTimeFormat) ?? "HH:mm:ss"
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
