using System.ComponentModel;
using System.Runtime.CompilerServices;
using AutoFlash.Services;

namespace AutoFlash.ViewModels;

public sealed record FlashRow(string Title, string Subtitle, bool Warning);

// 最終ステージで決定されたときの書き込み内容。
public sealed record FlashSelection(string FilePath, Uf2Volume Volume, bool Dangerous);

// 2つのフラッシュパネル(GitHub / Registered)の共通ロジック。
// macOS版では FirmwareFlashStore と RegisteredFlashStore がほぼ同型だったため、
// Windows版では基底クラス + 単一の FlashPanelWindow に統合している。
public abstract class FlashPanelViewModelBase : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;

    protected FlashPanelViewModelBase()
    {
        SettingsStore.Changed += () =>
        {
            OnPropertyChanged(nameof(PanelOpacity));
            OnPropertyChanged(nameof(HotKeyLabel));
        };
    }

    protected void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));

    private int _selectedIndex;
    public int SelectedIndex
    {
        get => _selectedIndex;
        set
        {
            // ItemsSource 差し替え時に ListBox が -1 を書き戻してくるのは無視する
            if (value < 0 || value == _selectedIndex) return;
            _selectedIndex = value;
            OnPropertyChanged();
        }
    }

    private bool _isLoading;
    public bool IsLoading
    {
        get => _isLoading;
        protected set { _isLoading = value; OnPropertyChanged(); }
    }

    private string? _errorMessage;
    public string? ErrorMessage
    {
        get => _errorMessage;
        protected set
        {
            _errorMessage = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(HasError));
        }
    }

    public bool HasError => _errorMessage is not null;

    public double PanelOpacity => SettingsStore.Current.WindowOpacity;

    public abstract string Title { get; }
    public abstract IReadOnlyList<FlashRow> Rows { get; }
    public abstract string BadgeGlyph { get; }
    public abstract string StageGlyph { get; }
    public abstract bool IsFirstStage { get; }
    public abstract string SwitchHint { get; }
    public abstract string HotKeyLabel { get; }
    // フラッシュ成功 HUD の後半文言("You can select the next UF2." 等)
    public abstract string FlashSuccessHint { get; }

    public abstract void Reset();
    public abstract Task<FlashSelection?> SelectAsync();
    public abstract void Back();
    public abstract Task RefreshAsync();
    // 書き込み成功後にファイル選択ステージへ戻す(パネルは開いたまま連続書き込みできる)
    public abstract void ReturnToFilesStage();

    public void Move(int delta)
    {
        var count = Rows.Count;
        SelectedIndex = Math.Min(Math.Max(0, _selectedIndex + delta), Math.Max(0, count - 1));
    }

    protected void ResetSelection()
    {
        _selectedIndex = 0;
        OnPropertyChanged(nameof(SelectedIndex));
    }

    // ステージ遷移後にタイトル・行・アイコンをまとめて更新する
    protected void NotifyStageChanged()
    {
        ResetSelection();
        OnPropertyChanged(nameof(Title));
        OnPropertyChanged(nameof(Rows));
        OnPropertyChanged(nameof(StageGlyph));
        OnPropertyChanged(nameof(IsFirstStage));
    }
}
