namespace AutoFlash.Services;

// 二重起動防止。Mutex はプロセス生存中ずっと保持する。
public static class SingleInstance
{
    private static Mutex? _mutex;

    public static bool TryAcquire()
    {
        _mutex = new Mutex(initiallyOwned: true, @"Local\AutoFlashForZMK_SingleInstance", out var createdNew);
        return createdNew;
    }
}
