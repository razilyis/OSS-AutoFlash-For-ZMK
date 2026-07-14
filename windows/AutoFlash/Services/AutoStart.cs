using Microsoft.Win32;

namespace AutoFlash.Services;

// ログイン時自動起動(macOS版 LoginItem 相当)。HKCU の Run キーに exe パスを登録する。
// exe パス直書きのため、アプリを移動した場合は設定し直す必要がある。
public static class AutoStart
{
    private const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";
    private const string ValueName = "AutoFlashForZMK";

    public static bool IsEnabled
    {
        get
        {
            using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
            return key?.GetValue(ValueName) is not null;
        }
    }

    public static void SetEnabled(bool enabled)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath, writable: true)
            ?? Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (enabled)
        {
            var exe = Environment.ProcessPath
                ?? throw new InvalidOperationException("Cannot determine the executable path.");
            key.SetValue(ValueName, $"\"{exe}\"");
        }
        else
        {
            key.DeleteValue(ValueName, throwOnMissingValue: false);
        }
    }
}
