import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';
import '../design/map_style_colors.dart';

/// composition root（`app`）で `FogOfWarLayer` を組み立てる。
///
/// 【Issue #57・注入方式】色を知っているのは `app` 側のみ。
/// `packages/location` の `FogOfWarLayer` はコンストラクタで受け取った
/// 16進文字列・αを保持するだけで、配色そのものには関与しない。
/// ここで DESIGN.md の `fog` トークン（`ColorTokens.fog`）を
/// `MapStyleColor` 経由で MapLibre 用の値に変換し、注入する。
///
/// 実際の `MapView` へのレイヤー登録・`feature-state` 切り替え
/// （`specs/001-mvp/plan.md` §8・タスク T056）は本 Issue のスコープ外。
FogOfWarLayer buildFogOfWarLayer() {
  return FogOfWarLayer(
    fillColorHex: ColorTokens.fog.toMapLibreHexRGB,
    fillOpacity: ColorTokens.fog.toMapLibreOpacity,
  );
}
