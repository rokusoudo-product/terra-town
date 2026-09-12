import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/color_tokens.dart';
import 'package:terra_town/design/map_style_colors.dart';
import 'package:terra_town/map/current_location_marker_factory.dart';

void main() {
  // 【Issue #57】色の正しさを担保するのは app 側の責務。
  // ここで DESIGN.md の既存トークン（info・surface）と、実際に
  // CurrentLocationMarkerStyle へ注入される値が一致することを検証する。
  // packages/location 側のテストはフェイク値のみを扱う（役割分担）。
  test('現在地マーカーへの注入値がDESIGN.mdのinfo/surfaceトークンと一致する', () {
    final style = buildCurrentLocationMarkerStyle();

    // DESIGN.md: info(ライト) = #1565C0 / surface(ライト) = #FFFFFF
    expect(style.fillColorHex, '#1565C0');
    expect(style.strokeColorHex, '#FFFFFF');

    // ColorTokens（唯一の色の正本）から導出した値と完全一致することも確認する。
    expect(style.fillColorHex, ColorTokens.infoLight.toMapLibreHexRGB);
    expect(style.strokeColorHex, ColorTokens.surfaceLight.toMapLibreHexRGB);
  });
}
