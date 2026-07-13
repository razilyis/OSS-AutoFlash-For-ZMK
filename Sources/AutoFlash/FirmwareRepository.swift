import Foundation
import Security

struct FirmwareRepository: Codable, Identifiable, Hashable {
    var id = UUID()
    var name = "New Firmware"
    var repositoryURL = ""
    var workflow = "build.yml"
    var defaultBranch = "main"

    var suggestedName: String? {
        guard let url = URL(string: repositoryURL) else { return nil }
        let value = url.deletingPathExtension().lastPathComponent
            .removingPercentEncoding?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    var ownerAndRepository: (String, String)? {
        guard let url = URL(string: repositoryURL),
            let host = url.host, host.lowercased().contains("github.com")
        else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        return (parts[0], parts[1].replacingOccurrences(of: ".git", with: ""))
    }
}

enum FirmwareRepositorySettings {
    private static let key = "firmware.repositories"

    static var repositories: [FirmwareRepository] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
            return (try? JSONDecoder().decode([FirmwareRepository].self, from: data)) ?? []
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: key)
            }
        }
    }
}

enum FirmwareTokenStore {
    private static let service = "com.autoflash.zmk.github-firmware"
    private static let commonAccount = "common"

    static var commonToken: String {
        get { token(account: commonAccount) }
        set { setToken(newValue, account: commonAccount) }
    }

    static func effectiveToken(for repositoryID: UUID) -> String {
        let override = token(for: repositoryID)
        return override.isEmpty ? commonToken : override
    }

    static func token(for repositoryID: UUID) -> String {
        token(account: repositoryID.uuidString)
    }

    private static func token(account: String) -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func setToken(_ token: String, for repositoryID: UUID) {
        setToken(token, account: repositoryID.uuidString)
    }

    private static func setToken(_ token: String, account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard !token.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func removeToken(for repositoryID: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: repositoryID.uuidString,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

nonisolated enum GitHubFirmwareAPI {
    struct DownloadedFirmware: Codable, Sendable {
        let url: URL
        let artifactName: String
        let relativePath: String
    }
    struct Branch: Decodable { let name: String }
    struct Runs: Decodable { let workflow_runs: [Run] }
    struct Run: Decodable {
        let id: Int64
        let head_sha: String
        let status: String
        let conclusion: String?
        let run_number: Int
    }
    struct Artifacts: Decodable { let artifacts: [Artifact] }
    struct Artifact: Decodable {
        let id: Int64
        let name: String
        let expired: Bool
        let archive_download_url: URL
    }
    private struct CacheManifest: Codable {
        let runID: Int64
        let commit: String
        let files: [DownloadedFirmware]
    }

    static func branches(for repository: FirmwareRepository, token: String) async throws -> [String] {
        let (owner, repo) = try coordinates(repository)
        let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/branches?per_page=100")!
        let data = try await request(url, token: token)
        return try JSONDecoder().decode([Branch].self, from: data).map(\.name)
    }

    static func latestUF2Files(
        for repository: FirmwareRepository, branch: String, token: String,
        allowLatestSuccessfulFallback: Bool = false
    ) async throws -> (files: [DownloadedFirmware], commit: String, fromCache: Bool) {
        let (owner, repo) = try coordinates(repository)
        let workflow = repository.workflow.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repository.workflow
        var components = URLComponents(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/workflows/\(workflow)/runs")!
        components.queryItems = [
            URLQueryItem(name: "branch", value: branch),
            URLQueryItem(name: "per_page", value: "20"),
        ]
        let runsData = try await request(components.url!, token: token)
        let runs = try JSONDecoder().decode(Runs.self, from: runsData)
        guard let latest = runs.workflow_runs.first else { throw FirmwareAPIError.message("No workflow runs found.") }
        let latestSucceeded = latest.status == "completed" && latest.conclusion == "success"
        let successful = runs.workflow_runs.first { $0.status == "completed" && $0.conclusion == "success" }
        if !latestSucceeded && !allowLatestSuccessfulFallback {
            throw FirmwareAPIError.latestRunNotSuccessful(
                runNumber: latest.run_number,
                state: latest.status == "completed" ? (latest.conclusion ?? "unknown") : latest.status,
                hasSuccessfulFallback: successful != nil)
        }
        guard let run = latestSucceeded ? latest : successful else {
            throw FirmwareAPIError.message("No successful workflow run found.")
        }
        let artifactsURL = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/actions/runs/\(run.id)/artifacts?per_page=100")!
        let artifactsData = try await request(artifactsURL, token: token)
        let artifactList = try JSONDecoder().decode(Artifacts.self, from: artifactsData)
            .artifacts.filter { !$0.expired }
        guard !artifactList.isEmpty else { throw FirmwareAPIError.message("No valid artifacts found.") }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AutoFlashFirmware/\(repository.id.uuidString)/\(run.id)", isDirectory: true)
        let manifestURL = root.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(CacheManifest.self, from: data),
            manifest.runID == run.id,
            !manifest.files.isEmpty,
            manifest.files.allSatisfy({ FileManager.default.fileExists(atPath: $0.url.path) })
        {
            return (manifest.files, manifest.commit, true)
        }
        try? FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var files: [DownloadedFirmware] = []
        for artifact in artifactList {
            // Actions Artifactのdownload endpointはZIPへの302を返す。Release Assetとは異なり
            // application/octet-streamを要求するとHTTP 415になるため、GitHub標準Acceptを使う。
            let data = try await request(artifact.archive_download_url, token: token)
            let zip = root.appendingPathComponent("\(artifact.id).zip")
            try data.write(to: zip, options: .atomic)
            let destination = root.appendingPathComponent(String(artifact.id), isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            process.arguments = ["-x", "-k", zip.path, destination.path]
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw FirmwareAPIError.message("Failed to extract the artifact.") }
            let enumerator = FileManager.default.enumerator(
                at: destination, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            while let url = enumerator?.nextObject() as? URL {
                guard url.pathExtension.lowercased() == "uf2" else { continue }
                let prefix = destination.path.hasSuffix("/") ? destination.path : destination.path + "/"
                let relative = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
                files.append(DownloadedFirmware(
                    url: url, artifactName: artifact.name, relativePath: relative))
            }
        }
        guard !files.isEmpty else { throw FirmwareAPIError.message("No UF2 files found in the artifact.") }
        let sortedFiles = files.sorted {
            if $0.url.lastPathComponent != $1.url.lastPathComponent {
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
            return $0.artifactName.localizedStandardCompare($1.artifactName) == .orderedAscending
        }
        let commit = String(run.head_sha.prefix(7))
        let manifest = CacheManifest(runID: run.id, commit: commit, files: sortedFiles)
        if let data = try? JSONEncoder().encode(manifest) { try? data.write(to: manifestURL, options: .atomic) }
        return (sortedFiles, commit, false)
    }

    private static func coordinates(_ repository: FirmwareRepository) throws -> (String, String) {
        guard let value = repository.ownerAndRepository else { throw FirmwareAPIError.message("Invalid GitHub repository URL.") }
        return value
    }

    private static func request(_ url: URL, token: String, accept: String = "application/vnd.github+json") async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("AutoFlashForZMK", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 401 {
                throw FirmwareAPIError.message(
                    "GitHub authentication required. Press ⌘K to open settings and add a fine-grained token with Actions/Contents Read-only access for this repository.")
            }
            if code == 403 {
                throw FirmwareAPIError.message(
                    "Check your GitHub token's permissions or API rate limit (HTTP 403).")
            }
            if code == 415 {
                throw FirmwareAPIError.message(
                    "The GitHub Actions artifact request format was rejected (HTTP 415).")
            }
            throw FirmwareAPIError.message("GitHub API error (HTTP \(code)).")
        }
        return data
    }
}

enum FirmwareAPIError: LocalizedError {
    case message(String)
    case latestRunNotSuccessful(runNumber: Int, state: String, hasSuccessfulFallback: Bool)
    var errorDescription: String? {
        switch self {
        case .message(let value): value
        case .latestRunNotSuccessful(let number, let state, _):
            "The latest workflow run #\(number) is \(state)."
        }
    }
}
