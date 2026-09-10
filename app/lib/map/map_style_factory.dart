import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';
import '../design/map_style_colors.dart';

/// composition root（`app`）で地域パック（同梱 MBTiles）の見た目を組み立てる。
///
/// 【Issue #57 の注入方式を踏襲】色を知っているのは `app` 側のみ。
/// `packages/location` の [MapView] はコンストラクタで受け取った `#RRGGBB` 文字列を
/// そのまま MapLibre に渡すだけで、配色そのものには関与しない
/// （`app/lib/map/fog_of_war_layer_factory.dart` と同じ役割分担）。
///
/// 【地図はライトのみ MVP（DESIGN.md）】`Theme.of(context)` を経由せず、常に
/// ライトトークン（`ColorTokens.*Light`）から導出する（`buildFogOfWarLayer()` と
/// 同じ方針。ダークテーマの有無に関わらず地図の配色は変えない）。
///
/// 【レイヤー選定の根拠・推測していない】`app/assets/pack/tiles.mbtiles` の実測
/// メタデータ（vector_layers。2026-09-10実測・`tools/pack-builder/README.md`）から、
/// 実際に存在するソースレイヤー名とズーム範囲を確認したうえで選定した:
///   - `water`（minzoom 0）         → secondary（DESIGN.md「水面=secondary系」）
///   - `landcover`（minzoom 7）     → primary（DESIGN.md「緑=primary系」。
///                                    森・草地などの土地被覆）
///   - `building`（minzoom 13）     → text-secondary（`docs/buildings.md` の
///                                    ゲーム内建物オブジェクト〔将来のスプライト表現〕
///                                    と混同しないよう、背景地図の建物footprintは
///                                    控えめな中間色にする）
///   - `transportation`（minzoom 4）→ text-secondary（道路の線レイヤー）
///
/// 塗り不透明度・線幅は DESIGN.md にトークン定義が無い（カラートークンのみが
/// 定義対象）ため、可読性を優先した実装判断の定数として明記する
/// （水面は基盤地図として不透明・土地被覆や建物footprintは主役であるゲーム内
/// オブジェクトを邪魔しないよう半透明にする）。
const _waterFillOpacity = 1.0;
const _landcoverFillOpacity = 0.35;
const _buildingFillOpacity = 0.5;
const _transportationLineOpacity = 0.8;
const _transportationLineWidth = 1.0;

/// 地域パックの vector source 全体のズーム範囲（同梱パックの実測値）。
const regionPackSourceMinzoom = 0.0;
const regionPackSourceMaxzoom = 14.0;

List<MapFillLayerStyle> buildRegionPackFillLayers() {
  return [
    MapFillLayerStyle(
      id: 'terra_town_water',
      sourceLayer: 'water',
      fillColorHex: ColorTokens.secondaryLight.toMapLibreHexRGB,
      fillOpacity: _waterFillOpacity,
      minzoom: 0,
    ),
    MapFillLayerStyle(
      id: 'terra_town_landcover',
      sourceLayer: 'landcover',
      fillColorHex: ColorTokens.primaryLight.toMapLibreHexRGB,
      fillOpacity: _landcoverFillOpacity,
      minzoom: 7,
    ),
    MapFillLayerStyle(
      id: 'terra_town_building',
      sourceLayer: 'building',
      fillColorHex: ColorTokens.textSecondaryLight.toMapLibreHexRGB,
      fillOpacity: _buildingFillOpacity,
      minzoom: 13,
    ),
  ];
}

List<MapLineLayerStyle> buildRegionPackLineLayers() {
  return [
    MapLineLayerStyle(
      id: 'terra_town_transportation',
      sourceLayer: 'transportation',
      lineColorHex: ColorTokens.textSecondaryLight.toMapLibreHexRGB,
      lineOpacity: _transportationLineOpacity,
      lineWidth: _transportationLineWidth,
      minzoom: 4,
    ),
  ];
}

/// 地図スタイルの背景色（`#RRGGBB`）。DESIGN.md の background トークン（ライト）。
String buildMapBackgroundColorHex() =>
    ColorTokens.backgroundLight.toMapLibreHexRGB;
