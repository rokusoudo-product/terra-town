import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/color_tokens.dart';
import 'package:terra_town/design/map_style_colors.dart';
import 'package:terra_town/map/map_style_factory.dart';

void main() {
  // 【Issue #57 と同じ役割分担】色の正しさを担保するのは app 側の責務。
  // DESIGN.md のトークン（水面=secondary系・緑=primary系）と、実際に MapView へ
  // 注入される値が一致することを検証する。ソースレイヤー名・ズーム範囲は
  // tools/pack-builder/README.md の実測メタデータに基づく（推測していない）。
  test('水面レイヤーは secondary トークンに一致する', () {
    final layers = buildRegionPackFillLayers();
    final water = layers.singleWhere((l) => l.sourceLayer == 'water');

    expect(water.fillColorHex, ColorTokens.secondaryLight.toMapLibreHexRGB);
    expect(water.minzoom, 0);
  });

  test('土地被覆(landcover)レイヤーは primary トークンに一致する', () {
    final layers = buildRegionPackFillLayers();
    final landcover = layers.singleWhere((l) => l.sourceLayer == 'landcover');

    expect(
      landcover.fillColorHex,
      ColorTokens.primaryLight.toMapLibreHexRGB,
    );
    expect(landcover.minzoom, 7);
  });

  test('建物(building)レイヤーは実測どおり minzoom 13 を指定する', () {
    final layers = buildRegionPackFillLayers();
    final building = layers.singleWhere((l) => l.sourceLayer == 'building');

    expect(building.minzoom, 13);
  });

  test('道路(transportation)の線レイヤーは text-secondary トークンに一致する', () {
    final lines = buildRegionPackLineLayers();
    final transportation = lines.singleWhere(
      (l) => l.sourceLayer == 'transportation',
    );

    expect(
      transportation.lineColorHex,
      ColorTokens.textSecondaryLight.toMapLibreHexRGB,
    );
    expect(transportation.minzoom, 4);
  });

  test('背景色は background トークン（ライト）から導出する', () {
    expect(
      buildMapBackgroundColorHex(),
      ColorTokens.backgroundLight.toMapLibreHexRGB,
    );
  });

  test('レイヤーIDは重複しない', () {
    final ids = [
      ...buildRegionPackFillLayers().map((l) => l.id),
      ...buildRegionPackLineLayers().map((l) => l.id),
    ];
    expect(ids.toSet().length, ids.length);
  });
}
