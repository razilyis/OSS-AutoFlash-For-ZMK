using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using AutoFlash.Models;

namespace AutoFlash.Services;

public sealed class FirmwareApiException : Exception
{
    public FirmwareApiException(string message) : base(message) { }
}

// 最新のワークフロー実行が成功していない場合に投げる。UI側でフォールバック確認ダイアログを出す。
public sealed class LatestRunNotSuccessfulException : Exception
{
    public int RunNumber { get; }
    public string State { get; }
    public bool HasSuccessfulFallback { get; }

    public LatestRunNotSuccessfulException(int runNumber, string state, bool hasSuccessfulFallback)
        : base($"The latest workflow run #{runNumber} is {state}.")
    {
        RunNumber = runNumber;
        State = state;
        HasSuccessfulFallback = hasSuccessfulFallback;
    }
}

// GitHub REST API クライアント(macOS版 GitHubFirmwareAPI の移植)。
public static class GitHubFirmwareApi
{
    public sealed record DownloadedFirmware(string FilePath, string ArtifactName, string RelativePath);

    public sealed record RepositorySummary(
        [property: JsonPropertyName("full_name")] string FullName,
        [property: JsonPropertyName("html_url")] string HtmlUrl,
        [property: JsonPropertyName("default_branch")] string DefaultBranch);

    private sealed record Branch([property: JsonPropertyName("name")] string Name);

    private sealed record Runs([property: JsonPropertyName("workflow_runs")] List<Run> WorkflowRuns);

    private sealed record Run(
        [property: JsonPropertyName("id")] long Id,
        [property: JsonPropertyName("head_sha")] string HeadSha,
        [property: JsonPropertyName("status")] string Status,
        [property: JsonPropertyName("conclusion")] string? Conclusion,
        [property: JsonPropertyName("run_number")] int RunNumber);

    private sealed record Artifacts([property: JsonPropertyName("artifacts")] List<Artifact> Items);

    private sealed record Artifact(
        [property: JsonPropertyName("id")] long Id,
        [property: JsonPropertyName("name")] string Name,
        [property: JsonPropertyName("expired")] bool Expired,
        [property: JsonPropertyName("archive_download_url")] string ArchiveDownloadUrl);

    private sealed record CacheManifest(long RunId, string Commit, List<DownloadedFirmware> Files);

    // artifact の ZIP ダウンロードは Azure Blob への 302 を返す。HttpClient は別ホストへの
    // リダイレクトで Authorization ヘッダを自動的に落とすため、そのままで正しく動く。
    private static readonly HttpClient Http = new();

    private static string CacheRoot => Path.Combine(Path.GetTempPath(), "AutoFlashForZMK");

    public static async Task<List<RepositorySummary>> UserRepositoriesAsync(string token)
    {
        var results = new List<RepositorySummary>();
        var url = "https://api.github.com/user/repos?per_page=100&sort=full_name";
        while (url is not null)
        {
            var (data, response) = await RequestAsync(url, token);
            results.AddRange(JsonSerializer.Deserialize<List<RepositorySummary>>(data) ?? new());
            url = NextPageUrl(response);
        }
        return results;
    }

    private static string? NextPageUrl(HttpResponseMessage response)
    {
        if (!response.Headers.TryGetValues("Link", out var values)) return null;
        foreach (var link in values)
        {
            foreach (var part in link.Split(','))
            {
                var segments = part.Split(';').Select(s => s.Trim()).ToArray();
                if (segments.Length < 2 || segments[1] != "rel=\"next\"") continue;
                if (segments[0].StartsWith('<') && segments[0].EndsWith('>'))
                {
                    return segments[0][1..^1];
                }
            }
        }
        return null;
    }

    public static async Task<List<string>> BranchesAsync(FirmwareRepository repository, string token)
    {
        var (owner, repo) = Coordinates(repository);
        var (data, _) = await RequestAsync(
            $"https://api.github.com/repos/{owner}/{repo}/branches?per_page=100", token);
        return (JsonSerializer.Deserialize<List<Branch>>(data) ?? new()).Select(b => b.Name).ToList();
    }

    public static async Task<(List<DownloadedFirmware> Files, string Commit, bool FromCache)> LatestUf2FilesAsync(
        FirmwareRepository repository, string branch, string token,
        bool allowLatestSuccessfulFallback = false)
    {
        var (owner, repo) = Coordinates(repository);
        var workflow = Uri.EscapeDataString(repository.Workflow);
        var runsUrl = $"https://api.github.com/repos/{owner}/{repo}/actions/workflows/{workflow}/runs" +
            $"?branch={Uri.EscapeDataString(branch)}&per_page=20";
        var (runsData, _) = await RequestAsync(runsUrl, token);
        var runs = JsonSerializer.Deserialize<Runs>(runsData)?.WorkflowRuns ?? new();
        var latest = runs.FirstOrDefault()
            ?? throw new FirmwareApiException("No workflow runs found.");
        var latestSucceeded = latest.Status == "completed" && latest.Conclusion == "success";
        var successful = runs.FirstOrDefault(r => r.Status == "completed" && r.Conclusion == "success");
        if (!latestSucceeded && !allowLatestSuccessfulFallback)
        {
            throw new LatestRunNotSuccessfulException(
                latest.RunNumber,
                latest.Status == "completed" ? (latest.Conclusion ?? "unknown") : latest.Status,
                successful is not null);
        }
        var run = latestSucceeded ? latest : successful
            ?? throw new FirmwareApiException("No successful workflow run found.");

        var artifactsUrl = $"https://api.github.com/repos/{owner}/{repo}/actions/runs/{run.Id}/artifacts?per_page=100";
        var (artifactsData, _) = await RequestAsync(artifactsUrl, token);
        var artifacts = (JsonSerializer.Deserialize<Artifacts>(artifactsData)?.Items ?? new())
            .Where(a => !a.Expired).ToList();
        if (artifacts.Count == 0) throw new FirmwareApiException("No valid artifacts found.");

        // run ID をキーにキャッシュする。最新の成功 run が変わっていなければ再ダウンロードしない。
        var root = Path.Combine(CacheRoot, repository.Id.ToString(), run.Id.ToString());
        var manifestPath = Path.Combine(root, "manifest.json");
        if (File.Exists(manifestPath))
        {
            try
            {
                var manifest = JsonSerializer.Deserialize<CacheManifest>(File.ReadAllText(manifestPath));
                if (manifest is not null && manifest.RunId == run.Id && manifest.Files.Count > 0
                    && manifest.Files.All(f => File.Exists(f.FilePath)))
                {
                    return (manifest.Files, manifest.Commit, true);
                }
            }
            catch (Exception)
            {
            }
        }
        try { Directory.Delete(root, recursive: true); } catch (Exception) { }
        Directory.CreateDirectory(root);

        var files = new List<DownloadedFirmware>();
        foreach (var artifact in artifacts)
        {
            // Actions Artifact の download endpoint は ZIP への 302 を返す。Release Asset とは異なり
            // application/octet-stream を要求すると HTTP 415 になるため、GitHub 標準 Accept を使う。
            var (zipData, _) = await RequestAsync(artifact.ArchiveDownloadUrl, token);
            var zipPath = Path.Combine(root, $"{artifact.Id}.zip");
            await File.WriteAllBytesAsync(zipPath, zipData);
            var destination = Path.Combine(root, artifact.Id.ToString());
            Directory.CreateDirectory(destination);
            try
            {
                ZipFile.ExtractToDirectory(zipPath, destination, overwriteFiles: true);
            }
            catch (Exception)
            {
                throw new FirmwareApiException("Failed to extract the artifact.");
            }
            foreach (var file in Directory.EnumerateFiles(destination, "*.uf2", SearchOption.AllDirectories))
            {
                files.Add(new DownloadedFirmware(
                    file, artifact.Name, Path.GetRelativePath(destination, file)));
            }
        }
        if (files.Count == 0) throw new FirmwareApiException("No UF2 files found in the artifact.");

        // エクスプローラーと同じ自然順(macOS版 localizedStandardCompare 相当)で
        // ファイル名 → artifact 名の2キーでソートする。
        files.Sort((a, b) =>
        {
            var nameA = Path.GetFileName(a.FilePath);
            var nameB = Path.GetFileName(b.FilePath);
            var byName = StrCmpLogicalW(nameA, nameB);
            return byName != 0 ? byName : StrCmpLogicalW(a.ArtifactName, b.ArtifactName);
        });

        var commit = run.HeadSha.Length >= 7 ? run.HeadSha[..7] : run.HeadSha;
        try
        {
            File.WriteAllText(manifestPath, JsonSerializer.Serialize(new CacheManifest(run.Id, commit, files)));
        }
        catch (Exception)
        {
        }
        return (files, commit, false);
    }

    private static (string Owner, string Repo) Coordinates(FirmwareRepository repository) =>
        repository.OwnerAndRepository
            ?? throw new FirmwareApiException("Invalid GitHub repository URL.");

    private static async Task<(byte[] Data, HttpResponseMessage Response)> RequestAsync(string url, string token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        request.Headers.TryAddWithoutValidation("Accept", "application/vnd.github+json");
        request.Headers.TryAddWithoutValidation("X-GitHub-Api-Version", "2026-03-10");
        request.Headers.TryAddWithoutValidation("User-Agent", "AutoFlashForZMK");
        if (token.Length > 0)
        {
            request.Headers.TryAddWithoutValidation("Authorization", $"Bearer {token}");
        }
        HttpResponseMessage response;
        try
        {
            response = await Http.SendAsync(request);
        }
        catch (HttpRequestException ex)
        {
            throw new FirmwareApiException($"Network error: {ex.Message}");
        }
        if (!response.IsSuccessStatusCode)
        {
            var code = (int)response.StatusCode;
            response.Dispose();
            throw code switch
            {
                401 => new FirmwareApiException(
                    "GitHub authentication required. Press Ctrl+K to open settings and add a fine-grained token " +
                    "with Actions/Contents Read-only access for this repository."),
                403 => new FirmwareApiException(
                    "Check your GitHub token's permissions or API rate limit (HTTP 403)."),
                415 => new FirmwareApiException(
                    "The GitHub Actions artifact request format was rejected (HTTP 415)."),
                _ => new FirmwareApiException($"GitHub API error (HTTP {code})."),
            };
        }
        var data = await response.Content.ReadAsByteArrayAsync();
        return (data, response);
    }

    [DllImport("shlwapi.dll", CharSet = CharSet.Unicode)]
    private static extern int StrCmpLogicalW(string a, string b);
}
