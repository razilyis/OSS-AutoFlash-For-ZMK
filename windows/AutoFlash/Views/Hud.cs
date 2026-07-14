using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media.Animation;
using System.Windows.Threading;

namespace AutoFlash.Views;

// 書き込み完了/失敗の一時フィードバック(macOS版 HUD の移植)。
// フォーカスを奪わず、クリックも透過する。画面下寄り中央に 0.9 秒表示してフェードアウトする。
public static class Hud
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x0020;
    private const int WsExToolWindow = 0x0080;
    private const int WsExNoActivate = 0x08000000;

    private static Window? _current;

    public static void Show(string message)
    {
        _current?.Close();

        var text = new TextBlock
        {
            Text = message,
            FontSize = 14,
            FontWeight = FontWeights.Medium,
        };
        text.SetResourceReference(TextBlock.ForegroundProperty, "Theme.TextPrimary");

        var capsule = new Border
        {
            Padding = new Thickness(18, 10, 18, 10),
            CornerRadius = new CornerRadius(20),
            BorderThickness = new Thickness(1),
            Child = text,
        };
        capsule.SetResourceReference(Border.BackgroundProperty, "Theme.PanelBackground");
        capsule.SetResourceReference(Border.BorderBrushProperty, "Theme.Divider");

        var window = new Window
        {
            WindowStyle = WindowStyle.None,
            AllowsTransparency = true,
            Background = System.Windows.Media.Brushes.Transparent,
            ShowActivated = false,
            ShowInTaskbar = false,
            Topmost = true,
            ResizeMode = ResizeMode.NoResize,
            SizeToContent = SizeToContent.WidthAndHeight,
            Content = capsule,
        };
        window.SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(window).Handle;
            var style = GetWindowLong(handle, GwlExStyle);
            SetWindowLong(handle, GwlExStyle, style | WsExTransparent | WsExNoActivate | WsExToolWindow);
        };
        window.Loaded += (_, _) =>
        {
            var area = SystemParameters.WorkArea;
            window.Left = area.Left + (area.Width - window.ActualWidth) / 2;
            window.Top = area.Bottom - area.Height * 0.16 - window.ActualHeight;
        };
        window.Show();
        _current = window;

        var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(0.9) };
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(window, _current)) return;
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromSeconds(0.35));
            fade.Completed += (_, _) =>
            {
                window.Close();
                if (ReferenceEquals(window, _current)) _current = null;
            };
            window.BeginAnimation(UIElement.OpacityProperty, fade);
        };
        timer.Start();
    }

    [DllImport("user32.dll")]
    private static extern int GetWindowLong(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll")]
    private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
}
