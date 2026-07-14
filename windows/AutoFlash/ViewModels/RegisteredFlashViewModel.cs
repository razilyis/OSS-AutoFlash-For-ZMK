using AutoFlash.Models;
using AutoFlash.Services;

namespace AutoFlash.ViewModels;

// 登録済みローカル .uf2 の書き込みフロー(macOS版 RegisteredFlashStore の移植)。
// ステージ: files → volumes
public sealed class RegisteredFlashViewModel : FlashPanelViewModelBase
{
    private enum Stage { Files, Volumes }

    private Stage _stage = Stage.Files;
    private List<RegisteredFirmware> _firmwares = new();
    private List<Uf2Volume> _volumes = new();
    private RegisteredFirmware? _file;

    public override string Title => _stage switch
    {
        Stage.Files => "Select firmware to flash",
        _ => "Select a destination",
    };

    public override IReadOnlyList<FlashRow> Rows => _stage switch
    {
        Stage.Files => _firmwares
            .Select(f => new FlashRow(
                f.Name,
                f.FileExists ? f.FilePath : $"File not found: {f.FilePath}",
                Flasher.IsDangerous(f.FileName)))
            .ToList(),
        _ => _volumes.Select(v => new FlashRow(v.DisplayName, v.RootPath, false)).ToList(),
    };
    public override string BadgeGlyph => "";  // cpu 相当 (Segoe: Component)
    public override string StageGlyph => _stage == Stage.Files ? "" : "";  // Page / USB
    public override bool IsFirstStage => _stage == Stage.Files;
    public override string SwitchHint => "Tab GitHub Firmware";
    public override string HotKeyLabel => SettingsStore.HotKey(HotKeyAction.RegisteredFlash).Label;
    public override string FlashSuccessHint => "You can select the next firmware.";

    public override void Reset()
    {
        _firmwares = SettingsStore.Current.RegisteredFirmwares.ToList();
        _stage = Stage.Files;
        ErrorMessage = null;
        _volumes.Clear();
        _file = null;
        NotifyStageChanged();
    }

    public override async Task<FlashSelection?> SelectAsync()
    {
        if (SelectedIndex >= Rows.Count) return null;
        switch (_stage)
        {
            case Stage.Files:
                var firmware = _firmwares[SelectedIndex];
                if (!firmware.FileExists)
                {
                    ErrorMessage = $"File not found: {firmware.FilePath}";
                    return null;
                }
                _file = firmware;
                await LoadVolumesAsync();
                return null;
            default:
                if (_file is null) return null;
                var volume = _volumes[SelectedIndex];
                return new FlashSelection(_file.FilePath, volume, Flasher.IsDangerous(_file.FileName));
        }
    }

    public override void Back()
    {
        ErrorMessage = null;
        if (_stage == Stage.Volumes)
        {
            _stage = Stage.Files;
            NotifyStageChanged();
        }
        else
        {
            ResetSelection();
        }
    }

    public override async Task RefreshAsync()
    {
        switch (_stage)
        {
            case Stage.Files:
                _firmwares = SettingsStore.Current.RegisteredFirmwares.ToList();
                OnPropertyChanged(nameof(Rows));
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
        _volumes.Clear();
        ErrorMessage = null;
        NotifyStageChanged();
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
