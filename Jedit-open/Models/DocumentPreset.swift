//
//  DocumentPreset.swift
//  Jedit-open
//
//  Created by Claude on 2025/01/15.
//

import Foundation

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

    init(id: UUID = UUID(), name: String, data: NewDocData, isBuiltIn: Bool = false) {
        self.id = id
        self.name = name
        self.data = data
        self.isBuiltIn = isBuiltIn
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
            isBuiltIn: true
        )
    }

    static var builtInPlainText: DocumentPreset {
        DocumentPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Plain Text",
            data: .plainText,
            isBuiltIn: true
        )
    }

    static var builtInRichText: DocumentPreset {
        DocumentPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "Rich Text",
            data: .richText,
            isBuiltIn: true
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
            for builtIn in DocumentPreset.builtInPresets {
                if let saved = savedPresets.first(where: { $0.id == builtIn.id }) {
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

    // MARK: - Notification

    /// プリセットの変更を通知
    private func notifyPresetsDidChange() {
        NotificationCenter.default.post(name: .documentPresetsDidChange, object: self)
    }
}
