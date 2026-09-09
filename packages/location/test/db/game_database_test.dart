import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【範囲】このテストは T030〜T034（Issue #83）の受け入れ基準のうち、
  // 「スキーマとマイグレーションが作成されている」ことを検証する。
  // 開示ヘクス集合の圧縮表現・パック更新の不変性ルール（T035〜T037・Issue #84）や
  // 実際のゲームロジックはスコープ外のため検証しない。

  late GameDatabase database;

  setUp(() {
    database = GameDatabase.forTesting();
  });

  tearDown(() async {
    await database.close();
  });

  group('disclosed_hex（T031）', () {
    test('hexId と pack_version を保存・復元できる', () async {
      await database.into(database.disclosedHexes).insert(
            DisclosedHexesCompanion.insert(
              hexId: const Value(123),
              packVersion: 'pack-v1',
            ),
          );

      final rows = await database.select(database.disclosedHexes).get();

      expect(rows, hasLength(1));
      expect(rows.single.hexId, 123);
      expect(rows.single.packVersion, 'pack-v1');
    });

    test('同じ hexId は一意である（1ヘクス1行）', () async {
      await database.into(database.disclosedHexes).insert(
            DisclosedHexesCompanion.insert(
              hexId: const Value(1),
              packVersion: 'pack-v1',
            ),
          );

      expect(
        () => database.into(database.disclosedHexes).insert(
              DisclosedHexesCompanion.insert(
                hexId: const Value(1),
                packVersion: 'pack-v2',
              ),
            ),
        throwsA(isA<sqlite3.SqliteException>()),
      );
    });
  });

  group('inventory（T032）', () {
    test('core の Resource には依存せず、生の文字列キーで資材数を保存できる', () async {
      await database.into(database.inventories).insert(
            InventoriesCompanion.insert(resourceKey: 'wood', amount: const Value(10)),
          );

      final row = await (database.select(database.inventories)
            ..where((t) => t.resourceKey.equals('wood')))
          .getSingle();

      expect(row.amount, 10);
    });
  });

  group('building（T033）', () {
    test('docs/buildings.md §2 の8種すべてを表現できる', () {
      // 採石場（Issue #72）を含む8種であることを固定する回帰テスト。
      // 7種を前提にしたスキーマに戻さないためのガード。
      expect(BuildingType.values, hasLength(8));
      expect(BuildingType.values, contains(BuildingType.quarry));
    });

    test('建物種別・レベル・建築状態軸・ヘクス座標・区画を保存・復元できる', () async {
      await database.into(database.buildings).insert(
            BuildingsCompanion.insert(
              hexId: 42,
              buildingType: BuildingType.quarry,
              districtId: const Value('district-1'),
            ),
          );

      final row = await database.select(database.buildings).getSingle();

      expect(row.hexId, 42);
      expect(row.buildingType, BuildingType.quarry);
      expect(row.level, 1);
      expect(row.constructionState, BuildingConstructionState.built);
      expect(row.districtId, 'district-1');
    });

    test('1マス1建物: 同じ hexId には2件目を建てられない', () async {
      await database.into(database.buildings).insert(
            BuildingsCompanion.insert(
              hexId: 7,
              buildingType: BuildingType.house,
            ),
          );

      expect(
        () => database.into(database.buildings).insert(
              BuildingsCompanion.insert(
                hexId: 7,
                buildingType: BuildingType.apartment,
              ),
            ),
        throwsA(isA<sqlite3.SqliteException>()),
      );
    });
  });

  group('district_progress・collection・quest_daily・settings（T034）', () {
    test('district_progress: 制覇率・発展度を保存・復元できる', () async {
      await database.into(database.districtProgresses).insert(
            DistrictProgressesCompanion.insert(
              districtId: 'district-1',
              conquestRate: const Value(0.5),
              developmentScore: const Value(3.0),
            ),
          );

      final row = await database.select(database.districtProgresses).getSingle();

      expect(row.conquestRate, 0.5);
      expect(row.developmentScore, 3.0);
    });

    test('collection: POI の発見記録を保存・復元できる', () async {
      await database.into(database.collections).insert(
            CollectionsCompanion.insert(poiId: 'poi-1'),
          );

      final row = await database.select(database.collections).getSingle();

      expect(row.poiId, 'poi-1');
    });

    test('quest_daily: 進捗・達成状況を保存・復元できる', () async {
      final today = DateTime(2026, 9, 10);
      await database.into(database.questDailies).insert(
            QuestDailiesCompanion.insert(
              questDate: today,
              questKey: 'walk-1km',
              goal: 1000,
              progress: const Value(250),
            ),
          );

      final row = await database.select(database.questDailies).getSingle();

      expect(row.questKey, 'walk-1km');
      expect(row.progress, 250);
      expect(row.goal, 1000);
      expect(row.completed, isFalse);
    });

    test('settings: key-value を保存・復元できる', () async {
      await database.into(database.settings).insert(
            SettingsCompanion.insert(key: 'privacy_zones', value: '[]'),
          );

      final row = await (database.select(database.settings)
            ..where((t) => t.key.equals('privacy_zones')))
          .getSingle();

      expect(row.value, '[]');
    });
  });

  test('schemaVersion は 1（初期スキーマ）', () {
    expect(database.schemaVersion, 1);
  });
}
