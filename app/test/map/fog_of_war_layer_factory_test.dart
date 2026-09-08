import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/color_tokens.dart';
import 'package:terra_town/design/map_style_colors.dart';
import 'package:terra_town/map/fog_of_war_layer_factory.dart';

void main() {
  // 【Issue #57】色の正しさを担保するのは app 側の責務。
  // ここで DESIGN.md の fog トークン（rgba(20,22,16,0.62)）と、
  // 実際に FogOfWarLayer へ注入される値が一致することを検証する。
  // packages/location 側のテストはフェイク値のみを扱う（役割分担）。
  test('fog レイヤーへの注入値が DESIGN.md の fog トークン(rgba(20,22,16,0.62))と一致する', () {
    final layer = buildFogOfWarLayer();

    // DESIGN.md: rgba(20,22,16,0.62) -> #RRGGBB = #141610
    expect(layer.fillColorHex, '#141610');
    // 8bit アルファ(0x9E=158)からの逆算のため僅かな丸め誤差(158/255=0.6196...)を許容する。
    expect(layer.fillOpacity, closeTo(0.62, 0.01));

    // ColorTokens.fog（唯一の色の正本）から導出した値と完全一致することも確認する。
    expect(layer.fillColorHex, ColorTokens.fog.toMapLibreHexRGB);
    expect(layer.fillOpacity, ColorTokens.fog.toMapLibreOpacity);
  });
}
