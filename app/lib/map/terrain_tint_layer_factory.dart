import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';
import '../design/map_style_colors.dart';

/// composition root（`app`）で `TerrainTintLayer`（開示済みヘクスの地形タイプ別
/// 色分け・Issue #176）を組み立てる。
///
/// 【Issue #57 の注入方式を踏襲】色を知っているのは `app` 側のみ。`location` の
/// `TerrainTintLayer` はコンストラクタで受け取った値をそのまま保持するだけで、
/// 配色そのものには関与しない（`fog_of_war_layer_factory.dart`・
/// `map_style_factory.dart` と同じ役割分担）。
///
/// 【数値の根拠は Issue #175（代表承認済み・2026-09-14）】
/// DESIGN.md への反映は別PR（#177・秘書が作成・本PR時点で未マージ）が担当するため、
/// 本ファイルは DESIGN.md 自体を編集せず、#175 の承認文面（下表）をそのまま定数化する:
///
/// | 地形タイプ | 塗り色（トークン） | 塗りの不透明度 |
/// |-----------|------------------|--------------|
/// | 空き地 | なし | 0 |
/// | 森 | `primary`（#2E7D32） | 0.22 |
/// | 山 | `text-secondary`（#4A4B45） | 0.22 |
/// | 水辺（川・湖） | `secondary`（#00695C） | 0.22 |
/// | 海 | `info`（#1565C0） | 0.22 |
///
/// 縁取り: `text-secondary` の線（幅1px・不透明度0.30）を開示済み全ヘクス
/// （空き地を含む）に適用する。空き地は
/// [TerrainTintLayer.fillColorHexByTerrainType] に含めないことで、
/// `terrainTintFillLayerProperties`（`terrain_tint_layer.dart`）の `match` 式の
/// 既定値（不透明度0）にフォールバックさせ、「塗らない」を表現する。
///
/// 塗り不透明度・縁取りの不透明度/線幅は DESIGN.md のカラートークン定義そのもの
/// ではない（#175 承認文面の数値）ため、`map_style_factory.dart` の
/// `_landcoverFillOpacity` 等と同じ位置づけの実装判断の定数として明記する
/// （`tools/check_design_tokens.sh` が検出するのは色リテラル（Flutter の Color
/// 型のコンストラクタ呼び出し）のみで、この double 定数は対象外）。
const _terrainTintFillOpacity = 0.22;
const _terrainTintOutlineOpacity = 0.30;
const _terrainTintOutlineWidth = 1.0;

/// 地域パックの `hex_terrain.terrain_type` が取りうるスネークケースの文字列
/// （`docs/terrain.md`・Issue #176 本文）。`core` の `TerrainType` enum 名
/// （`vacantLot` 等）とは表記が異なるため、ここでは地域パックの生の文字列を
/// 直接使う（`fog_hex_source.dart` の `properties.terrain_type` と同じ値）。
/// 空き地（`vacant_lot`）は塗らない方針（#175 承認文面）のためここには含めない。
const _forestTerrainType = 'forest';
const _mountainTerrainType = 'mountain';
const _watersideTerrainType = 'waterside';
const _seaTerrainType = 'sea';

/// [MapView.terrainTintLayer] へそのまま渡す設定値を組み立てる。
TerrainTintLayer buildTerrainTintLayer() {
  return TerrainTintLayer(
    fillColorHexByTerrainType: {
      _forestTerrainType: ColorTokens.primaryLight.toMapLibreHexRGB,
      _mountainTerrainType: ColorTokens.textSecondaryLight.toMapLibreHexRGB,
      _watersideTerrainType: ColorTokens.secondaryLight.toMapLibreHexRGB,
      _seaTerrainType: ColorTokens.infoLight.toMapLibreHexRGB,
    },
    fillOpacity: _terrainTintFillOpacity,
    outlineColorHex: ColorTokens.textSecondaryLight.toMapLibreHexRGB,
    outlineOpacity: _terrainTintOutlineOpacity,
    outlineWidth: _terrainTintOutlineWidth,
  );
}
