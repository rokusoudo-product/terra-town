# spikes/fixtures — MBTiles / PMTiles 検証用サンプル

`map_spike_gl` / `map_spike_josxha` のMBTiles・PMTiles読込テスト用フィクスチャ。
地域パック（`tools/pack-builder/`）はまだ存在しないため、terra-town固有のデータではなく、
MapLibreプロジェクト公式が配布する軽量サンプル（世界地図・国境ポリゴン、z0-6、数MB）を使う。

## 取得方法

```bash
cd spikes/fixtures
bash fetch_fixtures.sh
```

`sample.mbtiles`・`sample.pmtiles` がこのディレクトリに生成される（**リポジトリにはコミットしない**。
`.gitignore` 参照）。あわせて `sample.mbtiles` を `../map_spike_gl/assets/` にもコピーする
（アプリのアセット同梱用。同じくコミットしない）。

## 出典・ライセンス

- リポジトリ: [maplibre/demotiles](https://github.com/maplibre/demotiles)（コード: BSD-3-Clause）
- 地図データ: [Natural Earth Data](https://www.naturalearthdata.com/)（パブリックドメイン。
  クレジット表記は不要と明記されている）
- `sample.mbtiles`: [maplibre.mbtiles (release v1.0)](https://github.com/maplibre/demotiles/releases/download/v1.0/maplibre.mbtiles) — ベクタタイル、z0-6、約5MB
- `sample.pmtiles`: [world.pmtiles](https://demotiles.maplibre.org/pmtiles/vector/world.pmtiles) — 同データのPMTiles版、約3.8MB

## 探索の範囲（時間を区切って対応）

「軽量・入手元が明確・ライセンスがクリア」を条件に、MapLibre公式配布のサンプルのみを対象にした。
`klokantech/vector-tiles-sample` の `countries.mbtiles` など他の候補も見つけたが、出典・更新状況の
確認にさらに時間がかかるため見送った。より実データに近い（日本国内・高ズームレベルの）サンプルが
必要な場合は、代表が別途 `pmtiles convert` 等で用意することを想定している。

## 実機での使い方

**【2026-09-09 変更】`adb push` は使わない。** Android 13+ ではアプリがSAF（Storage Access
Framework）を通さずに `/sdcard/Download` 等の任意ファイルを直接読めず、`adb push` で配置した
ファイルへのアクセスが権限エラーになる。これは「MapLibre側の失敗」と外形上区別できず、
検証結果を汚染する（Androidのスコープドストレージ一般の制約。terra-town固有の一次情報
での確認はしていない。要確認としてIssue #24側に記録すること）。

かわりに `fetch_fixtures.sh` が `sample.mbtiles` を `map_spike_gl/assets/` へもコピーし、
`pubspec.yaml` の `flutter: assets:` に登録済みにしてある。`map_spike_gl` アプリのタブ①
「同梱フィクスチャをコピーして使う」ボタンを押せば、アプリ内蔵のアセットからアプリの
キャッシュディレクトリ（書き込み可能領域）へ自動コピーされ、そのパスで `mbtiles://` を試せる。
手入力のパス欄は残しているが、代表が別途用意したファイルを試す場合など補助的な用途とし、
既定の導線としては使わないこと。
