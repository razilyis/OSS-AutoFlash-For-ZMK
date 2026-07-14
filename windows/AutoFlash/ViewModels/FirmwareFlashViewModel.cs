using System.IO;
using AutoFlash.Models;
using AutoFlash.Services;

namespace AutoFlash.ViewModels;

// GitHub Actions Artifact からの書き込みフロー(macOS版 FirmwareFlashStore の移植)。
// ステージ: repositories → branches → files → volumes
public sealed class FirmwareFlashViewModel : FlashPanelViewModelBase
{
    private enum Stage { Repositories, Branches, Files, Volumes }

    private Stage _stage = Stage.Repositories;
    private List<FirmwareRepository> _repositories = new();
    private List<string> _branches = new();
    private List<GitHubFirmwareApi.DownloadedFirmware> _files = new();
    private List<Uf2Volume> _volumes = new();
    private FirmwareRepository? _repository;
    private string _branch = "";
    private GitHubFirmwareApi.DownloadedFirmware? _file;
    private string _commit = "";
    private bool _fromCache;

    // 最新 run が成功していないときに UI へ確認ダイアログを要求する(message, hasSuccessfulFallback)
    public event Action<string, bool>? RunWarningRequested;

    public override string Title => _stage switch
    {
        Stage.Repositories => "Select a repository",
        Stage.Branches => "Select a branch",
        Stage.Files => "Select a UF2 to flash",
        _ => "Select a destination",
    };

    public override IReadOnlyList<FlashRow> Rows => _stage switch
    {
        Stage.Repositories => _repositories
            .Select(r => new FlashRow(r.Name, r.RepositoryUrl, false)).ToList(),
        Stage.Branches => _branches
            .Select(b => new FlashRow(b, b == _repository?.DefaultBranch ? "default branch" : "", false))
            .ToList(),
        Stage.Files => _files
            .Select(f => new FlashRow(
                Path.GetFileName(f.FilePath),
                $"{f.ArtifactName} · {f.RelativePath} · commit {_commit}{(_fromCache ? " · cached" : "")}",
                Flasher.IsDangerous(Path.GetFileName(f.FilePath))))
            .ToList(),
        _ => _volumes.Select(v => new FlashRow(v.DisplayName, v.RootPath, false)).ToList(),
    };

    public override string BadgeGlyph => "";  // memorychip 相当 (Segoe: Memory)
    public override string StageGlyph => _stage switch
    {
        Stage.Repositories => "",  // Package
        Stage.Branches => "",      // Switch(ブランチ分岐)
        Stage.Files => "",         // Page
        _ => "",                   // USB
    };
    public override bool IsFirstStage => _stage == Stage.Repositories;
    public override string SwitchHint => "Tab Registered Files";
    public override string HotKeyLabel => SettingsStore.HotKey(HotKeyAction.GithubFlash).Label;
    public override string FlashSuccessHint => "You can select the next UF2.";

    public override void Reset()
    {
        _repositories = SettingsStore.Current.Repositories.ToList();
        _stage = Stage.Repositories;
        ErrorMessage = null;
        _branches.Clear();
        _files.Clear();
        _volumes.Clear();
        _repository = null;
        _file = null;
        NotifyStageChanged();
    }

    public override async Task<FlashSelection?> SelectAsync()
    {
        if (SelectedIndex >= Rows.Count) return null;
        switch (_stage)
        {
            case Stage.Repositories:
                _repository = _repositories[SelectedIndex];
                await LoadBranchesAsync();
                return null;
            case Stage.Branches:
                _branch = _branches[SelectedIndex];
                await LoadFilesAsync();
                return null;
            case Stage.Files:
                _file = _files[SelectedIndex];
                await LoadVolumesAsync();
                return null;
            default:
                if (_file is null) return null;
                var volume = _volumes[SelectedIndex];
                return new FlashSelection(
                    _file.FilePath, volume, Flasher.IsDangerous(Path.GetFileName(_file.FilePath)));
        }
    }

    public override void Back()
    {
        ErrorMessage = null;
        switch (_stage)
        {
            case Stage.Repositories:
                ResetSelection();
                return;
            case Stage.Branches:
                _stage = Stage.Repositories;
                break;
            case Stage.Files:
                _stage = Stage.Branches;
                break;
            case Stage.Volumes:
                _stage = Stage.Files;
                break;
        }
        NotifyStageChanged();
    }

    public override async Task RefreshAsync()
    {
        switch (_stage)
        {
            case Stage.Repositories:
                _repositories = SettingsStore.Current.Repositories.ToList();
                OnPropertyChanged(nameof(Rows));
                break;
            case Stage.Branches:
                await LoadBranchesAsync();
                break;
            case Stage.Files:
                await LoadFilesAsync();
                break;
            case Stage.Volumes:
                IsLoading = true;
                _volumes = await Flasher.MountedUf2VolumesAsync();
                IsLoading = false;
                ErrorMessage = _volumes.Count == 0 ? "No UF2 drive found." : null;
                OnPropertyChanged(nameof(Rows));
                break;
        }
    }

    public override void ReturnToFilesStage()
    {
        _stage = Stage.Files;
        _file = null;
        _volumes.Clear();
        ErrorMessage = null;
        NotifyStageChanged();
    }

    private async Task LoadBranchesAsync()
    {
        if (_repository is null) return;
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var values = await GitHubFirmwareApi.BranchesAsync(
                _repository, TokenStore.EffectiveToken(_repository.Id));
            // default branch を先頭にピンする
            var index = values.IndexOf(_repository.DefaultBranch);
            if (index > 0)
            {
                var pinned = values[index];
                values.RemoveAt(index);
                values.Insert(0, pinned);
            }
            _branches = values;
            _stage = Stage.Branches;
            NotifyStageChanged();
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        IsLoading = false;
    }

    public async Task LoadFilesAsync(bool allowFallback = false)
    {
        if (_repository is null) return;
        IsLoading = true;
        ErrorMessage = null;
        try
        {
            var result = await GitHubFirmwareApi.LatestUf2FilesAsync(
                _repository, _branch, TokenStore.EffectiveToken(_repository.Id),
                allowLatestSuccessfulFallback: allowFallback);
            _files = result.Files;
            _commit = result.Commit;
            _fromCache = result.FromCache;
            _stage = Stage.Files;
            NotifyStageChanged();
        }
        catch (LatestRunNotSuccessfulException ex)
        {
            RunWarningRequested?.Invoke(ex.Message, ex.HasSuccessfulFallback);
        }
        catch (Exception ex)
        {
            ErrorMessage = ex.Message;
        }
        IsLoading = false;
    }

    private async Task LoadVolumesAsync()
    {
        IsLoading = true;
        _volumes = await Flasher.MountedUf2VolumesAsync();
        IsLoading = false;
        if (_volumes.Count == 0)
        {
            ErrorMessage = "Connect a UF2 drive, then press Ctrl+R to refresh.";
        }
        else
        {
            _stage = Stage.Volumes;
            ErrorMessage = null;
            NotifyStageChanged();
        }
    }
}
