//
//  DocumentPreset.swift
//  Jedit-open
//
//  Created by Claude on 2025/01/15.
//

import Foundation
import UniformTypeIdentifiers

// MARK: - Notification Names

extension Notification.Name {
    /// プリセットが追加・削除・変更された時に送信される通知
    static let documentPresetsDidChange = Notification.Name("documentPresetsDidChange")
}

// MARK: - DocumentPreset

struct DocumentPreset: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var data: NewDocData
    var isBuiltIn: Bool
    var uti: String      // 対応UTI（例: "public.text"）
    var regex: String    // ファイル名マッチング用正規表現（例: "\.py$"）

    init(id: UUID = UUID(), name: String, data: NewDocData, isBuiltIn: Bool = false,
         uti: String = "", regex: String = "") {
        self.id = id
        self.name = name
        self.data = data
        self.isBuiltIn = isBuiltIn
        self.uti = uti
        self.regex = regex
    }

    // MARK: - Codable（既存保存データとの後方互換性）

    enum CodingKeys: String, CodingKey {
        case id, name, data, isBuiltIn, uti, regex
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        data = try container.decode(NewDocData.self, forKey: .data)
        isBuiltIn = try container.decode(Bool.self, forKey: .isBuiltIn)
        uti = try container.decodeIfPresent(String.self, forKey: .uti) ?? ""
        regex = try container.decodeIfPresent(String.self, forKey: .regex) ?? ""
    }

    /// 表示用のローカライズ済み名前
    /// ビルトインプリセットは翻訳を返し、ユーザー作成プリセットはそのまま返す
    var displayName: String {
        if isBuiltIn {
            return name.localized
        }
        return name
    }

    // MARK: - Built-in Presets

    static var builtInDefault: DocumentPreset {
        DocumentPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Default",
            data: .default,
            isBuiltIn: true,
            uti: "",
            regex: ""
        )
    }

    static var builtInPlainText: DocumentPreset {
        DocumentPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Plain Text",
            data: .plainText,
            isBuiltIn: true,
            uti: "public.text",
            regex: ""
        )
    }

    static var builtInRichText: DocumentPreset {
        DocumentPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Rich Text",
            data: .richText,
            isBuiltIn: true,
            uti: "public.rtf",
            regex: ""
        )
    }

    static var builtInPresets: [DocumentPreset] {
        [builtInDefault, builtInPlainText, builtInRichText]
    }
}

// MARK: - DocumentPresetManager

class DocumentPresetManager {
    static let shared = DocumentPresetManager()

    private let userDefaultsKey = "documentPresets"
    private let selectedPresetKey = "selectedDocumentPresetID"

    private(set) var presets: [DocumentPreset] = []
    private(set) var selectedPresetID: UUID?

    private init() {
        loadPresets()
    }

    // MARK: - Load/Save

    func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let savedPresets = try? JSONDecoder().decode([DocumentPreset].self, from: data) {
            // マージ: ビルトインプリセットは常に存在、ユーザー追加プリセットを追加
            var result: [DocumentPreset] = []

            // ビルトインプリセットを追加（保存されたデータで上書き可能）
            // ただし uti/regex はビルトイン定義値を常に適用（既存保存データとの互換性）
            for builtIn in DocumentPreset.builtInPresets {
                if var saved = savedPresets.first(where: { $0.id == builtIn.id }) {
                    saved.uti = builtIn.uti
                    saved.regex = builtIn.regex
                    result.append(saved)
                } else {
                    result.append(builtIn)
                }
            }

            // ユーザー追加プリセットを追加
            for preset in savedPresets where !preset.isBuiltIn {
                result.append(preset)
            }

            presets = result
        } else {
            // 初回起動時はビルトインプリセットのみ
            presets = DocumentPreset.builtInPresets
        }

        // 選択されたプリセットIDを読み込み
        if let idString = UserDefaults.standard.string(forKey: selectedPresetKey),
           let id = UUID(uuidString: idString) {
            selectedPresetID = id
        } else {
            selectedPresetID = DocumentPreset.builtInDefault.id
        }
    }

    func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }

        if let id = selectedPresetID {
            UserDefaults.standard.set(id.uuidString, forKey: selectedPresetKey)
        }
    }

    // MARK: - CRUD Operations

    func addPreset(name: String, basedOn preset: DocumentPreset? = nil) -> DocumentPreset {
        let baseData = preset?.data ?? .default
        let newPreset = DocumentPreset(name: name, data: baseData, isBuiltIn: false)
        presets.append(newPreset)
        savePresets()
        notifyPresetsDidChange()
        return newPreset
    }

    func updatePreset(_ preset: DocumentPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            savePresets()
            notifyPresetsDidChange()
        }
    }

    func deletePreset(at index: Int) {
        guard index >= 0 && index < presets.count else { return }
        let preset = presets[index]

        // ビルトインプリセットは削除不可
        guard !preset.isBuiltIn else { return }

        presets.remove(at: index)

        // 削除されたプリセットが選択されていた場合、Defaultに戻す
        if selectedPresetID == preset.id {
            selectedPresetID = DocumentPreset.builtInDefault.id
        }

        savePresets()
        notifyPresetsDidChange()
    }

    func deletePreset(id: UUID) {
        if let index = presets.firstIndex(where: { $0.id == id }) {
            deletePreset(at: index)
        }
    }

    func selectPreset(id: UUID) {
        if presets.contains(where: { $0.id == id }) {
            selectedPresetID = id
            savePresets()
        }
    }

    func selectedPreset() -> DocumentPreset? {
        guard let id = selectedPresetID else { return nil }
        return presets.first { $0.id == id }
    }

    func preset(at index: Int) -> DocumentPreset? {
        guard index >= 0 && index < presets.count else { return nil }
        return presets[index]
    }

    func revertToDefault(at index: Int) {
        guard index >= 0 && index < presets.count else { return }
        let preset = presets[index]

        // ビルトインプリセットのみリセット可能
        guard preset.isBuiltIn else { return }

        if let builtIn = DocumentPreset.builtInPresets.first(where: { $0.id == preset.id }) {
            presets[index] = builtIn
            savePresets()
        }
    }

    // MARK: - Preset Matching

    /// ファイルのURLとUTIタイプ名から、マッチする書類タイププリセットを検索する
    /// プリセット配列を逆順（最後から）に走査し、最初に一致したプリセットを返す
    /// - Parameters:
    ///   - url: ファイルのURL
    ///   - typeName: ファイルのUTIタイプ名
    /// - Returns: マッチしたプリセット、見つからなければ nil
    func findMatchingPreset(url: URL, typeName: String) -> DocumentPreset? {
        let fileName = url.lastPathComponent

        for preset in presets.reversed() {
            // 正規表現マッチ
            if !preset.regex.isEmpty {
                if let regex = try? NSRegularExpression(pattern: preset.regex, options: []),
                   regex.firstMatch(in: fileName, options: [],
                                    range: NSRange(fileName.startIndex..., in: fileName)) != nil {
                    return preset
                }
            }

            // UTI マッチ
            if !preset.uti.isEmpty {
                // 完全一致
                if typeName == preset.uti {
                    return preset
                }
                // UTType 適合チェック（例: public.python-script は public.source-code に適合）
                if let fileType = UTType(typeName), let presetType = UTType(preset.uti),
                   fileType.conforms(to: presetType) {
                    return preset
                }
            }
        }

        return nil
    }

    // MARK: - Notification

    /// プリセットの変更を通知
    private func notifyPresetsDidChange() {
        NotificationCenter.default.post(name: .documentPresetsDidChange, object: self)
    }
}
