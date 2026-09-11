import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [InventoryRepository.add] を2回目の呼び出しから必ず失敗させるフェイク
/// （`TerrainYieldLedger.applyAccrual` のトランザクションがロールバックされることを
/// 検証するために使う）。
class _ThrowsOnSecondAddInventoryRepository implements InventoryRepository {
  _ThrowsOnSecondAddInventoryRepository(this._delegate);

  final InventoryRepository _delegate;
  int _callCount = 0;

  @override
  Future<void> add(Resource resource, int delta) async {
    _callCount++;
    if (_callCount >= 2) {
      throw StateError('意図的な失敗（テスト用）');
    }
    await _delegate.add(resource, delta);
  }

  @override
  Future<int> amountOf(Resource resource) => _delegate.amountOf(resource);

  @override
  Future<Map<Resource, int>> readAll() => _delegate.readAll();
}

void main() {
  // 【範囲】Issue #138 の受け入れ基準のうち、TerrainYieldLedger（settingsテーブルの
  // ウォーターマーク・端数、inventoryテーブルの資材加算）を1つのトランザクションで
  // 書くこと・失敗時にロールバックされることを検証する。
  // 「区間開始時点の開示済みヘクスを使う」「セッションをまたがない」等の
  // ロジックは TerrainYieldAccrualCoordinator 側（app層）のテストで検証する。

  group('TerrainYieldLedger（インメモリDB）', () {
    late GameDatabase database;
    late TerrainYieldLedger ledger;

    setUp(() {
      database = GameDatabase.forTesting();
      ledger = TerrainYieldLedger(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('既定（未計上）は watermarkRowId=0・remainderMicros=空', () async {
      final snapshot = await ledger.readSnapshot();

      expect(snapshot.watermarkRowId, 0);
      expect(snapshot.remainderMicros, isEmpty);
    });

    test('applyAccrualで資材が加算され、readSnapshotでウォーターマーク・端数が読み出せる', () async {
      await ledger.applyAccrual(
        grantedAmounts: {Resource.wood: 2},
        remainderMicros: {Resource.wood: 1234},
        watermarkRowId: 42,
      );

      final inventory = InventoryRepository(database);
      expect(await inventory.amountOf(Resource.wood), 2);

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.watermarkRowId, 42);
      expect(snapshot.remainderMicros, {Resource.wood: 1234});
    });

    test('applyAccrualを複数回呼ぶと資材は積み上がり、ウォーターマーク・端数は最新値で上書きされる', () async {
      await ledger.applyAccrual(
        grantedAmounts: {Resource.wood: 1},
        remainderMicros: {Resource.wood: 100},
        watermarkRowId: 1,
      );
      await ledger.applyAccrual(
        grantedAmounts: {Resource.wood: 1},
        remainderMicros: {Resource.wood: 200},
        watermarkRowId: 2,
      );

      final inventory = InventoryRepository(database);
      expect(await inventory.amountOf(Resource.wood), 2);

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.watermarkRowId, 2);
      expect(snapshot.remainderMicros, {Resource.wood: 200});
    });

    test('grantedAmountsが空でもウォーターマーク・端数だけを進められる（セッション境界等）', () async {
      await ledger.applyAccrual(
        grantedAmounts: const {},
        remainderMicros: const {},
        watermarkRowId: 5,
      );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.watermarkRowId, 5);
      expect(snapshot.remainderMicros, isEmpty);
    });

    test('端数0の資材はremainderMicrosに保存されない（無限に肥大化しない）', () async {
      await ledger.applyAccrual(
        grantedAmounts: {Resource.wood: 1},
        remainderMicros: {Resource.wood: 0, Resource.stone: 500},
        watermarkRowId: 1,
      );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.remainderMicros, {Resource.stone: 500});
    });

    test('解釈不能なremainder値（データ破損等）は端数なしとして扱う（罰しない側）', () async {
      await database.into(database.settings).insertOnConflictUpdate(
            const SettingsCompanion(
              key: Value(TerrainYieldLedger.remainderMicrosKey),
              value: Value('not-json'),
            ),
          );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.remainderMicros, isEmpty);
    });
  });

  group('TerrainYieldLedger（トランザクションの原子性・失敗時のロールバック）', () {
    test('grantedAmountsの2件目の加算で失敗すると、1件目の加算もウォーターマークも一切コミットされない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final throwingInventory =
          _ThrowsOnSecondAddInventoryRepository(InventoryRepository(database));
      final ledger = TerrainYieldLedger(database, inventoryRepository: throwingInventory);

      await expectLater(
        ledger.applyAccrual(
          grantedAmounts: {Resource.wood: 1, Resource.stone: 1},
          remainderMicros: {Resource.wood: 999},
          watermarkRowId: 10,
        ),
        throwsA(isA<StateError>()),
      );

      // 1件目（wood）は加算処理自体は呼ばれたが、トランザクション全体が
      // ロールバックされるため、DBには一切反映されていないこと。
      final inventory = InventoryRepository(database);
      expect(await inventory.amountOf(Resource.wood), 0);
      expect(await inventory.amountOf(Resource.stone), 0);

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.watermarkRowId, 0);
      expect(snapshot.remainderMicros, isEmpty);
    });
  });

  group('TerrainYieldLedger（アプリ再起動を模したファイルDBでの永続化）', () {
    test('保存後にDB接続を閉じ、同じファイルを開き直してもウォーターマーク・端数・資材が保持されている', () async {
      final tempDir = await Directory.systemTemp.createTemp('terrain_yield_ledger_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File(p.join(tempDir.path, 'game_state.sqlite'));

      final firstRun = GameDatabase(NativeDatabase(file));
      final firstLedger = TerrainYieldLedger(firstRun);
      await firstLedger.applyAccrual(
        grantedAmounts: {Resource.wood: 3},
        remainderMicros: {Resource.wood: 555},
        watermarkRowId: 7,
      );
      await firstRun.close();

      final secondRun = GameDatabase(NativeDatabase(file));
      addTearDown(secondRun.close);
      final secondLedger = TerrainYieldLedger(secondRun);

      final snapshot = await secondLedger.readSnapshot();
      expect(snapshot.watermarkRowId, 7);
      expect(snapshot.remainderMicros, {Resource.wood: 555});
      expect(await InventoryRepository(secondRun).amountOf(Resource.wood), 3);
    });
  });
}
