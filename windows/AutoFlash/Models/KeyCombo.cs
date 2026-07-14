namespace AutoFlash.Models;

// ホットキー1つ分のキー割り当て。ユーザーが設定画面から任意に変更できる。
// Modifiers は RegisterHotKey の MOD_* フラグ(MOD_NOREPEAT は登録時に付与する)。
public sealed record KeyCombo
{
    public const uint ModAlt = 0x0001;
    public const uint ModControl = 0x0002;
    public const uint ModShift = 0x0004;
    public const uint ModWin = 0x0008;

    public uint VirtualKey { get; init; }
    public uint Modifiers { get; init; }
    public string Label { get; init; } = "";

    public static string BuildLabel(uint modifiers, string keyName)
    {
        var parts = new List<string>();
        if ((modifiers & ModControl) != 0) parts.Add("Ctrl");
        if ((modifiers & ModAlt) != 0) parts.Add("Alt");
        if ((modifiers & ModShift) != 0) parts.Add("Shift");
        if ((modifiers & ModWin) != 0) parts.Add("Win");
        parts.Add(keyName);
        return string.Join("+", parts);
    }
}

// ホットキー識別子(HotKeyManager の登録 ID と settings.json のキーに使う)
public enum HotKeyAction
{
    GithubFlash,
    RegisteredFlash,
}

public static class HotKeyActionExtensions
{
    public static string Id(this HotKeyAction action) => action switch
    {
        HotKeyAction.GithubFlash => "hotkey.githubFlash",
        HotKeyAction.RegisteredFlash => "hotkey.registeredFlash",
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    public static string Title(this HotKeyAction action) => action switch
    {
        HotKeyAction.GithubFlash => "GitHub Firmware Flash",
        HotKeyAction.RegisteredFlash => "Registered File Flash",
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };

    public static KeyCombo DefaultCombo(this HotKeyAction action) => action switch
    {
        // macOS版の ⌥⌘U / ⌥⌘F に相当。F は Ctrl+Alt+F を常駐アプリが先取りしている環境が
        // 珍しくないため、Registered は R(Registered)をデフォルトにする。
        HotKeyAction.GithubFlash => new KeyCombo
        {
            VirtualKey = 0x55, // 'U'
            Modifiers = KeyCombo.ModControl | KeyCombo.ModAlt,
            Label = "Ctrl+Alt+U",
        },
        HotKeyAction.RegisteredFlash => new KeyCombo
        {
            VirtualKey = 0x52, // 'R'
            Modifiers = KeyCombo.ModControl | KeyCombo.ModAlt,
            Label = "Ctrl+Alt+R",
        },
        _ => throw new ArgumentOutOfRangeException(nameof(action)),
    };
}
