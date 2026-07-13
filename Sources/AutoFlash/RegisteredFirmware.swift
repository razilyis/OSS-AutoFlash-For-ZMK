import Foundation

// 事前に登録したローカルの.uf2ファイル。GitHubを経由せず直接書き込む。
struct RegisteredFirmware: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "New Firmware"
    var filePath = ""

    var url: URL? {
        filePath.isEmpty ? nil : URL(fileURLWithPath: filePath)
    }

    var fileName: String {
        url?.lastPathComponent ?? ""
    }

    var suggestedName: String? {
        guard let url else { return nil }
        let value = url.deletingPathExtension().lastPathComponent
        return value.isEmpty ? nil : value
    }

    var fileExists: Bool {
        guard let url else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}

enum RegisteredFirmwareSettings {
    private static let key = "registered.firmwares"

    static var firmwares: [RegisteredFirmware] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([RegisteredFirmware].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}
