import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/color_tokens.dart';
import 'package:terra_town/design/map_style_colors.dart';
import 'package:terra_town/map/buildable_highlight_layer_factory.dart';

void main() {
  // 【Issue #57・#192】色の正しさを担保するのは app 側の責務
  // （`terrain_tint_layer_factory_test.dart` と同じ役割分担）。
  test('塗り色はDESIGN.mdの success トークンと一致する', () {
    final layer = buildBuildableHighlightLayer();

    expect(layer.fillColorHex, ColorTokens.successLight.toMapLibreHexRGB);
    expect(layer.fillColorHex, '#2E7D32');
  });

  test('不透明度は0〜1の範囲内で、地形タイプ別色分け(0.22)より濃い', () {
    final layer = buildBuildableHighlightLayer();

    expect(layer.fillOpacity, greaterThan(0.22));
    expect(layer.fillOpacity, lessThanOrEqualTo(1.0));
  });
}
