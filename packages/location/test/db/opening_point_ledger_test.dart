import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terra_town_location/terra_town_location.dart';

/// [OpeningPointBalanceStore.write] を2回目の呼び出しから必ず失敗させるフェイク
/// （`OpeningPointLedger.applyAccrual` のトランザクションがロールバックされることを
/// 検証するために使う。`terrain_yield_ledger_test.dart` の
/// `_ThrowsOnSecondAddInventoryRepository` と同じ手法）。
class _ThrowsOnSecondWriteBalanceStore implements OpeningPointBalanceStore {
  _ThrowsOnSecondWriteBalanceStore(this._delegate);

  final OpeningPointBalanceStore _delegate;
  int _writeCallCount = 0;

  @override
  Future<int> read() => _delegate.read();

  @override
  Future<void> write(int value) async {
    _writeCallCount++;
    if (_writeCallCount >= 2) {
      throw StateError('意図的な失敗（テスト用）');
    }
    await _delegate.write(value);
  }
}

void main() {
  // 【範囲】Issue #143 の受け入れ基準のうち、OpeningPointLedger（settingsテーブルの
  // ウォーターマーク・端数・所持ポイント数）を1つのトランザクションで書くこと・
  // 失敗時にロールバックされることを検証する。「セッションをまたがない」
  // 「移動窓の復元」等のロジックは OpeningPointAccrualCoordinator 側（app層）の
  // テストで検証する。

  group('OpeningPointLedger（インメモリDB）', () {
    late GameDatabase database;
    late OpeningPointLedger ledger;

    setUp(() {
      database = GameDatabase.forTesting();
      ledger = OpeningPointLedger(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('既定（未計上）は watermarkRowId=0・remainderMillimeters=0・points=0', () async {
      final snapshot = await ledger.readSnapshot();

      expect(snapshot.watermarkRowId, 0);
      expect(snapshot.remainderMillimeters, 0);
      expect(snapshot.points, 0);
    });

    test('applyAccrualでポイントが加算され、readSnapshotでウォーターマーク・端数が読み出せる', () async {
      await ledger.applyAccrual(
        grantedPoints: 2,
        remainderMillimeters: 1234,
        watermarkRowId: 42,
      );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.points, 2);
      expect(snapshot.watermarkRowId, 42);
      expect(snapshot.remainderMillimeters, 1234);
    });

    test('applyAccrualを複数回呼ぶとポイントは積み上がり、ウォーターマーク・端数は最新値で上書きされる', () async {
      await ledger.applyAccrual(
        grantedPoints: 1,
        remainderMillimeters: 100,
        watermarkRowId: 1,
      );
      await ledger.applyAccrual(
        grantedPoints: 1,
        remainderMillimeters: 200,
        watermarkRowId: 2,
      );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.points, 2);
      expect(snapshot.watermarkRowId, 2);
      expect(snapshot.remainderMillimeters, 200);
    });

    test('grantedPointsが0でもウォーターマーク・端数だけを進められる（セッション境界等）', () async {
      await ledger.applyAccrual(
        grantedPoints: 0,
        remainderMillimeters: 500000,
        watermarkRowId: 5,
      );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.points, 0);
      expect(snapshot.watermarkRowId, 5);
      expect(snapshot.remainderMillimeters, 500000);
    });

    test('解釈不能なウォーターマーク値（データ破損等）は0として扱う（罰しない側）', () async {
      await database.into(database.settings).insertOnConflictUpdate(
            const SettingsCompanion(
              key: Value(OpeningPointLedger.watermarkRowIdKey),
              value: Value('not-a-number'),
            ),
          );

      final snapshot = await ledger.readSnapshot();
      expect(snapshot.watermarkRowId, 0);
    });
  });

  group('OpeningPointLedger（トランザクションの原子性・失敗時のロールバック）', () {
    test('端数の書き込みより前段のポイント加算後に失敗しても、ポイントもウォーターマークも一切コミットされない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final throwingBalance =
          _ThrowsOnSecondWriteBalanceStore(OpeningPointBalanceRepository(database));
      final ledger = OpeningPointLedger(database, balanceStore: throwingBalance);

      // 1回目の applyAccrual は正常に成功させ、2回目の write で失敗させることで
      // 「2回目の呼び出しの内容が一切コミットされない」ことを検証する
      // （1回目のwriteは成功させておかないと、そもそも書き込みが1回も
      // 成功しないケースとの区別がつかないため）。
      await ledger.applyAccrual(
        grantedPoints: 1,
        remainderMillimeters: 100,
        watermarkRowId: 1,
      );

      await expectLater(
        ledger.applyAccrual(
          grantedPoints: 1,
          remainderMillimeters: 999,
          watermarkRowId: 2,
        ),
        throwsA(isA<StateError>()),
      );

      // 2回目の呼び出しはポイント加算処理自体は呼ばれたが、トランザクション全体が
      // ロールバックされるため、DBには1回目の状態のまま残っていること。
      final snapshot = await ledger.readSnapshot();
      expect(snapshot.points, 1);
      expect(snapshot.watermarkRowId, 1);
      expect(snapshot.remainderMillimeters, 100);
    });
  });

  group('OpeningPointLedger（アプリ再起動を模したファイルDBでの永続化）', () {
    test('保存後にDB接続を閉じ、同じファイルを開き直してもウォーターマーク・端数・ポイントが保持されている', () async {
      final tempDir = await Directory.systemTemp.createTemp('opening_point_ledger_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File(p.join(tempDir.path, 'game_state.sqlite'));

      final firstRun = GameDatabase(NativeDatabase(file));
      final firstLedger = OpeningPointLedger(firstRun);
      await firstLedger.applyAccrual(
        grantedPoints: 3,
        remainderMillimeters: 555,
        watermarkRowId: 7,
      );
      await firstRun.close();

      final secondRun = GameDatabase(NativeDatabase(file));
      addTearDown(secondRun.close);
      final secondLedger = OpeningPointLedger(secondRun);

      final snapshot = await secondLedger.readSnapshot();
      expect(snapshot.watermarkRowId, 7);
      expect(snapshot.remainderMillimeters, 555);
      expect(snapshot.points, 3);
    });
  });
}
