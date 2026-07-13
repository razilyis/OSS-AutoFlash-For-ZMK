import Foundation

// UF2 ブートローダードライブの検出と書き込み。
// NICENANO / RPI-RP2 等の UF2 ブートローダーは、マウントされたボリューム直下に
// INFO_UF2.TXT を必ず持つため、これで確実に判別できる。
enum Flasher {
    static func mountedUF2Volumes() -> [URL] {
        let volumes =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeIsRemovableKey],
                options: [.skipHiddenVolumes]) ?? []
        return volumes.filter { volume in
            FileManager.default.fileExists(
                atPath: volume.appendingPathComponent("INFO_UF2.TXT").path)
        }
    }

    // ボリュームへファイルをコピーする(= UF2 書き込み)。
    // 書き込み完了と同時にデバイスが再起動してアンマウントされるため、
    // コピー自体が成功していればその後のエラーは無視してよい。
    static func write(fileAt url: URL, named fileName: String, to volume: URL) throws {
        let destination = volume.appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
    }
}
