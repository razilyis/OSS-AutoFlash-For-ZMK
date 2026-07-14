using System.Windows;

namespace AutoFlash.Services;

// フラッシュパネルの配色テーマ(Light/Dark)の切り替え。
// Application.Resources の MergedDictionaries を差し替え、全ブラシは DynamicResource で参照する。
public static class ThemeManager
{
    private static ResourceDictionary? _current;

    public static void Apply(string theme)
    {
        var name = theme.Equals("dark", StringComparison.OrdinalIgnoreCase) ? "Dark" : "Light";
        var dictionary = new ResourceDictionary
        {
            Source = new Uri($"Themes/{name}.xaml", UriKind.Relative),
        };
        var merged = Application.Current.Resources.MergedDictionaries;
        if (_current is not null) merged.Remove(_current);
        merged.Add(dictionary);
        _current = dictionary;
    }
}
