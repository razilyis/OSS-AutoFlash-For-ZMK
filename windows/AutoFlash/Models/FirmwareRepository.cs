namespace AutoFlash.Models;

// GitHub Actions Artifact からファームウェアを取得するリポジトリの登録情報。
public sealed class FirmwareRepository
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "New Firmware";
    public string RepositoryUrl { get; set; } = "";
    public string Workflow { get; set; } = "build.yml";
    public string DefaultBranch { get; set; } = "main";

    public string? SuggestedName
    {
        get
        {
            if (!Uri.TryCreate(RepositoryUrl, UriKind.Absolute, out var url)) return null;
            var last = url.Segments.LastOrDefault()?.Trim('/') ?? "";
            if (last.EndsWith(".git", StringComparison.OrdinalIgnoreCase)) last = last[..^4];
            last = Uri.UnescapeDataString(last).Trim();
            return last.Length == 0 ? null : last;
        }
    }

    // (owner, repo)。github.com の URL でなければ null。
    public (string Owner, string Repo)? OwnerAndRepository
    {
        get
        {
            if (!Uri.TryCreate(RepositoryUrl, UriKind.Absolute, out var url)) return null;
            if (!url.Host.Contains("github.com", StringComparison.OrdinalIgnoreCase)) return null;
            var parts = url.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2) return null;
            return (parts[0], parts[1].Replace(".git", ""));
        }
    }
}
