import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';
import '../design/map_style_colors.dart';

/// composition root（`app`）で `BuildableHighlightLayer`（建設タブで選んだ建物の
/// 「建てられるマス」ハイライト・Issue #192）を組み立てる。
///
/// 【Issue #57 の注入方式を踏襲】色を知っているのは `app` 側のみ。`location` の
/// `BuildableHighlightLayer` はコンストラクタで受け取った値をそのまま保持する
/// だけで、配色そのものには関与しない（`terrain_tint_layer_factory.dart` と
/// 同じ役割分担）。
///
/// 【色は Issue #192 本文の指定どおり `success` トークン】「塗りは既存トークン
/// （例: `success`）を薄く重ねる」（Issue #192「2. 建設の流れ（画面）」）。
/// 不透明度は `terrain_tint_layer_factory.dart` の地形タイプ別色分け（0.22）より
/// 濃い 0.35 とする——地形タイプ別色分けは「そこにいるだけで分かる情報」の
/// 常時表示だが、本ハイライトは「今まさに選べる操作対象」を示す一時的な強調
/// 表示であり、地形の塗りより目立たせる必要があるため（DESIGN.md への追記時に
/// 秘書が採用した実装判断。不透明度の確定値は実機確認で微調整してよい
/// 〔DESIGN.md「開示済みヘクスの土地の見え方」と同じ扱い〕）。
const _buildableHighlightFillOpacity = 0.35;

/// [MapView.buildableHighlightLayer] へそのまま渡す設定値を組み立てる。
BuildableHighlightLayer buildBuildableHighlightLayer() {
  return BuildableHighlightLayer(
    fillColorHex: ColorTokens.successLight.toMapLibreHexRGB,
    fillOpacity: _buildableHighlightFillOpacity,
  );
}
