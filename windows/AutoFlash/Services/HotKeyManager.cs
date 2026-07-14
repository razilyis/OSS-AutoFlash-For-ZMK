using System.Runtime.InteropServices;
using System.Windows.Interop;
using AutoFlash.Models;

namespace AutoFlash.Services;

// RegisterHotKey によるグローバルホットキー(macOS版 HotKeyCenter の移植)。
// ID(文字列)単位で登録し、ハンドラを保ったままキーの差し替えができる。
// WM_HOTKEY はメッセージ専用ウィンドウで受ける。
public sealed class HotKeyManager
{
    public static HotKeyManager Shared { get; } = new();

    private const int WmHotKey = 0x0312;
    private const uint ModNoRepeat = 0x4000;
    private static readonly IntPtr HwndMessage = new(-3);

    private sealed class Registration
    {
        public required int NumericId { get; init; }
        public required Action Handler { get; init; }
        public required KeyCombo Combo { get; set; }
        public bool Active { get; set; }
    }

    private readonly Dictionary<string, Registration> _registrations = new();
    private readonly Dictionary<int, string> _idsByNumericId = new();
    private int _nextNumericId = 1;
    private readonly HwndSource _source;

    private HotKeyManager()
    {
        var parameters = new HwndSourceParameters("AutoFlashHotKeys")
        {
            WindowStyle = 0,
            ParentWindow = HwndMessage,
        };
        _source = new HwndSource(parameters);
        _source.AddHook(WndProc);
    }

    // 失敗しても登録情報は保持する(後から設定画面の UpdateKey で別のキーに差し替えられるように)。
    public bool Register(string id, KeyCombo combo, Action handler)
    {
        if (_registrations.TryGetValue(id, out var existing) && existing.Active)
        {
            UnregisterHotKey(_source.Handle, existing.NumericId);
        }
        var numericId = existing?.NumericId ?? _nextNumericId++;
        var active = RegisterHotKey(_source.Handle, numericId, combo.Modifiers | ModNoRepeat, combo.VirtualKey);
        _registrations[id] = new Registration
        {
            NumericId = numericId, Handler = handler, Combo = combo, Active = active,
        };
        _idsByNumericId[numericId] = id;
        return active;
    }

    // 既存ハンドラを保ったままキーだけ差し替える。失敗時は元のキーに戻して false を返す。
    public bool UpdateKey(string id, KeyCombo combo)
    {
        if (!_registrations.TryGetValue(id, out var registration)) return false;

        if (registration.Active)
        {
            UnregisterHotKey(_source.Handle, registration.NumericId);
            registration.Active = false;
        }

        if (RegisterHotKey(_source.Handle, registration.NumericId, combo.Modifiers | ModNoRepeat, combo.VirtualKey))
        {
            registration.Combo = combo;
            registration.Active = true;
            return true;
        }

        // 失敗: 元のキーで再登録して状態を戻す
        registration.Active = RegisterHotKey(
            _source.Handle, registration.NumericId,
            registration.Combo.Modifiers | ModNoRepeat, registration.Combo.VirtualKey);
        return false;
    }

    // レコーダーでのキー入力中に既存ホットキーが発火しないよう一時停止する
    public void PauseAll()
    {
        foreach (var registration in _registrations.Values)
        {
            if (!registration.Active) continue;
            UnregisterHotKey(_source.Handle, registration.NumericId);
            registration.Active = false;
        }
    }

    public void ResumeAll()
    {
        foreach (var registration in _registrations.Values)
        {
            if (registration.Active) continue;
            registration.Active = RegisterHotKey(
                _source.Handle, registration.NumericId,
                registration.Combo.Modifiers | ModNoRepeat, registration.Combo.VirtualKey);
        }
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmHotKey && _idsByNumericId.TryGetValue(wParam.ToInt32(), out var id))
        {
            _registrations[id].Handler();
            handled = true;
        }
        return IntPtr.Zero;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
