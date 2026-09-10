import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【役割分担・Issue #57】色の正しさ（DESIGN.md の fog トークンと一致すること）は
  // composition root である app 側のテスト
  // （app/test/map/fog_of_war_layer_factory_test.dart）が担保する。
  // location 側のこのテストはフェイク値を渡し、「コンストラクタで受け取った値を
  // そのまま保持するだけ」であることのみを検証する（location は配色を知らない）。
  test('FogOfWarLayer はコンストラクタで受け取った色・不透明度をそのまま保持する', () {
    const layer = FogOfWarLayer(fillColorHex: '#ABCDEF', fillOpacity: 0.5);

    expect(layer.fillColorHex, '#ABCDEF');
    expect(layer.fillOpacity, 0.5);
  });

  // 【Issue #100・T056の受け入れ基準】
  // 「各Featureが直下に整数idを持つ形でソースに追加されている（promoteIdを
  // 使っていない）」ことを、実機（MapLibreMapController）に依存しない
  // 純粋関数として検証する。`FogOfWarController.install` はこの関数を
  // 地図登録の直前に呼ぶ（本関数自体のテストで install 全体の検証を代替する。
  // install 自体はプラットフォームチャンネルが必要なため flutter test では
  // 検証できない — map_screen_test.dart 冒頭コメントと同じ制約）。
  group('validateFogHexFeatureCollectionIds', () {
    test('全Featureが直下に整数idを持つ場合は例外を投げない', () {
      final featureCollection = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'id': 1,
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [0.0, 0.0],
                  [0.0, 1.0],
                  [1.0, 1.0],
                  [0.0, 0.0],
                ],
              ],
            },
            'properties': <String, dynamic>{},
          },
          {'type': 'Feature', 'id': 2, 'geometry': null, 'properties': {}},
        ],
      };

      expect(
        () => validateFogHexFeatureCollectionIds(featureCollection),
        returnsNormally,
      );
    });

    test('Featureの直下にidが無く、properties内にのみある場合は例外を投げる', () {
      // promoteId（Web専用）で昇格させる誤った実装の再現。Androidでは機能しない
      // ため、この形は実行時に弾く必要がある（plan.md §8・research.md §6.3）。
      final featureCollection = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': null,
            'properties': {'hexId': 1},
          },
        ],
      };

      expect(
        () => validateFogHexFeatureCollectionIds(featureCollection),
        throwsArgumentError,
      );
    });

    test('idが整数でない（文字列等の）場合は例外を投げる', () {
      final featureCollection = {
        'type': 'FeatureCollection',
        'features': [
          {'type': 'Feature', 'id': '1', 'geometry': null, 'properties': {}},
        ],
      };

      expect(
        () => validateFogHexFeatureCollectionIds(featureCollection),
        throwsArgumentError,
      );
    });

    test('featuresキー自体が無い場合は例外を投げる', () {
      expect(
        () => validateFogHexFeatureCollectionIds({'type': 'FeatureCollection'}),
        throwsArgumentError,
      );
    });
  });
}
