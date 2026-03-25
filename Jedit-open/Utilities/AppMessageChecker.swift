//
//  AppMessageChecker.swift
//  Jedit-open
//
//  Created by Claude on 2026/03/25.
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

/// GitHub Raw ファイルからアプリ内メッセージを取得して表示する。
/// リポジトリルートの messages.json を定期的にチェックし、
/// 未読メッセージを NSAlert で表示する。
enum AppMessageChecker {

    // MARK: - Configuration

    private static let messagesURL = URL(string: "https://raw.githubusercontent.com/cometheart314/Jedit-open/main/messages.json")!

    // MARK: - JSON Model

    private struct MessagePayload: Decodable {
        let messages: [Message]
    }

    private struct Message: Decodable {
        let id: String
        let date: String
        let minVersion: String
        let maxVersion: String
        let title: String
        let title_en: String?
        let body: String
        let body_en: String?
        let url: String
        let url_en: String?
        let priority: String

        /// ユーザーの言語設定に応じたタイトルを返す。
        var localizedTitle: String {
            if !isJapanese, let en = title_en, !en.isEmpty { return en }
            return title
        }

        /// ユーザーの言語設定に応じた本文を返す。
        var localizedBody: String {
            if !isJapanese, let en = body_en, !en.isEmpty { return en }
            return body
        }

        /// ユーザーの言語設定に応じた URL を返す。
        var localizedURL: String {
            if !isJapanese, let en = url_en, !en.isEmpty { return en }
            return url
        }

        private var isJapanese: Bool {
            Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
        }
    }

    // MARK: - Public API

    /// メッセージをチェックして未読があれば表示する。
    /// バックグラウンドスレッドで JSON を取得し、メインスレッドでアラートを表示する。
    static func checkMessages() {
        URLSession.shared.dataTask(with: messagesURL) { data, response, error in
            guard let data = data, error == nil else {
                NSLog("[AppMessageChecker] Failed to fetch messages: %@", error?.localizedDescription ?? "unknown error")
                return
            }

            // HTTP ステータスコードを確認
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                NSLog("[AppMessageChecker] HTTP status %d", httpResponse.statusCode)
                return
            }

            do {
                let payload = try JSONDecoder().decode(MessagePayload.self, from: data)
                let unread = filterUnreadMessages(payload.messages)
                if !unread.isEmpty {
                    DispatchQueue.main.async {
                        showMessages(unread)
                    }
                }
            } catch {
                NSLog("[AppMessageChecker] JSON decode error: %@", error.localizedDescription)
            }
        }.resume()
    }

    // MARK: - Filtering

    /// 未読かつ対象バージョンのメッセージだけを返す。
    private static func filterUnreadMessages(_ messages: [Message]) -> [Message] {
        let readIDs = Set(UserDefaults.standard.stringArray(forKey: UserDefaults.Keys.readMessageIDs) ?? [])
        let appVersion = appVersionNumber()

        return messages.filter { message in
            // 既読チェック
            if readIDs.contains(message.id) { return false }

            // minVersion チェック（空文字列は制限なし）
            if !message.minVersion.isEmpty,
               let minVer = Double(message.minVersion),
               appVersion < minVer {
                return false
            }

            // maxVersion チェック（空文字列は制限なし）
            if !message.maxVersion.isEmpty,
               let maxVer = Double(message.maxVersion),
               appVersion > maxVer {
                return false
            }

            return true
        }
    }

    /// アプリのビルドバージョン番号（CURRENT_PROJECT_VERSION）を Double で返す。
    private static func appVersionNumber() -> Double {
        guard let versionString = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              let version = Double(versionString) else {
            return 0
        }
        return version
    }

    // MARK: - Display

    /// メッセージを順番に NSAlert で表示し、表示済みを既読として記録する。
    private static func showMessages(_ messages: [Message]) {
        guard let message = messages.first else { return }

        let alert = NSAlert()
        alert.messageText = message.localizedTitle
        alert.informativeText = message.localizedBody

        // priority に応じたアラートスタイル
        switch message.priority {
        case "critical":
            alert.alertStyle = .critical
        case "warning":
            alert.alertStyle = .warning
        default:
            alert.alertStyle = .informational
        }

        alert.addButton(withTitle: "OK")

        // URL がある場合は「詳細を見る」ボタンを追加
        let hasURL = !message.localizedURL.isEmpty && URL(string: message.localizedURL) != nil
        if hasURL {
            alert.addButton(withTitle: "More Info".localized)
        }

        let response = alert.runModal()

        // 「詳細を見る」がクリックされた場合
        if hasURL, response == .alertSecondButtonReturn,
           let url = URL(string: message.localizedURL) {
            NSWorkspace.shared.open(url)
        }

        // 既読として記録
        markAsRead(message.id)

        // 残りのメッセージを表示
        if messages.count > 1 {
            let remaining = Array(messages.dropFirst())
            // 次のメッセージは少し遅延して表示
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showMessages(remaining)
            }
        }
    }

    /// メッセージ ID を既読リストに追加する。
    private static func markAsRead(_ messageID: String) {
        var readIDs = UserDefaults.standard.stringArray(forKey: UserDefaults.Keys.readMessageIDs) ?? []
        if !readIDs.contains(messageID) {
            readIDs.append(messageID)
            UserDefaults.standard.set(readIDs, forKey: UserDefaults.Keys.readMessageIDs)
        }
    }
}
