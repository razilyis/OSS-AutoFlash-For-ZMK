using System.Windows;

namespace AutoFlash.Views;

// 確認ダイアログ(macOS版 NSAlert 相当)。
// 書き込み確認と「最新 run が失敗している」警告の両方で使う。
public partial class FlashConfirmDialog : Window
{
    private FlashConfirmDialog(Window owner, string title, string message, string? primaryText, bool critical)
    {
        InitializeComponent();
        Owner = owner;
        TitleText.Text = title;
        MessageText.Text = message;
        if (primaryText is null)
        {
            FlashButton.Visibility = Visibility.Collapsed;
        }
        else
        {
            FlashButton.Content = primaryText;
        }
        if (critical)
        {
            FlashButton.SetResourceReference(BackgroundProperty, "Theme.Orange");
        }
    }

    // 書き込み前の確認。危険ファイル(reset/clear/erase)は critical 調にする。
    public static bool Confirm(Window owner, string fileName, string volumeName, bool dangerous)
    {
        var dialog = new FlashConfirmDialog(
            owner,
            dangerous ? "Flash the reset UF2?" : "Flash this firmware?",
            $"{fileName}\n→ {volumeName}",
            "Flash",
            dangerous);
        return dialog.ShowDialog() == true;
    }

    // 最新のワークフロー run が成功していないときの警告。
    // true = 直近の成功 run へフォールバックして続行する。
    public static bool ShowRunWarning(Window owner, string message, bool hasSuccessfulFallback)
    {
        var body = message + (hasSuccessfulFallback
            ? "\nYou can fetch the UF2 from the latest successful run instead."
            : "\nNo successful run is available either.");
        var dialog = new FlashConfirmDialog(
            owner,
            "Can't use the latest workflow run",
            body,
            hasSuccessfulFallback ? "Use latest successful run" : null,
            critical: false);
        return dialog.ShowDialog() == true;
    }

    private void OnFlashClick(object sender, RoutedEventArgs e)
    {
        DialogResult = true;
    }
}
