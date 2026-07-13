# AutoFlash for ZMK

自作分割キーボード(ZMKファームウェア、UF2ブートローダー機)向けの、macOS用ファームウェア書き込みユーティリティです。メニューバーに常駐し、ホットキー1つでファームウェアを書き込めます。

English: [README.md](README.md)

機能はあえて2つだけに絞っています:

1. **Registered File Flash(登録ファイルFlash)** — 事前に登録したローカルの`.uf2`ファイルを、ホットキー(初期値 `⌥⌘F`)一発で書き込む
2. **GitHub Firmware Flash** — 登録したGitHubリポジトリのGitHub Actions Artifactから最新の`.uf2`を自動ダウンロードして書き込む(初期値 `⌥⌘U`)

## 免責事項

本アプリはキーボードのブートローダーへ直接書き込みを行います。**利用は完全に自己責任でお願いします。** 本アプリの使用によって生じた不具合、故障、ハードウェアの起動不能、データ損失などについて、作者は一切の保証を行わず、責任を負いません。詳細は [LICENSE](LICENSE) の"AS IS"条項を参照してください。

## スクリーンショット

| リポジトリ選択 | ブランチ選択 |
| --- | --- |
| ![リポジトリ選択](docs/screenshots/repository-select.png) | ![ブランチ選択](docs/screenshots/branch-select.png) |

## 動作環境

- macOS 15.0以降
- Swift 6 ツールチェーン(Xcode 16以降、または Swift 6 toolchain 単体)

## インストール

### リリース版をダウンロードする場合

[Releases](../../releases) ページから `.dmg` をダウンロードして開き、`AutoFlash for ZMK.app` を `Applications` へドラッグしてください。

本アプリはAd-hoc署名(`codesign --sign -`)のみで、Apple公証(notarization)は受けていません。ネットからダウンロードしたファイルにはmacOSが隔離属性(quarantine)を付けるため、通常のダブルクリックでは「開発元が未確認」としてGatekeeperにブロックされます。**初回のみアプリを右クリック(またはControlキーを押しながらクリック)→「開く」**で起動してください。それ以降は通常通りダブルクリックで起動できます。

### ソースからビルドする場合

```sh
git clone <このリポジトリのURL>
cd OSS-AutoFlash-For-ZMK
./scripts/macos/make_app.sh
open "dist/AutoFlash for ZMK.app"
```

`swift build` だけでも実行バイナリは作れますが、メニューバーアイコンやログイン項目登録を正しく機能させるには `.app` バンドル化(`scripts/macos/make_app.sh`)が必要です。配布用に`.dmg`を作る場合は `./scripts/macos/make_dmg.sh` を実行してください。

## GitHub Firmware Flashの設定

ZMKのファームウェアビルドは、GitHub Actionsのワークフロー実行ごとに`.uf2`をArtifactとして生成する運用が一般的です(GitHub Releaseのタグ付けは前提にしていません)。

1. アプリのメニューバーアイコン → 設定 → **GitHub Firmware** タブを開く
2. 対象リポジトリの [Fine-grained personal access token](https://github.com/settings/personal-access-tokens) を発行する
   - Repository access: 対象リポジトリのみ
   - Permissions: **Actions: Read-only**, **Contents: Read-only**
3. 発行したTokenを「GitHub Personal Access Token」欄に貼り付ける(リポジトリごとに個別Tokenで上書きも可能)
4. 「GitHub Repositories」でリポジトリURL・Workflowファイル名(例: `build.yml`)・既定ブランチを登録する

以降は `⌥⌘U` → リポジトリ → ブランチ → UF2 → 書き込み先ボリューム、の順にキーボードだけで選択して書き込めます。書き込み成功後もパネルは閉じないので、左右分割のもう片側を続けて書き込めます。

### Artifactのキャッシュについて

ダウンロード・展開したUF2ファイルは、ワークフロー実行ID(run ID)をキーにシステムの一時ディレクトリへキャッシュされます。対象ブランチの最新の成功runが前回と変わっていなければ、GitHubへ再ダウンロードせずキャッシュを再利用します。ただし保存先は一時ディレクトリのため永続保管ではなく、macOSの再起動や定期クリーンアップで消えることがあります。その場合は自動的に再ダウンロードされます。

## 登録ファイルFlashの設定

1. 設定 → **Registered Files** タブを開く
2. 「Add File…」でローカルの`.uf2`ファイルを選択し、表示名を付ける
3. 左右分割キーボードの場合は左右それぞれを別項目として登録する

以降は `⌥⌘F` → 登録ファイル → 書き込み先ボリューム、の順に選択して書き込めます。こちらも書き込み成功後にファイル一覧へ戻るため、連続して書き込めます。

## UF2ブートローダーについて

nRF52/RP2040系のUF2ブートローダーは、マウントされたボリューム直下に`INFO_UF2.TXT`というファイルを必ず持ちます。本アプリはこれを検出条件として使い、対象ファイルをそのボリュームへコピーすることで書き込みを行います(コピー = 書き込み)。書き込み完了と同時にデバイスが再起動してボリュームがアンマウントされます。

## ライセンス

[MIT License](LICENSE)
