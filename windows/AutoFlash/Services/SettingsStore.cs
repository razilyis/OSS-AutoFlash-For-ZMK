using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using AutoFlash.Models;

namespace AutoFlash.Services;

// 設定の永続化(macOS版の UserDefaults 相当)。
// %APPDATA%\AutoFlashForZMK\settings.json に1ファイルで保存する。
public sealed class AppSettings
{
    public Dictionary<string, KeyCombo> HotKeys { get; set; } = new();
    public double WindowOpacity { get; set; } = 1.0;
    public string Theme { get; set; } = "light";
    public List<FirmwareRepository> Repositories { get; set; } = new();
    public List<RegisteredFirmware> RegisteredFirmwares { get; set; } = new();
}

public static class SettingsStore
{
    public const double WindowOpacityMin = 0.4;
    public const double WindowOpacityMax = 1.0;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };

    public static string Directory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AutoFlashForZMK");

    private static string FilePath => Path.Combine(Directory, "settings.json");

    public static AppSettings Current { get; private set; } = Load();

    // 設定変更の通知(パネルの opacity/テーマ即時反映用。@AppStorage 相当)
    public static event Action? Changed;

    private static AppSettings Load()
    {
        try
        {
            if (File.Exists(FilePath))
            {
                var settings = JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath), JsonOptions);
                if (settings is not null) return settings;
            }
        }
        catch (Exception)
        {
            // 壊れた設定ファイルはデフォルトで起動し、次回保存で上書きする
        }
        return new AppSettings();
    }

    public static void Save()
    {
        System.IO.Directory.CreateDirectory(Directory);
        var tmp = FilePath + ".tmp";
        File.WriteAllText(tmp, JsonSerializer.Serialize(Current, JsonOptions));
        File.Move(tmp, FilePath, overwrite: true);
        Changed?.Invoke();
    }

    public static KeyCombo HotKey(HotKeyAction action) =>
        Current.HotKeys.TryGetValue(action.Id(), out var combo) ? combo : action.DefaultCombo();

    public static void SetHotKey(HotKeyAction action, KeyCombo combo)
    {
        Current.HotKeys[action.Id()] = combo;
        Save();
    }

    public static void ResetHotKey(HotKeyAction action)
    {
        Current.HotKeys.Remove(action.Id());
        Save();
    }
}
