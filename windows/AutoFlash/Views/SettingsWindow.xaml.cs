using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AutoFlash.Models;
using AutoFlash.Services;

namespace AutoFlash.Views;

public enum SettingsTab { General, HotKeys, Firmware, RegisteredFiles }

// 設定ウィンドウ(macOS版 SettingsWindow の移植)。
public partial class SettingsWindow : Window
{
    private readonly Action? _onClose;
    private bool _updatingUi;

    public SettingsWindow(SettingsTab tab, Action? onClose)
    {
        // Slider の Minimum="0.4" は、明示的な Value 未設定時に WPF が Value=0 を 0.4 へ
        // 自動補正(coerce)し、その場で ValueChanged を発火させる。これが
        // InitializeComponent() の最中に起きるため、_updatingUi は InitializeComponent()
        // より先に true にしておかないと、保存済みの透過度が 0.4 で上書きされてしまう。
        _updatingUi = true;
        InitializeComponent();
        _onClose = onClose;

        LoadGeneralTab();
        GithubHotKeyRow.Initialize(HotKeyAction.GithubFlash);
        RegisteredHotKeyRow.Initialize(HotKeyAction.RegisteredFlash);
        LoadFirmwareTab();
        LoadRegisteredTab();
        _updatingUi = false;

        SelectTab(tab);
        Closed += (_, _) => _onClose?.Invoke();
    }

    public void SelectTab(SettingsTab tab) => Tabs.SelectedIndex = (int)tab;

    // フラッシュパネルから Ctrl+K で開いた場合、設定側でも Ctrl+K で閉じて元パネルへ戻れる
    private void OnWindowPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (_onClose is not null && e.Key == Key.K
            && Keyboard.Modifiers.HasFlag(ModifierKeys.Control))
        {
            e.Handled = true;
            Close();
        }
    }

    // MARK: - General

    private void LoadGeneralTab()
    {
        LaunchAtLoginCheck.IsChecked = AutoStart.IsEnabled;
        ThemeSelect.SelectedIndex = SettingsStore.Current.Theme.Equals(
            "dark", StringComparison.OrdinalIgnoreCase) ? 0 : 1;
        OpacitySlider.Value = SettingsStore.Current.WindowOpacity;
        UpdateOpacityLabel();
        var github = SettingsStore.HotKey(HotKeyAction.GithubFlash).Label;
        var registered = SettingsStore.HotKey(HotKeyAction.RegisteredFlash).Label;
        PreviewHotKeyText.Text = github;
        PreviewCaption.Text = $"Applies to the flash panels opened by {github} / {registered}.";
    }

    private void OnLaunchAtLoginToggled(object sender, RoutedEventArgs e)
    {
        if (_updatingUi) return;
        try
        {
            AutoStart.SetEnabled(LaunchAtLoginCheck.IsChecked == true);
            LoginErrorText.Visibility = Visibility.Collapsed;
        }
        catch (Exception ex)
        {
            LoginErrorText.Text = ex.Message;
            LoginErrorText.Visibility = Visibility.Visible;
            _updatingUi = true;
            LaunchAtLoginCheck.IsChecked = AutoStart.IsEnabled;
            _updatingUi = false;
        }
    }

    private void OnThemeChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi) return;
        var theme = ThemeSelect.SelectedIndex == 0 ? "dark" : "light";
        SettingsStore.Current.Theme = theme;
        SettingsStore.Save();
        ThemeManager.Apply(theme);
    }

    private void OnOpacityChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (PreviewBackground is not null) PreviewBackground.Opacity = OpacitySlider.Value;
        UpdateOpacityLabel();
        if (_updatingUi) return;
        SettingsStore.Current.WindowOpacity = Math.Round(OpacitySlider.Value, 2);
        SettingsStore.Save();
    }

    private void UpdateOpacityLabel()
    {
        if (OpacityLabel is not null) OpacityLabel.Text = $"{(int)(OpacitySlider.Value * 100)}%";
    }

    // MARK: - GitHub Firmware

    private List<FirmwareRepository> Repositories => SettingsStore.Current.Repositories;

    private FirmwareRepository? SelectedRepository => RepoList.SelectedItem as FirmwareRepository;

    private void LoadFirmwareTab()
    {
        CommonTokenBox.Password = TokenStore.CommonToken;
        UpdateCommonTokenStatus();
        ReloadRepoList(Repositories.FirstOrDefault());
    }

    private void ReloadRepoList(FirmwareRepository? select)
    {
        _updatingUi = true;
        RepoList.ItemsSource = null;
        RepoList.ItemsSource = Repositories;
        _updatingUi = false;
        RepoList.SelectedItem = select;
        if (select is null) UpdateRepoDetailPanel();
    }

    private void UpdateCommonTokenStatus()
    {
        var empty = CommonTokenBox.Password.Length == 0;
        CommonTokenStatus.Text = empty
            ? "No common token set"
            : "Common token saved in the Windows Credential Manager";
        CommonTokenStatus.Foreground = empty
            ? System.Windows.Media.Brushes.Firebrick : System.Windows.Media.Brushes.Gray;
        FetchButton.IsEnabled = !empty;
        FetchButton.ToolTip = empty
            ? "Set a GitHub token above first" : "List repositories your token can access";
    }

    private void OnCommonTokenChanged(object sender, RoutedEventArgs e)
    {
        if (_updatingUi) return;
        TokenStore.CommonToken = CommonTokenBox.Password;
        UpdateCommonTokenStatus();
    }

    private void OnRepoSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi) return;
        UpdateRepoDetailPanel();
    }

    private void UpdateRepoDetailPanel()
    {
        var repository = SelectedRepository;
        RepoRemoveButton.IsEnabled = repository is not null;
        RepoSettingsPanel.Visibility = repository is null ? Visibility.Collapsed : Visibility.Visible;
        if (repository is null) return;
        _updatingUi = true;
        RepoNameBox.Text = repository.Name;
        RepoUrlBox.Text = repository.RepositoryUrl;
        RepoWorkflowBox.Text = repository.Workflow;
        RepoBranchBox.Text = repository.DefaultBranch;
        RepoTokenBox.Password = TokenStore.Token(repository.Id);
        _updatingUi = false;
        UpdateRepoTokenStatus();
    }

    private void OnRepoFieldChanged(object sender, TextChangedEventArgs e)
    {
        if (_updatingUi || SelectedRepository is not { } repository) return;
        repository.Name = RepoNameBox.Text;
        repository.Workflow = RepoWorkflowBox.Text;
        repository.DefaultBranch = RepoBranchBox.Text;
        SettingsStore.Save();
        RepoList.Items.Refresh();
    }

    private void OnRepoUrlChanged(object sender, TextChangedEventArgs e)
    {
        if (_updatingUi || SelectedRepository is not { } repository) return;
        // 名前が未設定/初期値/前回の自動提案のままなら、URL から名前を自動更新する
        var previousSuggested = repository.SuggestedName;
        var shouldUpdateName = repository.Name.Length == 0
            || repository.Name == "New Firmware"
            || repository.Name == previousSuggested;
        repository.RepositoryUrl = RepoUrlBox.Text;
        if (shouldUpdateName && repository.SuggestedName is { } suggested)
        {
            repository.Name = suggested;
            _updatingUi = true;
            RepoNameBox.Text = suggested;
            _updatingUi = false;
        }
        SettingsStore.Save();
        RepoList.Items.Refresh();
    }

    private void OnRepoTokenChanged(object sender, RoutedEventArgs e)
    {
        if (_updatingUi || SelectedRepository is not { } repository) return;
        TokenStore.SetToken(repository.Id, RepoTokenBox.Password);
        UpdateRepoTokenStatus();
    }

    private void UpdateRepoTokenStatus()
    {
        var empty = RepoTokenBox.Password.Length == 0;
        RepoTokenStatus.Text = empty ? "Using common token" : "Overridden with its own token";
        UseCommonTokenButton.IsEnabled = !empty;
    }

    private void OnUseCommonTokenClick(object sender, RoutedEventArgs e)
    {
        RepoTokenBox.Password = "";
    }

    private void OnRepoAddClick(object sender, RoutedEventArgs e)
    {
        var repository = new FirmwareRepository();
        Repositories.Add(repository);
        SettingsStore.Save();
        ReloadRepoList(repository);
    }

    private void OnRepoFetchClick(object sender, RoutedEventArgs e)
    {
        var dialog = new RepoPickerDialog(
            this, TokenStore.CommonToken,
            () => Repositories,
            repository =>
            {
                Repositories.Add(repository);
                SettingsStore.Save();
                ReloadRepoList(repository);
            });
        dialog.ShowDialog();
    }

    private void OnRepoRemoveClick(object sender, RoutedEventArgs e)
    {
        if (SelectedRepository is not { } repository) return;
        // リポジトリ削除時は上書きトークンも削除する
        TokenStore.RemoveToken(repository.Id);
        Repositories.Remove(repository);
        SettingsStore.Save();
        ReloadRepoList(Repositories.FirstOrDefault());
    }

    // MARK: - Registered Files

    private List<RegisteredFirmware> Firmwares => SettingsStore.Current.RegisteredFirmwares;

    private RegisteredFirmware? SelectedFirmware => FirmwareList.SelectedItem as RegisteredFirmware;

    private void LoadRegisteredTab()
    {
        ReloadFirmwareList(Firmwares.FirstOrDefault());
    }

    private void ReloadFirmwareList(RegisteredFirmware? select)
    {
        _updatingUi = true;
        FirmwareList.ItemsSource = null;
        FirmwareList.ItemsSource = Firmwares;
        _updatingUi = false;
        FirmwareList.SelectedItem = select;
        if (select is null) UpdateFirmwareDetailPanel();
    }

    private void OnFirmwareSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_updatingUi) return;
        UpdateFirmwareDetailPanel();
    }

    private void UpdateFirmwareDetailPanel()
    {
        var firmware = SelectedFirmware;
        FirmwareRemoveButton.IsEnabled = firmware is not null;
        FirmwareSettingsPanel.Visibility = firmware is null ? Visibility.Collapsed : Visibility.Visible;
        if (firmware is null) return;
        _updatingUi = true;
        FirmwareNameBox.Text = firmware.Name;
        FirmwarePathText.Text = firmware.FilePath;
        _updatingUi = false;
    }

    private void OnFirmwareNameChanged(object sender, TextChangedEventArgs e)
    {
        if (_updatingUi || SelectedFirmware is not { } firmware) return;
        firmware.Name = FirmwareNameBox.Text;
        SettingsStore.Save();
        FirmwareList.Items.Refresh();
    }

    private void OnFirmwareAddClick(object sender, RoutedEventArgs e)
    {
        if (PickUf2File() is not { } path) return;
        var firmware = new RegisteredFirmware { FilePath = path };
        firmware.Name = firmware.SuggestedName ?? Path.GetFileName(path);
        Firmwares.Add(firmware);
        SettingsStore.Save();
        ReloadFirmwareList(firmware);
    }

    private void OnFirmwareChangeFileClick(object sender, RoutedEventArgs e)
    {
        if (SelectedFirmware is not { } firmware || PickUf2File() is not { } path) return;
        firmware.FilePath = path;
        SettingsStore.Save();
        FirmwarePathText.Text = path;
        FirmwareList.Items.Refresh();
    }

    private void OnFirmwareRemoveClick(object sender, RoutedEventArgs e)
    {
        if (SelectedFirmware is not { } firmware) return;
        Firmwares.Remove(firmware);
        SettingsStore.Save();
        ReloadFirmwareList(Firmwares.FirstOrDefault());
    }

    private string? PickUf2File()
    {
        var dialog = new Microsoft.Win32.OpenFileDialog
        {
            Filter = "UF2 firmware (*.uf2)|*.uf2",
            CheckFileExists = true,
        };
        return dialog.ShowDialog(this) == true ? dialog.FileName : null;
    }
}
