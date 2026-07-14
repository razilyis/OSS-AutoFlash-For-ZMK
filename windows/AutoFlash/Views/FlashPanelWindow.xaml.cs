using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using AutoFlash.Services;
using AutoFlash.ViewModels;

namespace AutoFlash.Views;

// キーボード操作主体のフラッシュパネル(macOS版 FirmwareFlashPanel / RegisteredFlashPanel 相当)。
// GitHub / Registered の両フローが同じウィンドウ実装を ViewModel 違いで共有する。
public partial class FlashPanelWindow : Window
{
    private readonly FlashPanelViewModelBase _vm;
    private bool _hasPositioned;

    // Ctrl+K / 歯車: パネルを隠して設定の該当タブを開く(閉じたらパネルを再表示する)
    public Action? OnOpenSettings { get; set; }
    // Tab: もう一方のパネルへ現在座標を引き継いで切り替える
    public Action? OnSwitch { get; set; }

    public FlashPanelWindow(FlashPanelViewModelBase viewModel)
    {
        InitializeComponent();
        _vm = viewModel;
        DataContext = viewModel;
        viewModel.PropertyChanged += OnViewModelPropertyChanged;

        if (viewModel is FirmwareFlashViewModel github)
        {
            github.RunWarningRequested += (message, hasFallback) =>
            {
                Dispatcher.BeginInvoke(async () =>
                {
                    if (FlashConfirmDialog.ShowRunWarning(this, message, hasFallback))
                    {
                        await github.LoadFilesAsync(allowFallback: true);
                    }
                });
            };
        }
    }

    public Point Origin => new(Left, Top);

    public void ShowPanel(Point? origin = null)
    {
        _vm.Reset();
        if (origin is { } point)
        {
            Left = point.X;
            Top = point.Y;
        }
        else if (!_hasPositioned)
        {
            var area = SystemParameters.WorkArea;
            Left = area.Left + (area.Width - Width) / 2;
            Top = area.Top + (area.Height - Height) / 2;
        }
        _hasPositioned = true;
        Show();
        ForceForeground();
    }

    // グローバルホットキーで開いた直後は、直前にフォーカスがあった他アプリの
    // ウィンドウから OS レベルのキーボードフォーカスを奪えないことがある
    // (Activate() だけでは Windows のフォアグラウンド制限に阻まれる)。
    // AttachThreadInput で入力キューを一時的に共有し、確実に SetForegroundWindow する。
    private void ForceForeground()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        var foreground = GetForegroundWindow();
        if (foreground != hwnd)
        {
            var thisThreadId = GetCurrentThreadId();
            var foregroundThreadId = GetWindowThreadProcessId(foreground, out _);
            if (foregroundThreadId != 0 && foregroundThreadId != thisThreadId)
            {
                AttachThreadInput(thisThreadId, foregroundThreadId, true);
                SetForegroundWindow(hwnd);
                AttachThreadInput(thisThreadId, foregroundThreadId, false);
            }
            else
            {
                SetForegroundWindow(hwnd);
            }
        }
        Activate();
        Focus();
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    public void HidePanel() => Hide();

    // Alt+F4 等で破棄されないよう隠すだけにする(Application.Shutdown 時のキャンセルは無視される)
    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        HidePanel();
        base.OnClosing(e);
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(_vm.SelectedIndex) or nameof(_vm.Rows))
        {
            Dispatcher.BeginInvoke(() =>
            {
                // ItemsSource 差し替え時に ListBox の選択が -1 に落ちるため、VM の値を再適用する
                if (_vm.Rows.Count > 0 && RowList.SelectedIndex != _vm.SelectedIndex)
                {
                    RowList.SelectedIndex = _vm.SelectedIndex;
                }
                if (RowList.SelectedItem is not null) RowList.ScrollIntoView(RowList.SelectedItem);
            });
        }
    }

    private async void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        var ctrl = Keyboard.Modifiers.HasFlag(ModifierKeys.Control);
        switch (e.Key)
        {
            case Key.Up:
                _vm.Move(-1);
                e.Handled = true;
                break;
            case Key.Down:
                _vm.Move(1);
                e.Handled = true;
                break;
            case Key.Enter:
                e.Handled = true;
                await SelectAsync();
                break;
            case Key.Escape:
                e.Handled = true;
                if (_vm.IsFirstStage) HidePanel();
                else _vm.Back();
                break;
            case Key.R when ctrl:
                e.Handled = true;
                await _vm.RefreshAsync();
                break;
            case Key.K when ctrl:
                e.Handled = true;
                OpenSettings();
                break;
            case Key.Tab:
                e.Handled = true;
                OnSwitch?.Invoke();
                break;
        }
    }

    private async void OnSelectClick(object sender, RoutedEventArgs e) => await SelectAsync();

    private async void OnRefreshClick(object sender, RoutedEventArgs e) => await _vm.RefreshAsync();

    private void OnSettingsClick(object sender, RoutedEventArgs e) => OpenSettings();

    private void OnCloseClick(object sender, RoutedEventArgs e) => HidePanel();

    // 行のクリックはシングルクリックで選択を確定する(ダブルクリックは使わない。
    // 選択確定でステージが進むと同じ座標に別の行が来るため、2回目のクリックを
    // ダブルクリックとして扱うと意図しない行を選んでしまう)。
    private async void OnRowClick(object sender, MouseButtonEventArgs e)
    {
        if (ItemsControl.ContainerFromElement(RowList, (DependencyObject)e.OriginalSource)
            is not ListBoxItem) return;
        e.Handled = true;
        await SelectAsync();
    }

    private void OnBackgroundMouseDown(object sender, MouseButtonEventArgs e)
    {
        // リスト行やボタンが処理しなかった背景クリックだけがここに届く
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            try { DragMove(); } catch (InvalidOperationException) { }
        }
    }

    private void OpenSettings()
    {
        HidePanel();
        OnOpenSettings?.Invoke();
    }

    private async Task SelectAsync()
    {
        var selection = await _vm.SelectAsync();
        if (selection is null) return;
        ConfirmAndWrite(selection);
    }

    private void ConfirmAndWrite(FlashSelection selection)
    {
        var fileName = Path.GetFileName(selection.FilePath);
        if (!FlashConfirmDialog.Confirm(this, fileName, selection.Volume.DisplayName, selection.Dangerous)) return;
        try
        {
            Flasher.Write(selection.FilePath, fileName, selection.Volume);
            _vm.ReturnToFilesStage();
            Activate();
            Hud.Show($"Flashed to {selection.Volume.DisplayName}. {_vm.FlashSuccessHint}");
        }
        catch (Exception ex)
        {
            Hud.Show($"Flash failed: {ex.Message}");
        }
    }
}
