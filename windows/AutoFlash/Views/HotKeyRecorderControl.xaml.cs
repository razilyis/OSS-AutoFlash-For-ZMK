using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AutoFlash.Models;
using AutoFlash.Services;

namespace AutoFlash.Views;

// ホットキー1件分のレコーダー行(macOS版 HotKeyRecorderRow の移植)。
// クリック → 修飾キーを含む組み合わせを押して割り当て。Esc でキャンセル。
public partial class HotKeyRecorderControl : UserControl
{
    private HotKeyAction _action;
    private bool _recording;

    public HotKeyRecorderControl()
    {
        InitializeComponent();
    }

    public void Initialize(HotKeyAction action)
    {
        _action = action;
        TitleText.Text = action.Title();
        ComboButton.Content = SettingsStore.HotKey(action).Label;
        ResetButton.ToolTip = $"Reset to default ({action.DefaultCombo().Label})";
    }

    private void OnComboClick(object sender, RoutedEventArgs e)
    {
        if (_recording) CancelRecording();
        else StartRecording();
    }

    private void StartRecording()
    {
        SetError(null);
        _recording = true;
        ComboButton.Content = "Press a key…";
        // 記録中は既存ホットキーが発火しないよう一時停止する
        HotKeyManager.Shared.PauseAll();
        ComboButton.Focus();
        Keyboard.Focus(ComboButton);
    }

    private void OnComboKeyDown(object sender, KeyEventArgs e)
    {
        if (!_recording) return;
        e.Handled = true;

        // Alt を含む組み合わせは Key.System 経由で届く
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key == Key.Escape)
        {
            CancelRecording();
            return;
        }
        if (IsModifierKey(key)) return;

        var modifiers = ToHotKeyModifiers(Keyboard.Modifiers);
        // Shift 単独は不可。Ctrl / Alt / Win のいずれかを必須にする(macOS版の ⌘/⌥/⌃ 必須と対応)
        if ((modifiers & (KeyCombo.ModControl | KeyCombo.ModAlt | KeyCombo.ModWin)) == 0)
        {
            SetError("Combination must include Ctrl, Alt, or Win.");
            return;
        }

        var combo = new KeyCombo
        {
            VirtualKey = (uint)KeyInterop.VirtualKeyFromKey(key),
            Modifiers = modifiers,
            Label = KeyCombo.BuildLabel(modifiers, KeyName(key)),
        };

        _recording = false;
        if (HotKeyManager.Shared.UpdateKey(_action.Id(), combo))
        {
            SettingsStore.SetHotKey(_action, combo);
            ComboButton.Content = combo.Label;
            SetError(null);
        }
        else
        {
            ComboButton.Content = SettingsStore.HotKey(_action).Label;
            SetError("Couldn't register this combination (it conflicts with another hotkey or app).");
        }
        HotKeyManager.Shared.ResumeAll();
    }

    private void OnComboLostFocus(object sender, KeyboardFocusChangedEventArgs e)
    {
        if (_recording) CancelRecording();
    }

    private void OnResetClick(object sender, RoutedEventArgs e)
    {
        CancelRecording();
        var defaultCombo = _action.DefaultCombo();
        if (HotKeyManager.Shared.UpdateKey(_action.Id(), defaultCombo))
        {
            SettingsStore.ResetHotKey(_action);
            ComboButton.Content = defaultCombo.Label;
            SetError(null);
        }
        else
        {
            SetError("Couldn't reset to default (conflicts with another hotkey).");
        }
    }

    private void CancelRecording()
    {
        if (!_recording) return;
        _recording = false;
        ComboButton.Content = SettingsStore.HotKey(_action).Label;
        HotKeyManager.Shared.ResumeAll();
    }

    private void SetError(string? message)
    {
        ErrorText.Text = message ?? "";
        ErrorText.Visibility = message is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private static bool IsModifierKey(Key key) => key is
        Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or
        Key.LeftShift or Key.RightShift or Key.LWin or Key.RWin;

    private static uint ToHotKeyModifiers(ModifierKeys modifiers)
    {
        uint value = 0;
        if (modifiers.HasFlag(ModifierKeys.Control)) value |= KeyCombo.ModControl;
        if (modifiers.HasFlag(ModifierKeys.Alt)) value |= KeyCombo.ModAlt;
        if (modifiers.HasFlag(ModifierKeys.Shift)) value |= KeyCombo.ModShift;
        if (modifiers.HasFlag(ModifierKeys.Windows)) value |= KeyCombo.ModWin;
        return value;
    }

    private static string KeyName(Key key) => key switch
    {
        >= Key.A and <= Key.Z => key.ToString(),
        >= Key.D0 and <= Key.D9 => key.ToString()[1..],
        >= Key.NumPad0 and <= Key.NumPad9 => "Num" + key.ToString()[^1..],
        >= Key.F1 and <= Key.F24 => key.ToString(),
        Key.Space => "Space",
        Key.Return => "Enter",
        Key.Tab => "Tab",
        Key.Back => "Backspace",
        Key.Delete => "Delete",
        Key.Insert => "Insert",
        Key.Home => "Home",
        Key.End => "End",
        Key.PageUp => "PageUp",
        Key.PageDown => "PageDown",
        Key.Up => "Up",
        Key.Down => "Down",
        Key.Left => "Left",
        Key.Right => "Right",
        Key.OemComma => ",",
        Key.OemPeriod => ".",
        Key.OemMinus => "-",
        Key.OemPlus => "+",
        _ => key.ToString(),
    };
}
