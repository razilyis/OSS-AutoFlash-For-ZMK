# AutoFlash for ZMK

自作分割キーボード(ZMKファームウェア、UF2ブートローダー機)向けのファームウェア書き込みユーティリティです。macOSではメニューバー常駐、Windowsではシステムトレイ常駐として動作します。

コンセプトは「マウスに一切触れずファームウェアを書き込めること」。ホットキーを押し、矢印キーでリストを選び、Returnで決定するだけ。ファイラーもドラッグ&ドロップもGUIのクリック操作も不要です。

English: [README.md](README.md)

機能はあえて2つだけに絞っています:

1. **Registered File Flash(登録ファイルFlash)** — 事前に登録したローカルの`.uf2`ファイルをホットキー一発で書き込む
2. **GitHub Firmware Flash** — 登録したGitHubリポジトリのGitHub Actions Artifactから最新の`.uf2`を自動ダウンロードして書き込む

デフォルトのキー割り当て(設定 → Hotkeys で変更可能):

| 操作 | macOS | Windows |
| --- | --- | --- |
| GitHub Firmware Flash | `⌥⌘U` | `Ctrl+Alt+U` |
| Registered File Flash | `⌥⌘F` | `Ctrl+Alt+R` |
| 更新(パネル内) | `⌘R` | `Ctrl+R` |
| 設定を開く(パネル内) | `⌘K` | `Ctrl+K` |
| 戻る / 閉じる | `Esc` | `Esc` |
| 2つのパネルの切り替え | `Tab` | `Tab` |

## 免責事項

本アプリはキーボードのブートローダーへ直接書き込みを行います。**利用は完全に自己責任でお願いします。** 本アプリの使用によって生じた不具合、故障、ハードウェアの起動不能、データ損失などについて、作者は一切の保証を行わず、責任を負いません。詳細は [LICENSE](LICENSE) の"AS IS"条項を参照してください。

## スクリーンショット

| リポジトリ選択 | ブランチ選択 |
| --- | --- |
| ![リポジトリ選択](docs/screenshots/repository-select.png) | ![ブランチ選択](docs/screenshots/branch-select.png) |

## 動作環境

### macOS

- macOS 15.0以降
- ソースからビルドする場合のみ: Swift 6 ツールチェーン(Xcode 16以降、または Swift 6 toolchain 単体)。リリース版をダウンロードするだけなら不要です。

### Windows

- Windows 10 21H2以降(アイコングリフの見た目はWindows 11推奨)
- ソースからビルドする場合のみ: .NET 8 SDK以降。リリース版は自己完結型の単一exeなので、ダウンロードするだけなら不要です。

## インストール

### macOS — リリース版をダウンロードする場合

[Releases](../../releases) ページから `.dmg` をダウンロードして開き、`AutoFlash for ZMK.app` を `Applications` へドラッグしてください。ツールチェーンのセットアップは不要で、macOS 15.0以降だけで動作します。

本アプリはローカルの自己署名証明書で署名されており、Apple公証(notarization)は受けていません。ネットからダウンロードしたファイルにはmacOSが隔離属性(quarantine)を付けるため、通常のダブルクリックでは「開発元が未確認」としてGatekeeperにブロックされます。**初回のみアプリを右クリック(またはControlキーを押しながらクリック)→「開く」**で起動してください。それ以降は通常通りダブルクリックで起動できます。

### Windows — リリース版をダウンロードする場合

[Releases](../../releases) ページから `AutoFlashForZMK-win-x64-<version>.zip` をダウンロードし、任意の場所に展開して `AutoFlash.exe` を実行してください。アプリはシステムトレイ(通知領域)に常駐します。

exeにはコード署名がないため、初回起動時にMicrosoft Defender SmartScreenが「発行元不明」の警告を出すことがあります。**「詳細情報」→「実行」**で起動してください。それ以降は通常通り起動できます。なお、設定の「Launch at login(ログイン時に起動)」はexeの現在のパスを登録するため、exeを移動した場合は設定し直してください。

### macOS — ソースからビルドする場合

Swift 6 ツールチェーンが必要です(上記の動作環境を参照)。

```sh
git clone <このリポジトリのURL>
cd OSS-AutoFlash-For-ZMK
./scripts/macos/make_app.sh
open "dist/AutoFlash for ZMK.app"
```

`swift build` だけでも実行バイナリは作れますが、メニューバーアイコンやログイン項目登録を正しく機能させるには `.app` バンドル化(`scripts/macos/make_app.sh`)が必要です。配布用に`.dmg`を作る場合は `./scripts/macos/make_dmg.sh` を実行してください。

`make_app.sh` はデフォルトで `AutoFlash for ZMK Dev` という名前のローカル証明書で署名します。この証明書は事前にKeychain Access(キーチェーンアクセス)→ 証明書アシスタント → 証明書を作成 → 種類「コード署名」で作成しておく必要があります。固定の証明書を使うことで、再ビルドしてもアプリの識別子が変わらず、Keychainのアクセス許可(GitHubトークンの読み取りなど)が毎回リセットされるのを防げます。証明書を作りたくない場合は `CODESIGN_IDENTITY=- ./scripts/macos/make_app.sh` でAd-hoc署名にできます(その場合、再ビルドのたびにKeychainの確認ダイアログが再び出るようになります)。別名の証明書を使う場合は `CODESIGN_IDENTITY=<証明書名>` を指定してください。

### Windows — ソースからビルドする場合

.NET 8 SDK以降が必要です。

```powershell
git clone <このリポジトリのURL>
cd OSS-AutoFlash-For-ZMK
./scripts/windows/publish.ps1
# → dist/windows/AutoFlash.exe と dist/AutoFlashForZMK-win-x64-<version>.zip
```

開発時は `dotnet run --project windows/AutoFlash` でも起動できます。Windows版は [windows/](windows/) 配下のWPFプロジェクトで、macOS版と同じ挙動になるよう実装されています。

## GitHub Firmware Flashの設定

ZMKのファームウェアビルドは、GitHub Actionsのワークフロー実行ごとに`.uf2`をArtifactとして生成する運用が一般的です(GitHub Releaseのタグ付けは前提にしていません)。

1. メニューバー/トレイのアイコン → 設定 → **GitHub Firmware** タブを開く
2. Fine-grained personal access tokenを発行する:
   1. [github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens) (GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens) を開き、**Generate new token** をクリック
   2. **Token name**: 分かりやすい名前(例: `AutoFlash for ZMK`)
   3. **Expiration(有効期限)**: 任意。短くすると安全ですが、期限切れのたびに再発行してAutoFlashに貼り直す必要があります。好みで選んでください
   4. **Resource owner**: 自分のアカウント(対象リポジトリが組織(Organization)所有の場合はその組織)
   5. **Repository access**: **Only select repositories** を選び、AutoFlashに登録するリポジトリだけを選択する(不要なリポジトリへのアクセスは与えない)
   6. **Permissions → Repository permissions**: **Actions** を **Read-only**、**Contents** を **Read-only** に設定。それ以外は **No access** のままにする
   7. **Generate token** をクリックし、**表示された直後にコピーする**(`github_pat_…` で始まるトークンはこの時しか全文表示されません)
   8. 組織所有のリポジトリでFine-grainedトークンに制限がかかっている場合、組織の管理者による承認が必要になることがあります
3. 発行したTokenを「GitHub Personal Access Token」欄に貼り付ける(リポジトリごとに個別Tokenで上書きも可能)。TokenはmacOSのKeychain / WindowsのCredential Managerに保存されます
4. 「GitHub Repositories」で、**Fetch from GitHub…** ボタンからTokenがアクセスできるリポジトリ一覧を選んで登録するか(登録済みのものには印が付きます)、リポジトリURL・Workflowファイル名(例: `build.yml`)・既定ブランチを手動で登録する

以降はホットキー(`⌥⌘U` / `Ctrl+Alt+U`)→ リポジトリ → ブランチ → UF2 → 書き込み先ボリューム、の順にキーボードだけで選択して書き込めます。書き込み成功後もパネルは閉じないので、左右分割のもう片側を続けて書き込めます。

### Artifactのキャッシュについて

ダウンロード・展開したUF2ファイルは、ワークフロー実行ID(run ID)をキーにシステムの一時ディレクトリ(Windowsでは `%TEMP%\AutoFlashForZMK\`)へキャッシュされます。対象ブランチの最新の成功runが前回と変わっていなければ、GitHubへ再ダウンロードせずキャッシュを再利用します。ただし保存先は一時ディレクトリのため永続保管ではなく、OSの再起動や定期クリーンアップで消えることがあります。その場合は自動的に再ダウンロードされます。

## 登録ファイルFlashの設定

1. 設定 → **Registered Files** タブを開く
2. 「Add File…」でローカルの`.uf2`ファイルを選択し、表示名を付ける
3. 左右分割キーボードの場合は左右それぞれを別項目として登録する

以降はホットキー(`⌥⌘F` / `Ctrl+Alt+R`)→ 登録ファイル → 書き込み先ボリューム、の順に選択して書き込めます。こちらも書き込み成功後にファイル一覧へ戻るため、連続して書き込めます。

## UF2ブートローダーについて

nRF52/RP2040系のUF2ブートローダーは、マウントされたボリューム直下に`INFO_UF2.TXT`というファイルを必ず持ちます。本アプリはこれを検出条件として使い、対象ファイルをそのボリュームへコピーすることで書き込みを行います(コピー = 書き込み)。書き込み完了と同時にデバイスが再起動してボリュームがアンマウントされます。

## ライセンス

[MIT License](LICENSE)
