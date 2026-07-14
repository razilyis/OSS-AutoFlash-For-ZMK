using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Imaging;
using AutoFlash.Models;
using AutoFlash.Services;
using AutoFlash.ViewModels;
using AutoFlash.Views;
using Hardcodet.Wpf.TaskbarNotification;

namespace AutoFlash;

// トレイ常駐アプリ本体(macOS版 AppDelegate 相当)。メインウィンドウは持たない。
public partial class App : Application
{
    private TaskbarIcon? _trayIcon;
    private MenuItem? _githubFlashMenuItem;
    private MenuItem? _registeredFlashMenuItem;
    private FlashPanelWindow? _registeredFlash;
    private FlashPanelWindow? _githubFlash;
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        if (!SingleInstance.TryAcquire())
        {
            Shutdown();
            return;
        }

        ThemeManager.Apply(SettingsStore.Current.Theme);

        _registeredFlash = new FlashPanelWindow(new RegisteredFlashViewModel());
        _githubFlash = new FlashPanelWindow(new FirmwareFlashViewModel());
        // パネルの Ctrl+K: 該当タブで設定を開き、閉じたらパネルへ戻る
        _registeredFlash.OnOpenSettings = () =>
            OpenSettings(SettingsTab.RegisteredFiles, () => _registeredFlash.ShowPanel());
        _githubFlash.OnOpenSettings = () =>
            OpenSettings(SettingsTab.Firmware, () => _githubFlash.ShowPanel());
        // Tab でもう一方のパネルへ同じ位置のまま切り替える
        _registeredFlash.OnSwitch = () =>
        {
            var origin = _registeredFlash.Origin;
            _registeredFlash.HidePanel();
            _githubFlash.ShowPanel(origin);
        };
        _githubFlash.OnSwitch = () =>
        {
            var origin = _githubFlash.Origin;
            _githubFlash.HidePanel();
            _registeredFlash.ShowPanel(origin);
        };

        SetupTrayIcon();
        RegisterHotKeys();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _trayIcon?.Dispose();
        base.OnExit(e);
    }

    private void SetupTrayIcon()
    {
        var menu = new ContextMenu();

        _githubFlashMenuItem = new MenuItem
        {
            Header = HotKeyAction.GithubFlash.Title(),
            InputGestureText = SettingsStore.HotKey(HotKeyAction.GithubFlash).Label,
        };
        _githubFlashMenuItem.Click += (_, _) => OpenGithubFlash();
        menu.Items.Add(_githubFlashMenuItem);

        _registeredFlashMenuItem = new MenuItem
        {
            Header = HotKeyAction.RegisteredFlash.Title(),
            InputGestureText = SettingsStore.HotKey(HotKeyAction.RegisteredFlash).Label,
        };
        _registeredFlashMenuItem.Click += (_, _) => OpenRegisteredFlash();
        menu.Items.Add(_registeredFlashMenuItem);

        menu.Items.Add(new Separator());

        var settingsItem = new MenuItem { Header = "Settings…" };
        settingsItem.Click += (_, _) => OpenSettings();
        menu.Items.Add(settingsItem);

        var quitItem = new MenuItem { Header = "Quit AutoFlash for ZMK" };
        quitItem.Click += (_, _) => Shutdown();
        menu.Items.Add(quitItem);

        // メニューを開くたびにホットキー表示を最新値へ(macOS版 menuWillOpen 相当)
        menu.Opened += (_, _) =>
        {
            _githubFlashMenuItem.InputGestureText = SettingsStore.HotKey(HotKeyAction.GithubFlash).Label;
            _registeredFlashMenuItem.InputGestureText = SettingsStore.HotKey(HotKeyAction.RegisteredFlash).Label;
        };

        _trayIcon = new TaskbarIcon
        {
            IconSource = new BitmapImage(new Uri("pack://application:,,,/Assets/TrayIcon.ico")),
            ToolTipText = "AutoFlash for ZMK",
            MenuActivation = PopupActivationMode.LeftOrRightClick,
            ContextMenu = menu,
        };
    }

    private void RegisterHotKeys()
    {
        var failed = new List<string>();
        if (!HotKeyManager.Shared.Register(
            HotKeyAction.GithubFlash.Id(),
            SettingsStore.HotKey(HotKeyAction.GithubFlash),
            OpenGithubFlash))
        {
            failed.Add(SettingsStore.HotKey(HotKeyAction.GithubFlash).Label);
        }
        if (!HotKeyManager.Shared.Register(
            HotKeyAction.RegisteredFlash.Id(),
            SettingsStore.HotKey(HotKeyAction.RegisteredFlash),
            OpenRegisteredFlash))
        {
            failed.Add(SettingsStore.HotKey(HotKeyAction.RegisteredFlash).Label);
        }
        if (failed.Count > 0)
        {
            // 他アプリが先にグローバル登録している場合。設定で別のキーへ変更してもらう。
            _trayIcon?.ShowBalloonTip(
                "AutoFlash for ZMK",
                $"Hotkey {string.Join(", ", failed)} is in use by another app. " +
                "Change it in Settings → Hotkeys.",
                BalloonIcon.Warning);
        }
    }

    private void OpenGithubFlash()
    {
        _githubFlash?.ShowPanel();
    }

    private void OpenRegisteredFlash()
    {
        _registeredFlash?.ShowPanel();
    }

    private void OpenSettings() => OpenSettings(SettingsTab.General, onClose: null);

    private void OpenSettings(SettingsTab tab, Action? onClose)
    {
        if (_settingsWindow is not null)
        {
            _settingsWindow.SelectTab(tab);
            _settingsWindow.Activate();
            return;
        }
        _settingsWindow = new SettingsWindow(tab, onClose);
        _settingsWindow.Closed += (_, _) => _settingsWindow = null;
        _settingsWindow.Show();
        _settingsWindow.Activate();
    }
}
