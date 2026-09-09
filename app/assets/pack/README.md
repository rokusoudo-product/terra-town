# app/assets/pack/ — 同梱地域パック（バーティカルスライス対象エリア）

このディレクトリには、バーティカルスライス対象エリア（狭山湖周辺・Issue #85 で確定。
`tools/pack-builder/config.py` の `AREA_SLUG = "sayamako"`）の地域パックを配置する。

**このディレクトリの生成物（`region_pack.sqlite`・`tiles.mbtiles` 等）はコミットしない**
（`.gitignore` 参照。本 `README.md` だけがコミット対象）。`spikes/fixtures/` と同じ
「取得（生成）スクリプト + `.gitignore`」の考え方（plan.md §3・Issue #85）。

## 生成方法

```bash
cd tools/pack-builder
bash bundle_region_pack.sh
```

`tools/pack-builder/README.md` の「バーティカルスライス対象エリアの同梱」の節を参照。
実行すると、このディレクトリに次のファイルが生成される:

| ファイル | 内容 | 生成元 |
|---|---|---|
| `region_pack.sqlite` | ヘクス地形属性（`hex_terrain`）とパックメタ（`pack_meta`。`pack_version` を含む） | `classify_terrain.py` → `slim_pack_for_bundle.py` |
| `tiles.mbtiles` | ベクタタイル（表示専用の基盤地図） | `build_vector_tiles.sh`（Planetiler） |

## pubspec.yaml との関係

`app/pubspec.yaml` の `flutter.assets` はこのディレクトリを**ディレクトリ単位**
（`assets/pack/`）で宣言している。ディレクトリ宣言のため、この `README.md` だけが
存在する状態（＝生成物未取得の状態）でも `flutter test` / `flutter analyze` は失敗しない
（ビルド・実機実行時に地図表示を試す場合は、事前に `bundle_region_pack.sh` の実行が必要）。

## 地図表示（T055）で読む際の注意

- `region_pack.sqlite` の `hex_terrain` から、`location/` が実行時に fog of war 用の
  GeoJSON FeatureCollection を組み立てる（各 Feature 直下に `feature_id` 列の値を
  整数 `id` として持たせること。`promoteId` は Android 非対応 — plan.md §8）。
  本ディレクトリに GeoJSON ファイルとして同梱しているわけではない
  （参考実装・検証は `tools/pack-builder/export_hex_geojson.py`）。
- `tiles.mbtiles` は Planetiler 標準プロファイル（OpenMapTiles互換スキーマ）で生成した
  表示専用のベクタタイル。実機での読込確認手順は `tools/pack-builder/README.md`
  「実機での読込確認手順（代表向け）」を参照。
