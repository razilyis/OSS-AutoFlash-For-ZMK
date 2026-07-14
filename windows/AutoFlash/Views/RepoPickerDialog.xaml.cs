using System.Windows;
using System.Windows.Controls;
using AutoFlash.Models;
using AutoFlash.Services;

namespace AutoFlash.Views;

// トークンがアクセスできるリポジトリの一覧から選んで登録するダイアログ
// (macOS版 RepoPickerSheet の移植)。登録済みのものには印を付ける。
public partial class RepoPickerDialog : Window
{
    public sealed class Row
    {
        public required GitHubFirmwareApi.RepositorySummary Repository { get; init; }
        public required bool Added { get; init; }
        public string FullName => Repository.FullName;
        public string DefaultBranchText => $"Default branch: {Repository.DefaultBranch}";
        public Visibility AddedVisibility => Added ? Visibility.Visible : Visibility.Collapsed;
        public Visibility AddVisibility => Added ? Visibility.Collapsed : Visibility.Visible;
    }

    private readonly string _token;
    private readonly Func<IEnumerable<FirmwareRepository>> _currentRepositories;
    private readonly Action<FirmwareRepository> _onSelect;
    private List<GitHubFirmwareApi.RepositorySummary> _results = new();

    public RepoPickerDialog(
        Window owner, string token,
        Func<IEnumerable<FirmwareRepository>> currentRepositories,
        Action<FirmwareRepository> onSelect)
    {
        InitializeComponent();
        Owner = owner;
        _token = token;
        _currentRepositories = currentRepositories;
        _onSelect = onSelect;
        Loaded += async (_, _) => await LoadAsync();
    }

    private async Task LoadAsync()
    {
        LoadingText.Visibility = Visibility.Visible;
        ErrorText.Visibility = Visibility.Collapsed;
        ResultList.Visibility = Visibility.Collapsed;
        EmptyText.Visibility = Visibility.Collapsed;
        try
        {
            _results = await GitHubFirmwareApi.UserRepositoriesAsync(_token);
            LoadingText.Visibility = Visibility.Collapsed;
            ApplyFilter();
        }
        catch (Exception ex)
        {
            LoadingText.Visibility = Visibility.Collapsed;
            ErrorText.Text = ex.Message;
            ErrorText.Visibility = Visibility.Visible;
        }
    }

    private void ApplyFilter()
    {
        // 登録済み判定は owner/repo を小文字に正規化して比較する
        var added = _currentRepositories()
            .Select(r => r.OwnerAndRepository)
            .Where(c => c is not null)
            .Select(c => $"{c!.Value.Owner}/{c.Value.Repo}".ToLowerInvariant())
            .ToHashSet();

        var search = SearchBox.Text.Trim();
        var rows = _results
            .Where(r => search.Length == 0
                || r.FullName.Contains(search, StringComparison.OrdinalIgnoreCase))
            .Select(r => new Row
            {
                Repository = r,
                Added = added.Contains(r.FullName.ToLowerInvariant()),
            })
            .ToList();

        ResultList.ItemsSource = rows;
        ResultList.Visibility = rows.Count > 0 ? Visibility.Visible : Visibility.Collapsed;
        EmptyText.Visibility = rows.Count == 0 && ErrorText.Visibility == Visibility.Collapsed
            ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnSearchChanged(object sender, TextChangedEventArgs e)
    {
        if (_results.Count > 0) ApplyFilter();
    }

    private void OnAddClick(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not Row row) return;
        var repository = new FirmwareRepository
        {
            Name = row.Repository.FullName.Split('/').LastOrDefault() ?? row.Repository.FullName,
            RepositoryUrl = row.Repository.HtmlUrl,
            DefaultBranch = row.Repository.DefaultBranch,
        };
        _onSelect(repository);
        ApplyFilter();
    }
}
