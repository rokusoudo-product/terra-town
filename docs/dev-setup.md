---
type: spec
project: terra-town
doc: 開発環境セットアップ手順
status: approved
created: 2026-07-30
updated: 2026-09-08
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

## 2. 導入済みのバージョン（2026-07-30 時点の実測、JDK 行のみ 2026-09-08 に実態へ更新）

| 項目 | バージョン / パス |
|------|------------------|
| Flutter | 3.44.8（channel stable） |
| Dart | 3.12.2 |
| Flutter SDK パス | `~/flutter` |
| Android SDK パス | `~/Android/Sdk` |
| Android SDK Platform | android-36 |
| Android SDK Build-Tools | 37.0.0 |
| Android SDK Platform-Tools | 37.0.0 |
| JDK | OpenJDK 21.0.12（Ubuntu 24.04 システムパッケージ `openjdk-21-jdk-headless`。`/usr/bin/java` → `update-alternatives` 経由。詳細・sdkman との関係は下記注記） |

`flutter doctor` の結果:

- ✅ Flutter
- ✅ Android toolchain
- ✅ Network resources
- ❌ Chrome / Linux desktop → **本プロジェクトでは不要**（Android 先行のモバイルアプリのため）

**CI（`.github/workflows/ci.yml`）はこの表の Flutter / JDK バージョンを固定値として参照している。**
Flutter バージョンを上げる（例: stable channel の更新に追従する）場合は、
`ci.yml` の `flutter-version` とこの表を **同じ PR で** 更新すること。片方だけ更新すると、
ローカルと CI で異なるバージョンのまま乖離する。
この乖離は `tools/check_toolchain_versions.sh` が CI で機械的に検出する（Issue #59）。
**正本（enforced value）は `ci.yml` 側であり、乖離時はこの表を `ci.yml` の値に合わせて修正すること。**

### ⚠️ JDK 行の実態（2026-09-08 確認・sdkman の記述は現状と合っていなかった）

本表の JDK 行は従来「OpenJDK 17.0.11（sdkman 管理）」としていたが、2026-09-08 に
`java -version` を実際に確認したところ **OpenJDK 21.0.12** だった。調査の結果、
「sdkman 管理」という記述はもはや正確ではなく、次の2系統が併存している状態だと判明した。

- **対話シェル（`bash -i` など、人間が WSL ターミナルを開いて作業する場合）**: `~/.bashrc` の
  sdkman 初期化行（`sdkman-init.sh`）が実行され、`java` は sdkman 管理の
  **17.0.11-tem**（`~/.sdkman/candidates/java/current` が指す版）に解決される。
- **非対話シェル（`bash -lc "..."` など。CI・エージェント（po_agent 等）からの実行はすべてこちら）**:
  Ubuntu の `.bashrc` 冒頭にある非対話ガード（`case $- in *i*) ;; *) return;; esac`）により
  sdkman の初期化行に到達せず、`java` は `update-alternatives` が指す
  **Ubuntu 24.04 システムパッケージの OpenJDK 21.0.12**（`openjdk-21-jdk-headless`、
  `/usr/bin/java` → `/etc/alternatives/java` → `/usr/lib/jvm/java-21-openjdk-amd64`）に解決される。

**これが Blocker B の混乱の原因そのものだった**（詳細: `specs/001-mvp/research.md` §6.1）。
前任のエージェントが最初に「ローカルでビルド成功」と報告したのは非対話シェル経由で
JDK21 に偶然フォールバックしていたためで、対話シェル相当の sdkman JDK17 を明示的に
使って再現するとCIと同じ `invalid source release: 21` で失敗した。

プロジェクトの正本を JDK 21 に統一した（2026-09-08 代表決定。§3「`maplibre_gl` 0.27.0 は
JDK 21 を要求する」参照）ため、
**この対話/非対話の分岐自体はもう実害を生まない**（どちらの経路でも 21 系に統一するのが
本来あるべき姿）が、sdkman 側の候補は 17.0.11-tem のまま残っており、対話シェルで
`sdk default java 21.x-tem` 相当の設定変更は未実施。sdkman 側の追従（21系候補への切替、
または sdkman 運用自体の終了）は本PRのスコープ外とし、別Issue化を推奨する。

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
- **`java -version` が21を返しても、Gradleビルドは17で動いて落ちることがある**
  （2026-09-09・実機セッションで発生）。対話シェルではsdkmanの初期化行が実行され
  `JAVA_HOME=~/.sdkman/candidates/java/current`（JDK **17**.0.11-tem）が設定される。
  `PATH`からsdkmanのパスだけを取り除いても`JAVA_HOME`は残ったままになり、
  **Gradleは`java`コマンドの解決結果より`JAVA_HOME`を優先する**ため、
  「`java -version`は21なのにGradleは17を使い`invalid source release: 21`で落ちる」
  という一見矛盾した状態になる（sdkmanにはJDK 21がインストールされていないため
  `sdk use java 21...`も使えない）。対処は`JAVA_HOME`をシステムJDK21のパスへ
  明示的に上書きすること。例:
  ```bash
  JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH=$(echo "$PATH" | tr ':' '\n' | grep -v sdkman | paste -sd:) \
    flutter run
  ```
  17でビルドを一度試みてGradleデーモンが起動してしまっている場合は、環境変数を
  直しただけでは効かないことがあるため、先に`./gradlew --stop`でデーモンを
  止めてからやり直すこと。詳細・具体的な発生経緯は
  `spikes/map_spike_gl/README.md`「代表向けの実行手順」ステップ0を参照
  （本プロジェクトのJDK正本は下記§3のとおり21だが、対話シェル環境ではsdkmanが
  この落とし穴を作りうる点は環境準備一般の注意として本節に記録する）。

### ⚠️ `android.builtInKotlin` と `maplibre_gl` の git 依存（Issue #67・2026-09-10 対応済み）

`app/android/gradle.properties` の `android.builtInKotlin` は Flutter 3.44.8 の既定である
`false` に戻っている。以前（PR #66）は `maplibre_gl` 0.27.0（pub.dev版）のビルド失敗
（`Could not find method kotlin()`）を回避するため `true` にしていたが、この設定は
`kotlin-android` を適用する他の Flutter プラグイン（`path_provider` 等）を軒並み
使えなくする相互排他を生むブロッカーだったことが実測で判明した（2026-09-10、
Issue #83 / PR #90 の CI 失敗がきっかけ）。`builtInKotlin=true` と `false` は
プラグイン構成に対して二者択一であり、両方を同時に満たす設定は存在しない。

- **現在の構成**: `packages/location/pubspec.yaml` の `maplibre_gl` は pub.dev 版ではなく、
  上流の修正コミット（`2dff788c650f0d49677397aae55423774aecb8f2` — PR #1020
  「apply KGP when AGP does not compile Kotlin itself」、2026-09-08 main マージ済み）
  への git 依存（`path: maplibre_gl` 指定必須。上流はワークスペース構成）。
  これにより `android.builtInKotlin=false` のままでも `maplibre_gl` のビルドが通る。
- **一時的差し戻しである**: Issue #55（2026-09-07 代表決定）は「pub.dev 版
  `maplibre_gl: ^0.27.0` を採用し git 依存は採らない」と決めていた。本対応は
  pub.dev に上記修正を含む版（0.27.1 以降）が未リリースであることによる一時的な
  差し戻し。リリースされ次第 pub.dev 版に戻すこと（追跡 Issue は別途起票）。
- **Flutter をアップグレードする際は必ず Issue #67 を確認すること。** 特に AGP バージョンが変わる
  Flutter アップデートでは本件が別の形で再発しうる。上記 §2 の
  `tools/check_toolchain_versions.sh`（Issue #59, Flutter/JDK のバージョン整合チェック）を
  Flutter バージョン変更時に実行する運用と合わせて、本フラグ・git 依存の要否もそのタイミングで再評価する。

### ⚠️ `maplibre_gl` 0.27.0 は JDK 21 を要求する（解決済み・2026-09-08・JDK 21 に統一）

`android.builtInKotlin=true`（上記）だけでは `flutter build apk` は通らない。
`maplibre_gl-0.27.0/android/build.gradle` が Java/Kotlin のコンパイルターゲットを
**AGPのバージョンに関係なく無条件で** `JavaVersion.VERSION_21` / `JVM_21` に固定しているため、
JDK 17 でビルドすると

```
Execution failed for task ':maplibre_gl:compileDebugJavaWithJavac'.
> Java compilation initialization error
    error: invalid source release: 21
```

で失敗する。**これは Issue #67（`builtInKotlin` の撤去条件）とは独立した別の制約**で、
上流が Built-in Kotlin に対応しても解消しない。

**【代表決定・2026-09-08】プロジェクトの正本 JDK を 17 → 21 に引き上げた。**
根拠: ゲート②で承認済みの feature-state 方式の fog of war（`plan.md` §8）を実現するには
Android で `setFeatureState` が動く `maplibre_gl` 0.27.0 以降が必須（0.26.2 は
`UnimplementedError`）で、その 0.27.0 が JDK 21 を無条件で要求する。JDK 21 を採らない場合は
ゲート②の fog of war 方式の決定そのものを開き直す必要があり、割に合わないと判断した。
JDK 21 は LTS で AGP 9.0.1 / Kotlin 2.3.20 いずれも対応する。`ci.yml` の `java-version` を
`"21"` に変更し、本表（§2）も実態（21）に更新済み。詳細: `specs/001-mvp/research.md` §6.1、
`specs/001-mvp/plan.md` §14 R1 追記、PR #66。

**この一件が明らかにした `tools/check_toolchain_versions.sh` の限界**（Issue #59）:
このチェックは `ci.yml` と本ドキュメント §2 という**2つの文書間の一致**を検査するものであり、
**文書と実環境（実際にインストールされている JDK）のズレは検出できない**。今回は
両文書とも JDK 17 の記述で一致していたためチェック自体は PASS していたが、
（上記「JDK 行の実態」の節で述べた通り）非対話シェルの実環境は JDK 21 に解決されており、
実際にビルドを壊していたのはこの「文書 vs 実環境」のズレだった。文書間の一致チェックだけでは
この種の問題は防げない、という限界として記録しておく。

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
- **`android/` の配置**: `flutter create` の標準に合わせて **`app/android/`** とした（`app/ios/` は将来・未着手）。
  plan.md §2 のツリーは当初リポジトリ直下に `android/` を置く記述だったが、**Issue #35（2026-09-08）で実態に合わせて修正済み**。

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

## 8. SVG→PNG 変換環境（Issue #28）

`assets/*.svg`（アプリアイコン等）は SVG が正本だが、Android の mipmap と Google Play 掲載画像には
PNG が必要。2026-08-01 時点で WSL に変換手段がなかったため、以下の方針で整備した。

### 採用方式（2026-08-01 代表決定）

**cairosvg（A案）を採用。** `<use>` / `<defs>` / `clipPath` を正しく解釈できるため
（本リポジトリの SVG アセットはこれらを多用している）。rsvg-convert / Inkscape /
ImageMagick は不採用（未検証・追加導入コストが高い）。

### 前提条件

```bash
sudo apt install libcairo2 libcairo-gobject2   # 代表が導入済み（2026-08-01時点で確認済み）
```

system の `python3` には pip が入っておらず、Ubuntu 24.04 は PEP 668 により
system Python への直接 `pip install` も制限される。そのため **`tools/.venv`（リポジトリ専用の venv）**
に cairosvg を導入する方式にした。他プロジェクトの venv と共有しない理由は、
terra-town 専用のビルドツールが別プロジェクトの venv に依存する事態を避けるため。

### セットアップ手順

```bash
cd ~/terra-town   # WSLネイティブパス。/mnt/c/... は既知の罠（別ツールの遅延・パス解決不具合）につながるため避ける
python3 -m venv tools/.venv
tools/.venv/bin/pip install --upgrade pip
tools/.venv/bin/pip install cairosvg
```

`tools/.venv/` は `.gitignore` 済み（各開発者のローカルで作成する）。

### 使い方

```bash
# assets/*.svg すべてを mipmap 5段階（mdpi/hdpi/xhdpi/xxhdpi/xxxhdpi）+ Play掲載用512pxに変換
tools/.venv/bin/python tools/rasterize_assets.py

# 対象を絞る場合
tools/.venv/bin/python tools/rasterize_assets.py --asset app-icon

# 出力先を変える場合（デフォルト build/rasterized/。これも .gitignore 済み・再生成可能なため未コミット）
tools/.venv/bin/python tools/rasterize_assets.py --out-dir /tmp/out
```

Android実機への実際の反映（`mipmap-*/ic_launcher.png` の差し替え・`mipmap-anydpi-v26/ic_launcher.xml`
の追加・`flutter_launcher_icons` の導入）は別 Issue（#29）の範囲。本節はビルド環境の整備のみ。

## 9. 未確定事項

- **applicationId が `jp.rokusoudo.terra_town` で仮置き**（`app/android/app/build.gradle.kts`）。
  Google Play では**公開後に変更できない**ため、初回リリース前に代表が確定すること。
- Flutter 地図プラグインの選定は未着手（tasks.md T011・plan.md §16）。
