# map_spike_josxha — Issue #24 検証ハーネス（`maplibre`(josxha/flutter-maplibre) 用・最小プローブ）

**これは使い捨ての検証ハーネスであり、製品コードではありません。**

- terra-town 本体（`app/` `packages/core/` `packages/location/`）とは一切関係がなく、依存もしていません。
- `DESIGN.md` のデザイントークンには準拠していません。検証専用UIであり製品UIではないためです。
- `map_spike_gl`（`maplibre_gl` 用）と違い、**このアプリには性能計測UIを作っていません**。
  理由: `specs/001-mvp/research.md` §3.2 の机上調査で、このパッケージが `feature-state` API を
  実装している根拠（ソース・ドキュメント・Issue のいずれにも）を見つけられなかったため。
  fog of war 性能計測は `maplibre_gl` の方針（GeoJSON差分更新、feature-state非依存）で行うのが
  本命であり、性能計測の主戦場は `../map_spike_gl` 側にある。

## これは何を検証するか

| このアプリのUI | research.md §6 の項目 |
|---|---|
| 上部バナー: プラグイン名・版数・stable/git main | §6.1 の前提記録 |
| 基本地図表示 | §6.1 の基本動作確認 |
| MBTiles参照の試行（**無効化済み**） | §6.2 T012/R1（未解決のまま記録） |

## 代表向けの実行手順

`map_spike_gl/README.md` と同じ手順です（重複を避けるため要点のみ）。

1. Windows PowerShell で `usbipd list` → `usbipd attach --wsl --busid <busid>`
   （WSLにアタッチしている間はWindows側adbから見えなくなるのは正常）
2. WSLで `/home/zakis/flutter/bin/flutter devices` に端末が出ることを確認
3.
   ```bash
   cd ~/terra-town/spikes/map_spike_josxha
   /home/zakis/flutter/bin/flutter run
   ```

## MBTilesボタンを無効化した理由

`maplibre`（`packages/maplibre` / `packages/maplibre_android` / `packages/maplibre_platform_interface`）の
pub.dev配布パッケージのソースコードを `grep -i mbtiles` で検索したが、**1件もヒットしなかった**。
公式の機能マトリクス（`website/features/index.md`）ではMBTilesがAndroid ✅・iOS ✅と明記されているため、
実装自体は存在する可能性が高いが、Dart側から呼び出すための構文（URLスキームの書式・ファイル配置要件）を
示す一次情報が見つからなかった。

CHANGELOG.md の記述から、PMTilesサポートは「MapLibre Native を 11.8.0 にアップグレードしたことで追加された」
ことが分かっており（ネイティブ層＝maplibre-native Android SDKの機能）、research.md §2.4 が指摘する
「両パッケージとも同じmaplibre-native Androidエンジンの上に乗っている」という構造を踏まえると、
`maplibre_gl` 側で確認できている `mbtiles://<絶対パス>` という構文がこちらでも通る可能性はゼロではない。
しかし、これは完全な当て推量であり、一次情報による裏付けがない。**その状態のボタンを「動く」ものとして
提示するのは誠実でないため、意図的に無効化してある**（`onPressed: null`）。

代表が実機で確かめたい場合は、`lib/main.dart` の該当ボタンの `onPressed: null` を、
`maplibre_gl` 側の実装（`../map_spike_gl/lib/map_probe_page.dart` の `_loadMbtiles()`）を参考にした
処理に差し替えて試すことができます（`StyleController.addSource` 等、必要なAPIは
`packages/maplibre_platform_interface` の `Source`/`RasterSource` 系クラスを参照）。

## バージョン切り替え（pub.dev安定版 ⇔ git main）

`pubspec.yaml` の既定は pub.dev 安定版 `maplibre: 0.3.5` です。git 依存でmainブランチを直接参照する
記述をコメントアウトで併記してあります:

```yaml
dependencies:
  maplibre: ^0.3.5
  # 未リリースのmainブランチを試す場合は上の行をコメントアウトし、下を有効化する:
  # maplibre:
  #   git:
  #     url: https://github.com/josxha/flutter-maplibre.git
  #     ref: main
  #     path: packages/maplibre
```

切り替えたら **`lib/plugin_info.dart` の `kPluginVersionLabel` も必ず手で書き換える**こと。

- **安定版で回すと「今日出荷できるか」が分かる**。
- **git mainで回すと最新の変更（feature-state実装の有無を含む）が反映されているかが分かる**
  （josxha版はmainブランチのpushが2026-08-09時点で活発。0.3.5からの差分は不明なため要確認）。
- **両方回すことを推奨**します。切り替え後は `flutter pub get` を忘れずに。

## MBTiles / PMTiles フィクスチャ

`../fixtures/fetch_fixtures.sh` で MapLibre 公式配布の軽量サンプルを取得できます
（`../fixtures/README.md` 参照）。ただし本アプリはMBTilesボタン自体を無効化しているため、
現状では取得しても直接は使えません（上記「MBTilesボタンを無効化した理由」参照）。

## 環境

- Flutter 3.44.8 / Dart 3.12.2（`docs/dev-setup.md` §2 準拠）
- `maplibre: ^0.3.5`（pub.dev安定版）
- Dart SDK制約に注意: `maplibre` パッケージ自体の下限は `^3.12.0`。
  本リポジトリの実測 Dart は 3.12.2 のため適合するが、パッチ2つ分の余裕しかない
  （research.md §1 参照）。

## コンパイル確認（実施済み・実機実行は未実施）

- `flutter analyze`: 実施済み（結果はPR本文参照）
- `flutter build apk --debug`: 実施済み（結果はPR本文参照）
- **実機での起動・動作確認はしていません。** 実機が接続されていない環境で作業したため。
