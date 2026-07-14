using System.IO;

namespace AutoFlash.Services;

// UF2 ブートローダードライブ。表示名はボリュームラベル(例 NICENANO)、無ければ "E:"。
public sealed record Uf2Volume(string RootPath, string DisplayName);

// UF2 ブートローダードライブの検出と書き込み(macOS版 Flasher の移植)。
// NICENANO / RPI-RP2 等の UF2 ブートローダーは、マウントされたボリューム直下に
// INFO_UF2.TXT を必ず持つため、これで確実に判別できる。
public static class Flasher
{
    // DriveInfo.IsReady はカードリーダー等で数秒ブロックすることがあるためバックグラウンドで列挙する。
    public static Task<List<Uf2Volume>> MountedUf2VolumesAsync() => Task.Run(() =>
    {
        var volumes = new List<Uf2Volume>();
        foreach (var drive in DriveInfo.GetDrives())
        {
            try
            {
                if (!drive.IsReady) continue;
                var root = drive.RootDirectory.FullName;
                if (!File.Exists(Path.Combine(root, "INFO_UF2.TXT"))) continue;
                var label = "";
                try { label = drive.VolumeLabel?.Trim() ?? ""; }
                catch (IOException) { }
                volumes.Add(new Uf2Volume(root, label.Length > 0 ? label : root.TrimEnd('\\')));
            }
            catch (Exception)
            {
                // 取り外し中のドライブ等は無視する
            }
        }
        return volumes;
    });

    // ボリュームへファイルをコピーする(= UF2 書き込み)。
    // 書き込み完了と同時にデバイスが再起動してアンマウントされるため、
    // 例外が出てもドライブ(INFO_UF2.TXT)が消えていれば成功として扱う。
    public static void Write(string sourcePath, string fileName, Uf2Volume volume)
    {
        var destination = Path.Combine(volume.RootPath, fileName);
        try
        {
            if (File.Exists(destination))
            {
                try { File.Delete(destination); } catch (Exception) { }
            }
            File.Copy(sourcePath, destination, overwrite: true);
        }
        catch (Exception) when (!DriveStillPresent(volume.RootPath))
        {
        }
    }

    private static bool DriveStillPresent(string root)
    {
        try { return File.Exists(Path.Combine(root, "INFO_UF2.TXT")); }
        catch (Exception) { return false; }
    }

    // ファイル名に reset/clear/erase を含む UF2 は設定消去用の可能性が高いため警告する。
    public static bool IsDangerous(string fileName)
    {
        var name = fileName.ToLowerInvariant();
        return name.Contains("reset") || name.Contains("clear") || name.Contains("erase");
    }
}
