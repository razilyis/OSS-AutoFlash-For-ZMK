using Meziantou.Framework.Win32;

namespace AutoFlash.Services;

// GitHub Personal Access Token の保存(macOS版 FirmwareTokenStore の移植)。
// Windows Credential Manager に「共通トークン」と「リポジトリ別の上書きトークン」を保存する。
public static class TokenStore
{
    private const string Service = "com.autoflash.zmk.github-firmware";
    private const string CommonAccount = "common";

    public static string CommonToken
    {
        get => Get(CommonAccount);
        set => Set(CommonAccount, value);
    }

    // リポジトリ別トークンが空なら共通トークンを使う
    public static string EffectiveToken(Guid repositoryId)
    {
        var overrideToken = Token(repositoryId);
        return overrideToken.Length == 0 ? CommonToken : overrideToken;
    }

    public static string Token(Guid repositoryId) => Get(repositoryId.ToString());

    public static void SetToken(Guid repositoryId, string token) => Set(repositoryId.ToString(), token);

    public static void RemoveToken(Guid repositoryId) => Delete(repositoryId.ToString());

    private static string TargetName(string account) => $"{Service}/{account}";

    private static string Get(string account)
    {
        try
        {
            return CredentialManager.ReadCredential(TargetName(account))?.Password ?? "";
        }
        catch (Exception)
        {
            return "";
        }
    }

    private static void Set(string account, string token)
    {
        if (string.IsNullOrEmpty(token))
        {
            Delete(account);
            return;
        }
        CredentialManager.WriteCredential(
            TargetName(account), "AutoFlashForZMK", token, CredentialPersistence.LocalMachine);
    }

    private static void Delete(string account)
    {
        try
        {
            CredentialManager.DeleteCredential(TargetName(account));
        }
        catch (Exception)
        {
            // 未保存なら何もしない
        }
    }
}
