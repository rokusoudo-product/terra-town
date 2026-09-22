import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

BuildingRow _row({
  required int id,
  required int hexId,
  required BuildingType buildingType,
  String? districtId,
}) {
  return BuildingRow(
    id: id,
    hexId: hexId,
    buildingType: buildingType,
    level: 1,
    constructionState: BuildingConstructionState.built,
    districtId: districtId,
    builtAt: DateTime.utc(2026, 9, 21),
  );
}

void main() {
  group('buildingIconId', () {
    test('8種すべてに対して非空・一意の画像名を返す（Issue #193 本文「8種」）', () {
      final ids = BuildingType.values.map(buildingIconId).toList();

      expect(ids, hasLength(8));
      expect(ids.toSet(), hasLength(8)); // 一意
      for (final id in ids) {
        expect(id, isNotEmpty);
      }
    });

    test('同じ種別には常に同じ値を返す', () {
      expect(
        buildingIconId(BuildingType.house),
        buildingIconId(BuildingType.house),
      );
    });

    test('種別ごとに異なる値を返す（例）', () {
      expect(
        buildingIconId(BuildingType.house),
        isNot(buildingIconId(BuildingType.apartment)),
      );
    });
  });

  group('buildBuildingFeatureCollection', () {
    test('中心が見つかった建物のみ、直下に整数idを持つFeatureとして含める', () {
      final buildings = [
        _row(id: 1, hexId: 100, buildingType: BuildingType.house),
        _row(id: 2, hexId: 200, buildingType: BuildingType.quarry),
        // 中心が見つからない（hex_terrain 未収録想定）ためスキップされる。
        _row(id: 3, hexId: 300, buildingType: BuildingType.museum),
      ];
      final centers = {
        100: [139.0, 35.0],
        200: [139.1, 35.1],
      };

      final collection = buildBuildingFeatureCollection(buildings, centers);
      final features = collection['features'] as List;

      expect(features, hasLength(2));

      final first = features[0] as Map<String, dynamic>;
      expect(first['id'], isA<int>());
      expect(first['id'], hexIdToFeatureId(100));
      expect(first['geometry'], {
        'type': 'Point',
        'coordinates': [139.0, 35.0],
      });
      expect(first['properties']['hex_id_str'], '100');
      expect(first['properties']['building_type'], 'house');
      expect(first['properties']['icon'], buildingIconId(BuildingType.house));

      final second = features[1] as Map<String, dynamic>;
      expect(second['properties']['building_type'], 'quarry');
      expect(second['properties']['icon'], buildingIconId(BuildingType.quarry));

      expect(
        () => validateBuildingFeatureCollectionIds(collection),
        returnsNormally,
      );
    });

    test('建物が1件も無い場合は空のFeatureCollectionを返す', () {
      final collection = buildBuildingFeatureCollection(const [], const {});

      expect(collection['type'], 'FeatureCollection');
      expect(collection['features'], isEmpty);
    });
  });

  group('validateBuildingFeatureCollectionIds', () {
    test('Featureの直下にidが無い場合は例外を投げる', () {
      final featureCollection = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'geometry': null,
            'properties': {'hex_id_str': '1'},
          },
        ],
      };

      expect(
        () => validateBuildingFeatureCollectionIds(featureCollection),
        throwsArgumentError,
      );
    });

    test('featuresキー自体が無い場合は例外を投げる', () {
      expect(
        () =>
            validateBuildingFeatureCollectionIds({'type': 'FeatureCollection'}),
        throwsArgumentError,
      );
    });
  });

  group('buildingSymbolLayerProperties（Issue #170と同じ再発防止）', () {
    test('icon-imageはget式であり、feature-stateを一切参照しない', () {
      final json = buildingSymbolLayerProperties().toJson();

      expect(json['icon-image'], ['get', 'icon']);
      expect(_containsFeatureState(json), isFalse);
    });
  });
}

bool _containsFeatureState(dynamic value) {
  if (value is String) return value == 'feature-state';
  if (value is Map) return value.values.any(_containsFeatureState);
  if (value is List) return value.any(_containsFeatureState);
  return false;
}
