---
type: spec
project: terra-town
doc: 開発環境セットアップ手順
status: approved
created: 2026-07-30
updated: 2026-07-30
related:
  - specs/001-mvp/plan.md
  - specs/001-mvp/tasks.md
---

# terra-town — 開発環境セットアップ

> `specs/001-mvp/tasks.md` の **T001・T010** に対応する。
> 技術スタックの決定は `specs/001-mvp/plan.md`（ゲート②承認済み）を正とする。

## 1. インストール先の決定（2026-07-30 代表判断）

**Flutter SDK は WSL（Ubuntu 24.04）側に導入する。**

| 選択肢 | 判断 |
|--------|------|
| **WSL に導入（採用）** | リポジトリ（`~/terra-town`）と po_agent の日次自動化がすでに WSL 側にあり、それをそのまま維持できる |
| Windows に導入 | 既存の Android Studio/エミュレータを活かせるが、リポジトリを Windows 側へ移す必要があり、WSL の自動化と二重管理になる |

**WSL の弱点（エミュレータ・USB 接続）が実害になりにくい理由**: 本作は GPS 位置情報ゲームであり、
`plan.md` §15 のバーティカルスライス完了条件が「実際に30分歩いて…」である以上、
検証は**実機を屋外で歩かせる**のが前提になる。エミュレータの重要度が低い。

## 2. 導入済みのバージョン（2026-07-30 時点の実測）

| 項目 | バージョン / パス |
|------|------------------|
| Flutter | 3.44.8（channel stable） |
| Dart | 3.12.2 |
| Flutter SDK パス | `~/flutter` |
| Android SDK パス | `~/Android/Sdk` |
| Android SDK Platform | android-36 |
| Android SDK Build-Tools | 37.0.0 |
| Android SDK Platform-Tools | 37.0.0 |
| JDK | OpenJDK 17.0.11（sdkman 管理） |

`flutter doctor` の結果:

- ✅ Flutter
- ✅ Android toolchain
- ✅ Network resources
- ❌ Chrome / Linux desktop → **本プロジェクトでは不要**（Android 先行のモバイルアプリのため）

## 3. セットアップ手順（新しい環境で再現する場合）

sudo は不要。すべてホーム配下に入れる。

```bash
# 1. Flutter SDK（stable）
git clone --depth 1 -b stable https://github.com/flutter/flutter.git ~/flutter
export PATH="$HOME/flutter/bin:$PATH"
flutter --version   # 初回に Dart SDK をダウンロードする

# 2. Android cmdline-tools
#    最新の URL は https://developer.android.com/studio の
#    "Command line tools only" セクションから取得する
mkdir -p ~/Android/Sdk/cmdline-tools
curl -sSL -o /tmp/clt.zip \
  "https://dl.google.com/android/repository/commandlinetools-linux-<BUILD>_latest.zip"
unzip -q /tmp/clt.zip -d /tmp/clt
mv /tmp/clt/cmdline-tools ~/Android/Sdk/cmdline-tools/latest

export ANDROID_HOME="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

# 3. SDK パッケージ
sdkmanager --install "platform-tools" "platforms;android-36" "build-tools;37.0.0"

# 4. ライセンス同意
flutter config --android-sdk "$ANDROID_HOME"
flutter doctor --android-licenses   # すべて y

# 5. 確認
flutter doctor
```

### つまずきポイント（実際に踏んだもの）

- **`yes | sdkmanager ... > /dev/null 2>&1` は使わない。** SIGPIPE（exit 141）になるうえ、
  出力を捨てると失敗が見えなくなる。ライセンス同意は `flutter doctor --android-licenses` を使う。
- **`sdkmanager --list` の grep で platform を自動判定しない。** 実在しない `platforms;android-37` を
  拾ってしまい `Failed to find package` になった。導入可能な最新は **android-36**（2026-07-30 時点）。
- **`dart create --no-pub` は使わない。** クラッシュする。`--no-pub` なしで実行する。
- sdkmanager は deprecated 警告を出すが、現時点では動作する（将来 `android` CLI へ移行）。

## 4. PATH の永続化

`~/.bashrc` に以下が追記済み（マーカー `# >>> terra-town flutter env >>>` で囲まれている）:

```bash
export FLUTTER_HOME="$HOME/flutter"
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$FLUTTER_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"
```

## 5. 実機接続（WSL から Android 実機へ）

WSL からは USB が直接見えないため、**Android 11 以上のワイヤレスデバッグ**を使う。

```bash
# 端末側: 開発者オプション > ワイヤレスデバッグ を ON にしてペア設定
adb pair <端末のIP>:<ペアリングポート>
adb connect <端末のIP>:<接続ポート>
adb devices          # 接続を確認
flutter devices
flutter run -d <deviceId>
```

USB 接続が必要な場合は Windows 側に `usbipd-win` を導入して WSL へアタッチする。

## 6. リポジトリ構成と依存方向

```
terra-town/
├── app/                 # Flutter アプリ（composition root）
│   └── android/         # Kotlin ネイティブ（foreground service 等）
├── packages/
│   ├── core/            # terra_town_core：純粋 Dart。GPS/地図/Flutter に依存しない
│   └── location/        # terra_town_location：GPS・地図。core を実装する
└── tools/
    └── check_import_direction.sh   # 依存方向を CI で機械的に強制
```

- **依存方向は `location -> core` の一方向**（`GPS_ARCHITECTURE.md`・plan.md §1-D）。
  `app` は composition root として両方に依存してよい。
- **パッケージ名について**: ディレクトリは plan.md §2 のとおり `packages/core` / `packages/location` だが、
  pub のパッケージ名は **`terra_town_core` / `terra_town_location`** とした。
  理由 = `location` は pub.dev に同名の実在パッケージ（位置情報プラグイン）があり、
  将来それを依存に加えたときに名前が衝突するため。
- **`android/` の配置**: plan.md §2 のツリーはリポジトリ直下に `android/` を置いているが、
  `flutter create` の標準に合わせて **`app/android/`** とした。plan.md §2 は要追記修正。

## 7. よく使うコマンド

```bash
# 依存解決
flutter pub get -C packages/core
flutter pub get -C packages/location
flutter pub get -C app

# 静的解析
flutter analyze packages/core packages/location app

# テスト（core は Flutter なしで回る）
cd packages/core && dart test
cd app && flutter test

# 依存方向チェック
bash tools/check_import_direction.sh

# デバッグビルド
cd app && flutter build apk --debug
```

## 8. 未確定事項

- **applicationId が `jp.rokusoudo.terra_town` で仮置き**（`app/android/app/build.gradle.kts`）。
  Google Play では**公開後に変更できない**ため、初回リリース前に代表が確定すること。
- Flutter 地図プラグインの選定は未着手（tasks.md T011・plan.md §16）。
