import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【役割分担・Issue #57 の考え方の延長】ラスタ画像の中身の正しさ（配色・
  // アイコン・ラベルがDESIGN.mdどおりであること）は composition root である
  // app 側のテスト（app/test/map/landmark_layer_factory_test.dart）が担保する。
  // location 側のこのテストは、`LandmarkPinImages` がコンストラクタで
  // 受け取った Map をそのまま保持するだけであることのみを検証する。
  test('LandmarkPinImages はコンストラクタで受け取った画像Mapをそのまま保持する', () {
    final images = {landmarkLockedIconId: Uint8List.fromList([1, 2, 3])};
    final pinImages = LandmarkPinImages(images);

    expect(pinImages.images, images);
  });

  group('landmarkRevealedIconId / landmarkCollectedIconId', () {
    test('POI IDごとに一意で、同じIDには常に同じ値を返す', () {
      const idA = PointOfInterestId('node/1');
      const idB = PointOfInterestId('node/2');

      expect(landmarkRevealedIconId(idA), landmarkRevealedIconId(idA));
      expect(
        landmarkRevealedIconId(idA),
        isNot(landmarkRevealedIconId(idB)),
      );
      expect(
        landmarkRevealedIconId(idA),
        isNot(landmarkCollectedIconId(idA)),
      );
    });

    test('MapLibreの画像名として安全な文字列に正規化する（OSM IDのスラッシュ等）', () {
      const id = PointOfInterestId('node/12345');

      expect(landmarkRevealedIconId(id), 'terra_town_landmark_revealed_node_12345');
      expect(landmarkCollectedIconId(id), 'terra_town_landmark_collected_node_12345');
    });
  });

  group('buildLandmarkFeatureCollection', () {
    test('hexIdを持つPOIのみを、直下に整数idを持つFeatureとして含める', () {
      const withHex = PointOfInterest(
        id: PointOfInterestId('node/1'),
        name: '名所A',
        kind: 'tourism=museum',
        latitude: 35.0,
        longitude: 139.0,
        hexId: HexId(1),
      );
      const withoutHex = PointOfInterest(
        id: PointOfInterestId('node/2'),
        name: '名所B（旧パック由来でhexIdなし）',
        kind: 'tourism=attraction',
        latitude: 35.1,
        longitude: 139.1,
      );

      final collection = buildLandmarkFeatureCollection([withHex, withoutHex]);
      final features = collection['features'] as List;

      expect(features, hasLength(1));
      final feature = features.single as Map;
      expect(feature['id'], isA<int>());
      final properties = feature['properties'] as Map;
      expect(properties['poi_id_str'], 'node/1');
      expect(properties['revealed_icon'], landmarkRevealedIconId(withHex.id));
      expect(properties['collected_icon'], landmarkCollectedIconId(withHex.id));

      expect(
        () => validateLandmarkFeatureCollectionIds(collection),
        returnsNormally,
      );
    });

    test('POIが1件も無い場合は空のFeatureCollectionを返す', () {
      final collection = buildLandmarkFeatureCollection(const []);

      expect(collection['features'], isEmpty);
      expect(
        () => validateLandmarkFeatureCollectionIds(collection),
        returnsNormally,
      );
    });
  });

  group('validateLandmarkFeatureCollectionIds', () {
    test('Featureの直下にidが無い場合は例外を投げる', () {
      final featureCollection = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': null,
            'properties': {'poi_id_str': 'node/1'},
          },
        ],
      };

      expect(
        () => validateLandmarkFeatureCollectionIds(featureCollection),
        throwsArgumentError,
      );
    });

    test('featuresキー自体が無い場合は例外を投げる', () {
      expect(
        () => validateLandmarkFeatureCollectionIds({'type': 'FeatureCollection'}),
        throwsArgumentError,
      );
    });
  });
}
