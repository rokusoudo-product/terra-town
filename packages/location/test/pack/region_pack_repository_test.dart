import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [RegionPackRepository]（tasks.md T069・Issue #137）のテスト。
///
/// 合成データ（少数のフェイク行）による決定的な単体テストに加え、末尾で
/// 同梱の実パック（`app/assets/pack/region_pack.sqlite`）が存在する場合のみ実行する
/// 結合テストを持つ（`app/test/map/region_pack_fog_geometry_test.dart` と同じ方針。
/// `packages/location` から見て `../../app/assets/pack/region_pack.sqlite`）。
void main() {
  group('RegionPackRepository（合成データ）', () {
    RegionPackConnection openSeeded({
      String packVersion = 'test-v1',
      List<Map<String, Object?>> hexRows = const [],
      bool withDistrictTables = false,
      bool withPoiTable = false,
    }) {
      return RegionPackConnection.forTesting(
        seed: (db) {
          db.execute(
            'CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)',
          );
          db.execute(
            "INSERT INTO pack_meta (key, value) VALUES ('pack_version', ?)",
            [packVersion],
          );
          db.execute(
            'CREATE TABLE hex_terrain ('
            'hex_id INTEGER PRIMARY KEY, terrain_type TEXT NOT NULL, '
            'feature_id INTEGER NOT NULL, cell_count INTEGER NOT NULL, '
            'boundary_geojson TEXT NOT NULL)',
          );
          for (final row in hexRows) {
            db.execute(
              'INSERT INTO hex_terrain '
              '(hex_id, terrain_type, feature_id, cell_count, boundary_geojson) '
              'VALUES (?, ?, ?, ?, ?)',
              [
                row['hex_id'],
                row['terrain_type'],
                row['feature_id'] ?? 0,
                row['cell_count'] ?? 1,
                '[]',
              ],
            );
          }
          if (withDistrictTables) {
            db.execute(
              'CREATE TABLE district (district_id TEXT PRIMARY KEY, name TEXT NOT NULL, '
              'prefecture_name TEXT NOT NULL, county_name TEXT NOT NULL, '
              'geometry_geojson TEXT NOT NULL)',
            );
            db.execute(
              "INSERT INTO district VALUES ('13101', '千代田区', '東京都', '', '{}')",
            );
            db.execute(
              'CREATE TABLE hex_district (hex_id INTEGER PRIMARY KEY, district_id TEXT NOT NULL)',
            );
            db.execute('INSERT INTO hex_district VALUES (1, ?)', ['13101']);
          }
          if (withPoiTable) {
            db.execute(
              'CREATE TABLE poi (id TEXT PRIMARY KEY, lat REAL NOT NULL, '
              'lon REAL NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL)',
            );
            db.execute(
              "INSERT INTO poi VALUES ('node/1', 35.0, 135.0, 'shrine', '六創堂神社')",
            );
          }
        },
      );
    }

    test('pack_meta の pack_version を読み取る', () {
      final connection = openSeeded(packVersion: 'sayamako-v1-abc');
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.version, const PackVersion('sayamako-v1-abc'));
    });

    test('hex_terrain の snake_case terrain_type をTerrainType enumへ変換する', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'vacant_lot'},
          {'hex_id': 2, 'terrain_type': 'forest'},
          {'hex_id': 3, 'terrain_type': 'mountain'},
          {'hex_id': 4, 'terrain_type': 'waterside'},
          {'hex_id': 5, 'terrain_type': 'sea'},
        ],
      );
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.terrainOf(const HexId(1)), TerrainType.vacantLot);
      expect(repo.terrainOf(const HexId(2)), TerrainType.forest);
      expect(repo.terrainOf(const HexId(3)), TerrainType.mountain);
      expect(repo.terrainOf(const HexId(4)), TerrainType.waterside);
      expect(repo.terrainOf(const HexId(5)), TerrainType.sea);
    });

    test('パックに収録されていないヘクスは terrainOf が null', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'forest'},
        ],
      );
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.terrainOf(const HexId(999)), isNull);
    });

    test('未知の terrain_type 文字列は StateError（fail-loud）', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'unknown_terrain'},
        ],
      );
      addTearDown(connection.close);

      expect(() => RegionPackRepository.load(connection), throwsStateError);
    });

    test('pack_meta に pack_version が無い場合は StateError', () {
      final connection = RegionPackConnection.forTesting(
        seed: (db) {
          db.execute('CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)');
          db.execute(
            'CREATE TABLE hex_terrain (hex_id INTEGER PRIMARY KEY, terrain_type TEXT NOT NULL, '
            'feature_id INTEGER NOT NULL, cell_count INTEGER NOT NULL, '
            'boundary_geojson TEXT NOT NULL)',
          );
        },
      );
      addTearDown(connection.close);

      expect(() => RegionPackRepository.load(connection), throwsStateError);
    });

    test('district/hex_district テーブルが無い場合は districtOf が常に null・districts が空', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'forest'},
        ],
      );
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.districtOf(const HexId(1)), isNull);
      expect(repo.districts, isEmpty);
    });

    test('district/hex_district テーブルがある場合は実データを返す（forward-compat・Issue #86）', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'forest'},
        ],
        withDistrictTables: true,
      );
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.districtOf(const HexId(1)), const DistrictId('13101'));
      expect(repo.districts, [
        const District(id: DistrictId('13101'), name: '千代田区'),
      ]);
    });

    test('poi テーブルが無い場合は pointsOfInterest が空', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'forest'},
        ],
      );
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.pointsOfInterest, isEmpty);
    });

    test('poi テーブルがある場合は実データを返す（forward-compat・Issue #86）', () {
      final connection = openSeeded(
        hexRows: [
          {'hex_id': 1, 'terrain_type': 'forest'},
        ],
        withPoiTable: true,
      );
      addTearDown(connection.close);

      final repo = RegionPackRepository.load(connection);

      expect(repo.pointsOfInterest, [
        const PointOfInterest(
          id: PointOfInterestId('node/1'),
          name: '六創堂神社',
          kind: 'shrine',
          latitude: 35.0,
          longitude: 135.0,
        ),
      ]);
    });
  });

  group('RegionPackRepository（同梱の実パック・存在する場合のみ）', () {
    // packages/location/ から見た同梱パックの相対パス。
    const packPath = '../../app/assets/pack/region_pack.sqlite';

    test('実データ13,106件でterrainOfがStateErrorを投げない（enumマッピングの網羅確認）', () {
      if (!File(packPath).existsSync()) {
        markTestSkipped(
          '$packPath が存在しません（tools/pack-builder/bundle_region_pack.sh '
          '未実行の環境。Issue #85の方針により生成物はコミットしない）。',
        );
        return;
      }

      final connection = RegionPackConnection.open(packPath);
      addTearDown(connection.close);

      // load() 自体が全行の terrain_type 変換を行うため、例外なく完了することが
      // 「地域パック生成コードと core の TerrainType 定義がずれていない」ことの検証になる。
      final repo = RegionPackRepository.load(connection);

      expect(repo.version, isNotNull);
      // 狭山湖周辺パックの既知の1ヘクス（research.md §8.0 実測）で最低限の疎通を確認する。
      expect(repo.terrainOf(const HexId(626833455896940543)), TerrainType.vacantLot);
    });
  });
}
