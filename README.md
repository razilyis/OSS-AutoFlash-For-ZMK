# AutoFlash for ZMK

自作分割キーボード(ZMKファームウェア、UF2ブートローダー機)向けの、macOS用ファームウェア書き込みユーティリティです。メニューバーに常駐し、ホットキー1つでファームウェアを書き込めます。

機能はあえて2つだけに絞っています:

1. **登録ファイルFlash** — 事前に登録したローカルの`.uf2`ファイルを、ホットキー(初期値 `⌥⌘F`)一発で書き込む
2. **GitHub Firmware Flash** — 登録したGitHubリポジトリのGitHub Actions Artifactから最新の`.uf2`を自動ダウンロードして書き込む(初期値 `⌥⌘U`)

詳しい仕様は [spec.md](spec.md) を参照してください。

## スクリーンショット

(準備中)

## 動作環境

- macOS 15.0以降
- Swift 6 ツールチェーン(Xcode 16以降、または Swift 6 toolchain 単体)

## ビルド方法

```sh
git clone <このリポジトリのURL>
cd OSS-AutoFlash-For-ZMK
./scripts/make_app.sh
open "dist/AutoFlash for ZMK.app"
```

`swift build` だけでも実行バイナリは作れますが、メニューバーアイコンやログイン項目登録を正しく機能させるには `.app` バンドル化(`make_app.sh`)が必要です。

## GitHub Firmware Flashの設定

ZMKのファームウェアビルドは、GitHub Actionsのワークフロー実行ごとに`.uf2`をArtifactとして生成する運用が一般的です(GitHub Releaseのタグ付けは前提にしていません)。

1. アプリのメニューバーアイコン → 設定 → GitHub Firmware タブを開く
2. 対象リポジトリの [Fine-grained personal access token](https://github.com/settings/personal-access-tokens) を発行する
   - Repository access: 対象リポジトリのみ
   - Permissions: **Actions: Read-only**, **Contents: Read-only**
3. 発行したTokenを「共通GitHub Token」欄に貼り付ける(リポジトリごとに個別Tokenで上書きも可能)
4. 「GitHub Repositories」でリポジトリURL・Workflowファイル名(例: `build.yml`)・既定ブランチを登録する

以降は `⌥⌘U` → リポジトリ → ブランチ → UF2 → 書き込み先ボリューム、の順にキーボードだけで選択して書き込めます。

## 登録ファイルFlashの設定

1. 設定 → 登録ファイル タブを開く
2. 「ファイルを追加…」でローカルの`.uf2`ファイルを選択し、表示名を付ける
3. 左右分割キーボードの場合は左右それぞれを別項目として登録する

以降は `⌥⌘F` → 登録ファイル → 書き込み先ボリューム、の順に選択して書き込めます。

## UF2ブートローダーについて

nRF52/RP2040系のUF2ブートローダーは、マウントされたボリューム直下に`INFO_UF2.TXT`というファイルを必ず持ちます。本アプリはこれを検出条件として使い、対象ファイルをそのボリュームへコピーすることで書き込みを行います(コピー = 書き込み)。書き込み完了と同時にデバイスが再起動してボリュームがアンマウントされます。

## ライセンス

[MIT License](LICENSE)
