using System.IO;

namespace AutoFlash.Models;

// 事前に登録したローカルの.uf2ファイル。GitHubを経由せず直接書き込む。
public sealed class RegisteredFirmware
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public string Name { get; set; } = "New Firmware";
    public string FilePath { get; set; } = "";

    public string FileName => FilePath.Length == 0 ? "" : Path.GetFileName(FilePath);

    public string? SuggestedName
    {
        get
        {
            if (FilePath.Length == 0) return null;
            var value = Path.GetFileNameWithoutExtension(FilePath);
            return value.Length == 0 ? null : value;
        }
    }

    public bool FileExists => FilePath.Length > 0 && File.Exists(FilePath);
}
