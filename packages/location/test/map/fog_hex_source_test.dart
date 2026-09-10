import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_location/terra_town_location.dart';

/// [buildFogHexFeatureCollectionFromRegionPack] のテスト（Issue #105・tasks.md T056）。
///
/// `tools/pack-builder/classify_terrain.py`（Issue #105 で `hex_terrain.boundary_geojson`
/// 列を追加済み）が実際に書き込むスキーマ・値の形をそのまま再現してシードする。
/// 実データ（13,106件）そのものの検証は `app/test/`（`region_pack.sqlite` が
/// 存在する場合のみ実行する結合テスト）で行う。本テストは少数のフェイクデータで
/// 「変換ロジックが正しいか」を決定的に検証する。
void _seedHexTerrain(
  sqlite3.Database db, {
  required int hexId,
  required int featureId,
  required String terrainType,
  required int cellCount,
  required List<List<double>> boundaryRing,
}) {
  db.execute(
    'INSERT INTO hex_terrain '
    '(hex_id, feature_id, terrain_type, cell_count, boundary_geojson) '
    'VALUES (?, ?, ?, ?, ?)',
    [hexId, featureId, terrainType, cellCount, jsonEncode(boundaryRing)],
  );
}

RegionPackConnection _openSeeded(void Function(sqlite3.Database db) seed) {
  return RegionPackConnection.forTesting(
    seed: (db) {
      db.execute('''
        CREATE TABLE hex_terrain (
          hex_id INTEGER PRIMARY KEY,
          terrain_type TEXT NOT NULL,
          feature_id INTEGER NOT NULL,
          cell_count INTEGER NOT NULL,
          boundary_geojson TEXT NOT NULL
        )
      ''');
      seed(db);
    },
  );
}

void main() {
  group('buildFogHexFeatureCollectionFromRegionPack', () {
    test('hex_terrain の各行を、直下に整数idを持つFeatureへ変換する', () async {
      final ringA = [
        [139.0, 35.0],
        [139.001, 35.0],
        [139.001, 35.001],
        [139.0, 35.0],
      ];
      final ringB = [
        [139.1, 35.1],
        [139.101, 35.1],
        [139.101, 35.101],
        [139.1, 35.1],
      ];
      final connection = _openSeeded((db) {
        _seedHexTerrain(
          db,
          hexId: 626833456793083903, // research.md §8.4 実測の最大値（2^53を超える）
          featureId: 111,
          terrainType: 'forest',
          cellCount: 42,
          boundaryRing: ringA,
        );
        _seedHexTerrain(
          db,
          hexId: 2,
          featureId: 222,
          terrainType: 'waterside',
          cellCount: 7,
          boundaryRing: ringB,
        );
      });
      addTearDown(connection.close);

      final fc = buildFogHexFeatureCollectionFromRegionPack(connection);

      expect(fc['type'], 'FeatureCollection');
      final features = fc['features'] as List;
      expect(features, hasLength(2));

      // hex_id昇順（SQLの ORDER BY hex_id）: 2 が先、626833456793083903 が後。
      final first = features[0] as Map<String, dynamic>;
      expect(first['id'], 222);
      expect(first['id'], isA<int>());
      expect(first['geometry'], {
        'type': 'Polygon',
        'coordinates': [ringB],
      });
      expect(first['properties']['terrain_type'], 'waterside');
      expect(first['properties']['cell_count'], 7);
      expect(first['properties']['hex_id_str'], '2');
      expect(first['properties']['hex_id_str'], isA<String>());

      final second = features[1] as Map<String, dynamic>;
      expect(second['id'], 111);
      expect(second['properties']['hex_id_str'], '626833456793083903');

      // fog_of_war_layer.dart の受け入れ検証をそのまま通せることを確認する
      // （FogOfWarController.install が実行時に呼ぶのと同じ関数）。
      expect(
        () => validateFogHexFeatureCollectionIds(fc),
        returnsNormally,
      );
    });

    test('limit を指定すると hex_id 昇順で先頭N件だけを返す', () async {
      final ring = [
        [0.0, 0.0],
        [0.0, 1.0],
        [1.0, 1.0],
        [0.0, 0.0],
      ];
      final connection = _openSeeded((db) {
        for (final hexId in [30, 10, 20]) {
          _seedHexTerrain(
            db,
            hexId: hexId,
            featureId: hexId,
            terrainType: 'vacant_lot',
            cellCount: 1,
            boundaryRing: ring,
          );
        }
      });
      addTearDown(connection.close);

      final fc = buildFogHexFeatureCollectionFromRegionPack(
        connection,
        limit: 2,
      );

      final features = fc['features'] as List;
      expect(features, hasLength(2));
      expect(
        (features[0] as Map<String, dynamic>)['properties']['hex_id_str'],
        '10',
      );
      expect(
        (features[1] as Map<String, dynamic>)['properties']['hex_id_str'],
        '20',
      );
    });

    test('hex_terrain に行が無い場合は RegionPackMissingHexGeometryException を送出する', () async {
      final connection = _openSeeded((_) {});
      addTearDown(connection.close);

      expect(
        () => buildFogHexFeatureCollectionFromRegionPack(connection),
        throwsA(isA<RegionPackMissingHexGeometryException>()),
      );
    });

    test(
      'boundary_geojson が NULL の場合（古いパック相当）は '
      'RegionPackMissingHexGeometryException を送出する',
      () async {
        final connection = RegionPackConnection.forTesting(
          seed: (db) {
            // Issue #105 より前のスキーマ（boundary_geojson 列なし）を再現する。
            db.execute('''
              CREATE TABLE hex_terrain (
                hex_id INTEGER PRIMARY KEY,
                terrain_type TEXT NOT NULL,
                feature_id INTEGER NOT NULL,
                cell_count INTEGER NOT NULL
              )
            ''');
            db.execute(
              'INSERT INTO hex_terrain (hex_id, terrain_type, feature_id, cell_count) '
              "VALUES (1, 'forest', 1, 1)",
            );
          },
        );
        addTearDown(connection.close);

        expect(
          () => buildFogHexFeatureCollectionFromRegionPack(connection),
          throwsA(isA<RegionPackMissingHexGeometryException>()),
        );
      },
    );
  });
}
