import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_location/terra_town_location.dart';

/// [hexCentersFromRegionPack] のテスト（Issue #193・T090）。
///
/// `fog_hex_source_test.dart` と同じく、`tools/pack-builder/classify_terrain.py`
/// が実際に書き込むスキーマ・値の形をそのまま再現してシードする。
void _seedHexTerrain(
  sqlite3.Database db, {
  required int hexId,
  required List<List<double>>? boundaryRing,
}) {
  db.execute(
    'INSERT INTO hex_terrain (hex_id, terrain_type, feature_id, cell_count, boundary_geojson) '
    'VALUES (?, ?, ?, ?, ?)',
    [
      hexId,
      'vacant_lot',
      hexId,
      1,
      boundaryRing == null ? null : jsonEncode(boundaryRing),
    ],
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
          boundary_geojson TEXT
        )
      ''');
      seed(db);
    },
  );
}

void main() {
  group('hexCentersFromRegionPack', () {
    test('閉環の境界（先頭=末尾）の頂点を平均して中心を求める', () {
      final connection = _openSeeded((db) {
        _seedHexTerrain(
          db,
          hexId: 1,
          boundaryRing: [
            [0.0, 0.0],
            [0.0, 2.0],
            [2.0, 2.0],
            [2.0, 0.0],
            [0.0, 0.0], // 閉環（先頭と同じ点）
          ],
        );
      });
      addTearDown(connection.close);

      final centers = hexCentersFromRegionPack(connection, [1]);

      expect(centers, hasLength(1));
      expect(centers[1], [1.0, 1.0]);
    });

    test('2^53を超えるhexIdも正しく扱う（research.md §8.4 実測の最大値）', () {
      const hugeHexId = 626833456793083903; // 2^53を超える
      final connection = _openSeeded((db) {
        _seedHexTerrain(
          db,
          hexId: hugeHexId,
          boundaryRing: [
            [139.0, 35.0],
            [139.0, 35.002],
            [139.002, 35.002],
            [139.002, 35.0],
            [139.0, 35.0],
          ],
        );
      });
      addTearDown(connection.close);

      final centers = hexCentersFromRegionPack(connection, [hugeHexId]);

      expect(centers, hasLength(1));
      expect(centers[hugeHexId]![0], closeTo(139.001, 1e-9));
      expect(centers[hugeHexId]![1], closeTo(35.001, 1e-9));
    });

    test('要求したhexIdだけを返す（他の行は引かない）', () {
      final connection = _openSeeded((db) {
        _seedHexTerrain(
          db,
          hexId: 1,
          boundaryRing: [
            [0.0, 0.0],
            [0.0, 1.0],
            [1.0, 1.0],
            [0.0, 0.0],
          ],
        );
        _seedHexTerrain(
          db,
          hexId: 2,
          boundaryRing: [
            [10.0, 10.0],
            [10.0, 11.0],
            [11.0, 11.0],
            [10.0, 10.0],
          ],
        );
      });
      addTearDown(connection.close);

      final centers = hexCentersFromRegionPack(connection, [2]);

      expect(centers.keys, [2]);
    });

    test('hexIdsが空の場合は空のMapを返し、クエリを発行しない', () {
      final connection = _openSeeded((_) {});
      addTearDown(connection.close);

      final centers = hexCentersFromRegionPack(connection, const []);

      expect(centers, isEmpty);
    });

    test('hex_terrainに該当行が無いhexIdは結果に含めない（例外は投げない）', () {
      final connection = _openSeeded((_) {});
      addTearDown(connection.close);

      final centers = hexCentersFromRegionPack(connection, [999]);

      expect(centers, isEmpty);
    });

    test('boundary_geojsonがNULLのhexIdは結果に含めない（例外は投げない）', () {
      final connection = _openSeeded((db) {
        _seedHexTerrain(db, hexId: 1, boundaryRing: null);
      });
      addTearDown(connection.close);

      final centers = hexCentersFromRegionPack(connection, [1]);

      expect(centers, isEmpty);
    });
  });
}
