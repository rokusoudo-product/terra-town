// SaveDataTransferService（Issue #180・T105）の単体テスト。
//
// Issue #180 受け入れ基準の「単体テスト」6項目をすべて検証する:
//   1. 往復（書き出し→読み込み）で7テーブルが一致する
//   2. 同じ端末で書き出し→読み込みしても、開放ポイント・資材・開示数が変わらず、
//      ウォーターマーク＝端末の最大id
//   3. 新しい端末を想定し、端末の最大idが0のときウォーターマークが0になる
//   4. 新しいschema_versionを拒否する
//   5. 壊れたファイルでロールバックされる
//   6. 大きなhex_id（2^53超）が往復で変わらない
//
// Pigeon（LocationPointIdSource の既定実装）・SAF（SaveDataFileChannel）には
// 一切触れない（フェイクを注入する）。

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [LocationPointIdSource] のフェイク（値を差し替え可能にしてある）。
class _FakeLocationPointIdSource implements LocationPointIdSource {
  _FakeLocationPointIdSource(this.value);

  int value;

  @override
  Future<int> getMaxLocationPointId() async => value;
}

/// [SaveDataBackupWriter] のフェイク（書き込んだ内容を記録するだけ）。
class _FakeBackupWriter implements SaveDataBackupWriter {
  final List<String> written = [];

  @override
  Future<String> write(String jsonContents) async {
    written.add(jsonContents);
    return '/fake/backups/pre-import-${written.length}.json';
  }
}

/// 常に失敗する [SaveDataBackupWriter]（バックアップ失敗時に DB へ触れないことの
/// 検証に使う）。
class _ThrowingBackupWriter implements SaveDataBackupWriter {
  @override
  Future<String> write(String jsonContents) async {
    throw StateError('バックアップ書き込み失敗（テスト用）');
  }
}

/// 2^53（9007199254740992）を超える、実機の H3 解像度11セルインデックス相当の
/// 桁数を持つ架空の hexId（実在の座標には対応しない）。
const int _bigHexId = 700123456789012345;

/// 7テーブルすべてに1行ずつ、それぞれ意味のある値を入れる（往復比較用）。
Future<void> _seedFullSaveData(
  GameDatabase database, {
  int hexId = _bigHexId,
}) async {
  await database
      .into(database.disclosedHexes)
      .insert(
        DisclosedHexesCompanion.insert(
          hexId: Value(hexId),
          terrainType: TerrainType.forest,
          packVersion: 'pack-v1',
          discoveredAt: Value(DateTime.utc(2026, 9, 1, 12)),
        ),
      );
  await database
      .into(database.inventories)
      .insert(
        InventoriesCompanion.insert(
          resourceKey: 'wood',
          amount: const Value(5),
          updatedAt: Value(DateTime.utc(2026, 9, 1, 12)),
        ),
      );
  await database
      .into(database.buildings)
      .insert(
        BuildingsCompanion.insert(
          hexId: hexId,
          buildingType: BuildingType.house,
          districtId: const Value('district-1'),
          builtAt: Value(DateTime.utc(2026, 9, 2)),
        ),
      );
  await database
      .into(database.districtProgresses)
      .insert(
        DistrictProgressesCompanion.insert(
          districtId: 'district-1',
          conquestRate: const Value(0.5),
          developmentScore: const Value(1.5),
          updatedAt: Value(DateTime.utc(2026, 9, 2)),
        ),
      );
  await database
      .into(database.collections)
      .insert(
        CollectionsCompanion.insert(
          poiId: 'poi-1',
          kind: const Value('tourism'),
          name: const Value('名所A'),
          isBonus: const Value(false),
          collectMethod: const Value(CollectMethod.walk),
          bonusGranted: const Value(0),
          discoveredAt: Value(DateTime.utc(2026, 9, 3)),
        ),
      );
  await database
      .into(database.questDailies)
      .insert(
        QuestDailiesCompanion.insert(
          questDate: DateTime.utc(2026, 9, 4),
          questKey: 'walk_1km',
          goal: 1,
          progress: const Value(1),
          completed: const Value(true),
          completedAt: Value(DateTime.utc(2026, 9, 4, 8)),
        ),
      );
  await database
      .into(database.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: OpeningPointLedger.pointsKey,
          value: '3',
        ),
      );
  await database
      .into(database.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: OpeningPointLedger.remainderMillimetersKey,
          value: '250',
        ),
      );
  await database
      .into(database.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: TerrainYieldLedger.watermarkRowIdKey,
          value: '55', // 元の端末でのウォーターマーク（読み込み先では上書きされる）。
        ),
      );
}

class _AllTables {
  const _AllTables({
    required this.disclosedHexes,
    required this.inventories,
    required this.buildings,
    required this.districtProgresses,
    required this.collections,
    required this.questDailies,
    required this.settings,
  });

  final List<DisclosedHexRow> disclosedHexes;
  final List<InventoryRow> inventories;
  final List<BuildingRow> buildings;
  final List<DistrictProgressRow> districtProgresses;
  final List<CollectionRow> collections;
  final List<QuestDailyRow> questDailies;
  final List<SettingRow> settings;
}

Future<_AllTables> _readAll(GameDatabase database) async {
  return _AllTables(
    disclosedHexes: await database.select(database.disclosedHexes).get(),
    inventories: await database.select(database.inventories).get(),
    buildings: await database.select(database.buildings).get(),
    districtProgresses: await database.select(database.districtProgresses).get(),
    collections: await database.select(database.collections).get(),
    questDailies: await database.select(database.questDailies).get(),
    settings: await database.select(database.settings).get(),
  );
}

void main() {
  group('SaveDataTransferService（往復・同一端末・新端末）', () {
    late GameDatabase database;
    late _FakeLocationPointIdSource idSource;
    late SaveDataTransferService service;

    setUp(() async {
      database = GameDatabase.forTesting();
      idSource = _FakeLocationPointIdSource(0);
      service = SaveDataTransferService(
        database,
        locationPointIdSource: idSource,
      );
      await _seedFullSaveData(database);
    });

    tearDown(() => database.close());

    test('往復（書き出し→読み込み）で7テーブルが一致する（大きなhex_idも含む）', () async {
      final before = await _readAll(database);
      expect(before.disclosedHexes.single.hexId, _bigHexId);
      expect(_bigHexId, greaterThan(9007199254740992)); // 2^53 超であることの前提確認

      final exported = await service.exportToJsonString(
        appVersion: '1.0.0+1',
        packVersion: 'pack-v1',
      );

      // JSON上ではhex_idが10進文字列であること（丸め対策）。
      final decoded = jsonDecode(exported) as Map<String, dynamic>;
      final disclosedHexJson =
          (decoded['tables'] as Map<String, dynamic>)['disclosed_hex'] as List;
      expect(disclosedHexJson.single['hex_id'], _bigHexId.toString());

      idSource.value = 0; // このテストの主眼は「7テーブル一致」であり端末maxIdは0のまま。
      await service.importFromJsonString(
        exported,
        backupWriter: _FakeBackupWriter(),
      );

      final after = await _readAll(database);
      expect(after.disclosedHexes, unorderedEquals(before.disclosedHexes));
      expect(after.inventories, unorderedEquals(before.inventories));
      expect(after.buildings, unorderedEquals(before.buildings));
      expect(
        after.districtProgresses,
        unorderedEquals(before.districtProgresses),
      );
      expect(after.collections, unorderedEquals(before.collections));
      expect(after.questDailies, unorderedEquals(before.questDailies));

      // settings は watermark 系2キーだけ意図的に上書きされるため、
      // それ以外のキーが一致することを確認する。
      final beforeOthers = before.settings
          .where(
            (s) =>
                s.key != TerrainYieldLedger.watermarkRowIdKey &&
                s.key != OpeningPointLedger.watermarkRowIdKey,
          )
          .toList();
      final afterOthers = after.settings
          .where(
            (s) =>
                s.key != TerrainYieldLedger.watermarkRowIdKey &&
                s.key != OpeningPointLedger.watermarkRowIdKey,
          )
          .toList();
      expect(afterOthers, unorderedEquals(beforeOthers));
    });

    test(
      '同じ端末で書き出し→読み込みしても開放ポイント・資材・開示数は変わらず、'
      'ウォーターマーク＝端末の最大id',
      () async {
        idSource.value = 120; // 「この端末には既に120件の記録がある」という想定。

        final exported = await service.exportToJsonString();
        await service.importFromJsonString(
          exported,
          backupWriter: _FakeBackupWriter(),
        );

        final after = await _readAll(database);
        expect(after.disclosedHexes, hasLength(1));
        expect(after.collections, hasLength(1));

        final points = after.settings.firstWhere(
          (s) => s.key == OpeningPointLedger.pointsKey,
        );
        expect(points.value, '3'); // 変わらない。

        final watermark = after.settings.firstWhere(
          (s) => s.key == TerrainYieldLedger.watermarkRowIdKey,
        );
        expect(watermark.value, '120'); // 端末の最大idに補正される。

        final openingWatermark = after.settings.firstWhere(
          (s) => s.key == OpeningPointLedger.watermarkRowIdKey,
        );
        expect(openingWatermark.value, '120');
      },
    );

    test('新しい端末を想定し、端末の最大idが0のときウォーターマークが0になる', () async {
      // 元データの watermark は "55"（_seedFullSaveData）だが、読み込み先端末には
      // 位置記録が1件も無い（maxId=0）。
      idSource.value = 0;

      final exported = await service.exportToJsonString();
      await service.importFromJsonString(
        exported,
        backupWriter: _FakeBackupWriter(),
      );

      final after = await _readAll(database);
      final watermark = after.settings.firstWhere(
        (s) => s.key == TerrainYieldLedger.watermarkRowIdKey,
      );
      expect(watermark.value, '0');
    });
  });

  group('SaveDataTransferService（拒否・ロールバック）', () {
    test('新しいschema_versionを拒否し、DBは変わらない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);
      final service = SaveDataTransferService(
        database,
        locationPointIdSource: _FakeLocationPointIdSource(0),
        currentSchemaVersion: 3,
      );
      await _seedFullSaveData(database);
      final before = await _readAll(database);

      final tooNewJson = jsonEncode({
        'format_version': 1,
        'schema_version': 4, // currentSchemaVersion(3) より新しい。
        'pack_version': 'pack-v1',
        'app_version': '1.0.0+1',
        'exported_at': '2026-09-14T00:00:00.000Z',
        'tables': {
          'disclosed_hex': [],
          'inventory': [],
          'building': [],
          'district_progress': [],
          'collection': [],
          'quest_daily': [],
          'settings': [],
        },
      });

      expect(
        () => service.parseSummary(tooNewJson),
        throwsA(isA<SaveDataSchemaTooNewException>()),
      );

      final backupWriter = _FakeBackupWriter();
      await expectLater(
        service.importFromJsonString(tooNewJson, backupWriter: backupWriter),
        throwsA(isA<SaveDataSchemaTooNewException>()),
      );
      expect(backupWriter.written, isEmpty); // 検証前に弾かれ、バックアップにも進まない。

      final after = await _readAll(database);
      expect(after.disclosedHexes, unorderedEquals(before.disclosedHexes));
      expect(after.settings, unorderedEquals(before.settings));
    });

    test('壊れたJSONファイルは拒否され、DBは変わらない（バックアップにも進まない）', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);
      final service = SaveDataTransferService(
        database,
        locationPointIdSource: _FakeLocationPointIdSource(0),
      );
      await _seedFullSaveData(database);
      final before = await _readAll(database);

      final backupWriter = _FakeBackupWriter();
      await expectLater(
        service.importFromJsonString(
          '{ この文字列は正しいJSONではない',
          backupWriter: backupWriter,
        ),
        throwsA(isA<SaveDataFormatException>()),
      );
      expect(backupWriter.written, isEmpty);

      final after = await _readAll(database);
      expect(after.disclosedHexes, unorderedEquals(before.disclosedHexes));
    });

    test('必須キーが欠けたファイルは拒否され、DBは変わらない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);
      final service = SaveDataTransferService(
        database,
        locationPointIdSource: _FakeLocationPointIdSource(0),
      );
      await _seedFullSaveData(database);
      final before = await _readAll(database);

      final missingKeysJson = jsonEncode({
        'format_version': 1,
        'schema_version': 3,
        // pack_version・app_version・exported_at が欠けている。
        'tables': {
          'disclosed_hex': [],
          'inventory': [],
          'building': [],
          'district_progress': [],
          'collection': [],
          'quest_daily': [],
          'settings': [],
        },
      });

      await expectLater(
        service.importFromJsonString(
          missingKeysJson,
          backupWriter: _FakeBackupWriter(),
        ),
        throwsA(isA<SaveDataFormatException>()),
      );

      final after = await _readAll(database);
      expect(after.disclosedHexes, unorderedEquals(before.disclosedHexes));
    });

    test(
      'バックアップの書き込みに失敗した場合はDBに一切触れない（上書き前の安全策）',
      () async {
        final database = GameDatabase.forTesting();
        addTearDown(database.close);
        final service = SaveDataTransferService(
          database,
          locationPointIdSource: _FakeLocationPointIdSource(0),
        );
        await _seedFullSaveData(database);
        final before = await _readAll(database);

        final exported = await service.exportToJsonString();

        await expectLater(
          service.importFromJsonString(
            exported,
            backupWriter: _ThrowingBackupWriter(),
          ),
          throwsA(isA<SaveDataBackupFailedException>()),
        );

        final after = await _readAll(database);
        expect(after.disclosedHexes, unorderedEquals(before.disclosedHexes));
      },
    );

    test(
      '構造的には正しいが制約違反（buildingのhex_id重複）のファイルはロールバックされ、'
      '7テーブルとも読み込み前の状態のまま',
      () async {
        final database = GameDatabase.forTesting();
        addTearDown(database.close);
        final service = SaveDataTransferService(
          database,
          locationPointIdSource: _FakeLocationPointIdSource(0),
        );
        await _seedFullSaveData(database);
        final before = await _readAll(database);

        final exported = await service.exportToJsonString();
        final decoded = jsonDecode(exported) as Map<String, dynamic>;
        final tables = decoded['tables'] as Map<String, dynamic>;
        final buildingRow =
            (tables['building'] as List).single as Map<String, dynamic>;
        // building.hex_id はユニーク制約（「1マス1建物」）。同じ hex_id を持つ
        // 2行目を混入させ、挿入の途中で制約違反を起こす。
        tables['building'] = [
          buildingRow,
          Map<String, dynamic>.from(buildingRow)..['district_id'] = 'district-2',
        ];
        final corrupted = jsonEncode(decoded);

        final backupWriter = _FakeBackupWriter();
        await expectLater(
          service.importFromJsonString(corrupted, backupWriter: backupWriter),
          throwsA(isA<SaveDataImportFailedException>()),
        );
        // バックアップ自体は（削除・挿入の前に）成功していること。
        expect(backupWriter.written, hasLength(1));

        final after = await _readAll(database);
        expect(after.disclosedHexes, unorderedEquals(before.disclosedHexes));
        expect(after.inventories, unorderedEquals(before.inventories));
        expect(after.buildings, unorderedEquals(before.buildings));
        expect(
          after.districtProgresses,
          unorderedEquals(before.districtProgresses),
        );
        expect(after.collections, unorderedEquals(before.collections));
        expect(after.questDailies, unorderedEquals(before.questDailies));
        expect(after.settings, unorderedEquals(before.settings));
      },
    );
  });

  group('SaveDataTransferService（要約）', () {
    test('parseSummaryはexported_at・開示数・開放ポイント・収集数を返す', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);
      final service = SaveDataTransferService(
        database,
        locationPointIdSource: _FakeLocationPointIdSource(0),
      );
      await _seedFullSaveData(database);

      final exportedAt = DateTime.utc(2026, 9, 14, 10, 30);
      final exported = await service.exportToJsonString(exportedAt: exportedAt);

      final summary = service.parseSummary(exported);
      expect(summary.exportedAt, exportedAt);
      expect(summary.disclosedHexCount, 1);
      expect(summary.openingPoints, 3);
      expect(summary.collectionCount, 1);
    });
  });

  group('SaveDataTransferService（書き出し内容の検証）', () {
    test('書き出したJSONに位置記録（location_track）の内容は含まれない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);
      final service = SaveDataTransferService(
        database,
        locationPointIdSource: _FakeLocationPointIdSource(0),
      );
      await _seedFullSaveData(database);

      final exported = await service.exportToJsonString();
      final decoded = jsonDecode(exported) as Map<String, dynamic>;

      expect(decoded['tables'], isA<Map<String, dynamic>>());
      expect(
        (decoded['tables'] as Map<String, dynamic>).keys,
        unorderedEquals(kSaveDataTableNames),
      );
      expect(exported.contains('location_point'), isFalse);
      expect(exported.contains('location_track'), isFalse);
    });
  });
}
