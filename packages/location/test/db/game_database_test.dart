import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【範囲】このテストは T030〜T034（Issue #83）の受け入れ基準のうち、
  // 「スキーマとマイグレーションが作成されている」ことを検証する。
  // 開示ヘクス集合の圧縮表現（T035・Issue #84）や実際のゲームロジックはスコープ外の
  // ため検証しない。パック更新の不変性ルール自体の実装（T036〜T037・Issue #84 →
  // Issue #96 でスナップショット方式に改訂）のうち、スキーマ・マイグレーションに
  // 関わる部分はこのファイルの disclosed_hex グループ、およびファイル末尾の
  // マイグレーション専用グループで検証する。

  group('GameDatabase.forTesting()', () {
    late GameDatabase database;

    setUp(() {
      database = GameDatabase.forTesting();
    });

    tearDown(() async {
      await database.close();
    });

    group('disclosed_hex（T031・T035〜T037・Issue #96 で terrain_type 列を追加）', () {
      test('hexId・terrain_type（開示時点のスナップショット）・pack_version を保存・復元できる', () async {
        await database.into(database.disclosedHexes).insert(
              DisclosedHexesCompanion.insert(
                hexId: const Value(123),
                terrainType: TerrainType.forest,
                packVersion: 'pack-v1',
              ),
            );

        final rows = await database.select(database.disclosedHexes).get();

        expect(rows, hasLength(1));
        expect(rows.single.hexId, 123);
        expect(rows.single.terrainType, TerrainType.forest);
        expect(rows.single.packVersion, 'pack-v1');
      });

      test('同じ hexId は一意である（1ヘクス1行）', () async {
        await database.into(database.disclosedHexes).insert(
              DisclosedHexesCompanion.insert(
                hexId: const Value(1),
                terrainType: TerrainType.forest,
                packVersion: 'pack-v1',
              ),
            );

        expect(
          () => database.into(database.disclosedHexes).insert(
                DisclosedHexesCompanion.insert(
                  hexId: const Value(1),
                  terrainType: TerrainType.vacantLot,
                  packVersion: 'pack-v2',
                ),
              ),
          throwsA(isA<sqlite3.SqliteException>()),
        );
      });

      test(
          'パック更新（アプリ更新）をまたいでも terrain_type は開示当時のまま変わらず、'
          '地形産出・建築可否判定の材料が揺らがない（Issue #96 受け入れ基準）', () async {
        // 開示した瞬間（T054 のスコープ）に、その時点の地形分類（森）をスナップショットする。
        await database.into(database.disclosedHexes).insert(
              DisclosedHexesCompanion.insert(
                hexId: const Value(42),
                terrainType: TerrainType.forest,
                packVersion: 'pack-v1',
              ),
            );

        // --- ここでアプリ更新（パック更新）が起きたとみなす ---
        // 新しいパックでは同じヘクスの地形分類が空き地に変わったとしても、
        // 本テーブルは一切書き換えない（disclosed_hex は開示判定ロジック・T054 の
        // 責務であり、パック更新それ自体が既存行を書き換えるトリガーにはならない）。
        // よって読み出し側は単純に再読み込みするだけで良い。

        final row = await (database.select(database.disclosedHexes)
              ..where((t) => t.hexId.equals(42)))
            .getSingle();

        // 地形分類は開示当時（森）のまま。パックを再度引く経路が無いため、
        // 「アプリ更新後に新パックの空き地扱いへ揺れる」ことは構造的に起こらない。
        expect(row.terrainType, TerrainType.forest);
        expect(terrainYieldOf(row.terrainType), {Resource.wood}); // 地形産出も不変
        expect(row.terrainType == TerrainType.vacantLot, isFalse); // 建築可否の材料も不変
        // pack_version 列は「いつ開示したか」の監査記録として、開示当時のまま残る。
        expect(row.packVersion, 'pack-v1');
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

    test('schemaVersion は 2（disclosed_hex.terrain_type 追加・Issue #96）', () {
      expect(database.schemaVersion, 2);
    });
  });

  // 【別グループにする理由】上の 'GameDatabase.forTesting()' グループの
  // setUp/tearDown が開いたままの database と、ここで手作りする migratedDb を
  // 同時に開いた状態にすると、drift の「同じ GameDatabase クラスが複数回
  // 生成された」警告（race condition の可能性を知らせるもの）が出てしまう。
  // 実害はない（別々の QueryExecutor で完全に独立している）が、警告を
  // 増やさないためテスト用DBの生存期間が重ならないよう独立したグループに分ける。
  group('disclosed_hex マイグレーション（v1 → v2・Issue #96）', () {
    test(
        'v1（terrain_type 列が無いスキーマ）から v2 への自動マイグレーションが機能する'
        '（旧スキーマは一度もリリースされていないためテーブル再作成方式）', () async {
      // v1 相当の disclosed_hex（terrain_type 列なし）を持つ生の SQLite DB を
      // 手作りし、PRAGMA user_version を 1 に設定しておく
      // （drift はこの値で onCreate/onUpgrade を切り替えるため）。
      final rawDatabase = sqlite3.sqlite3.openInMemory();
      rawDatabase.execute('''
        CREATE TABLE disclosed_hex (
          hex_id INTEGER NOT NULL PRIMARY KEY,
          pack_version TEXT NOT NULL,
          discovered_at INTEGER NOT NULL
        );
      ''');
      rawDatabase.execute('PRAGMA user_version = 1;');

      final migratedDb = GameDatabase(NativeDatabase.opened(rawDatabase));
      addTearDown(migratedDb.close);

      // マイグレーションは遅延実行されるため、実際にクエリを発行して発火させる。
      final rows = await migratedDb.select(migratedDb.disclosedHexes).get();
      expect(rows, isEmpty); // テーブル再作成のため v1 時点の行は引き継がれない（意図的）

      // 新しいスキーマ（terrain_type 列あり）へ実際に insert できることを確認する。
      await migratedDb.into(migratedDb.disclosedHexes).insert(
            DisclosedHexesCompanion.insert(
              hexId: const Value(1),
              terrainType: TerrainType.mountain,
              packVersion: 'pack-v2',
            ),
          );
      final afterInsert = await migratedDb.select(migratedDb.disclosedHexes).get();
      expect(afterInsert, hasLength(1));
      expect(afterInsert.single.terrainType, TerrainType.mountain);
    });
  });
}
