import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/design/color_tokens.dart';
import 'package:terra_town/design/map_style_colors.dart';
import 'package:terra_town/map/terrain_tint_layer_factory.dart';

void main() {
  // 【Issue #57・#176】色の正しさを担保するのは app 側の責務。
  // ここで Issue #175 の承認文面（森=primary・山=text-secondary・水辺=secondary・
  // 海=info、いずれも0.22。縁取りはtext-secondary・幅1px・不透明度0.30）と、
  // 実際に TerrainTintLayer へ注入される値が一致することを検証する。
  // packages/location 側のテストはフェイク値のみを扱う（役割分担）。
  test('地形タイプ別の塗り色がDESIGN.mdのトークン（#175承認文面）と一致する', () {
    final layer = buildTerrainTintLayer();

    expect(
      layer.fillColorHexByTerrainType['forest'],
      ColorTokens.primaryLight.toMapLibreHexRGB,
    );
    expect(layer.fillColorHexByTerrainType['forest'], '#2E7D32');

    expect(
      layer.fillColorHexByTerrainType['mountain'],
      ColorTokens.textSecondaryLight.toMapLibreHexRGB,
    );
    expect(layer.fillColorHexByTerrainType['mountain'], '#4A4B45');

    expect(
      layer.fillColorHexByTerrainType['waterside'],
      ColorTokens.secondaryLight.toMapLibreHexRGB,
    );
    expect(layer.fillColorHexByTerrainType['waterside'], '#00695C');

    expect(
      layer.fillColorHexByTerrainType['sea'],
      ColorTokens.infoLight.toMapLibreHexRGB,
    );
    expect(layer.fillColorHexByTerrainType['sea'], '#1565C0');
  });

  test('空き地（vacant_lot）は塗り色マップに含まれない（塗らない方針）', () {
    final layer = buildTerrainTintLayer();

    expect(layer.fillColorHexByTerrainType.containsKey('vacant_lot'), isFalse);
    expect(layer.fillColorHexByTerrainType, hasLength(4));
  });

  test('塗りの不透明度は0.22で統一されている（#175承認文面）', () {
    final layer = buildTerrainTintLayer();

    expect(layer.fillOpacity, 0.22);
  });

  test('縁取りはtext-secondary・幅1px・不透明度0.30（#175承認文面）', () {
    final layer = buildTerrainTintLayer();

    expect(layer.outlineColorHex, ColorTokens.textSecondaryLight.toMapLibreHexRGB);
    expect(layer.outlineColorHex, '#4A4B45');
    expect(layer.outlineOpacity, 0.30);
    expect(layer.outlineWidth, 1.0);
  });
}
