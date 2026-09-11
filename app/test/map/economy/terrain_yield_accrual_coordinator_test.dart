import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/map/economy/terrain_yield_accrual_coordinator.dart';

/// [TerrainYieldLedgerStore] のオンメモリフェイク（`applyAccrual` の呼び出し回数・
/// 引数を記録できる。特定回数目で意図的に失敗させることもできる）。
class _FakeLedger implements TerrainYieldLedgerStore {
  int watermarkRowId = 0;
  Map<Resource, int> remainderMicros = {};

  final List<_ApplyCall> calls = [];
  bool throwOnNextApply = false;

  @override
  Future<TerrainYieldLedgerSnapshot> readSnapshot() async {
    return TerrainYieldLedgerSnapshot(
      watermarkRowId: watermarkRowId,
      remainderMicros: Map.of(remainderMicros),
    );
  }

  @override
  Future<void> applyAccrual({
    required Map<Resource, int> grantedAmounts,
    required Map<Resource, int> remainderMicros,
    required int watermarkRowId,
  }) async {
    if (throwOnNextApply) {
      throwOnNextApply = false;
      throw StateError('意図的な失敗（テスト用）');
    }
    calls.add(_ApplyCall(
      grantedAmounts: grantedAmounts,
      remainderMicros: remainderMicros,
      watermarkRowId: watermarkRowId,
    ));
    this.watermarkRowId = watermarkRowId;
    this.remainderMicros = Map.of(remainderMicros);
  }
}

class _ApplyCall {
  _ApplyCall({
    required this.grantedAmounts,
    required this.remainderMicros,
    required this.watermarkRowId,
  });

  final Map<Resource, int> grantedAmounts;
  final Map<Resource, int> remainderMicros;
  final int watermarkRowId;
}

LocationPointRecord _record({
  required int rowId,
  required String sessionId,
  required int elapsedMicros,
  int hexId = 1,
}) {
  return LocationPointRecord(
    rowId: rowId,
    position: GeoPosition(
      latitude: 35.0,
      longitude: 135.0,
      timestamp: DateTime.fromMicrosecondsSinceEpoch(elapsedMicros, isUtc: true),
      trackingSessionId: sessionId,
      hexId: HexId(hexId),
    ),
  );
}

void main() {
  group('TerrainYieldAccrualCoordinator', () {
    test('初回（直前の点が無い）では経過時間0として扱われ、産出は起きないがウォーターマークは進む', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(
        _record(rowId: 1, sessionId: 's', elapsedMicros: 0),
        {TerrainType.forest: 1},
      );

      expect(ledger.calls, hasLength(1));
      expect(ledger.calls.single.grantedAmounts, isEmpty);
      expect(ledger.calls.single.watermarkRowId, 1);
      expect(coordinator.watermarkRowId, 1);
    });

    test('同一セッション内の連続する2点の差分だけが積算される', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(
        _record(rowId: 1, sessionId: 's', elapsedMicros: 0),
        {TerrainType.forest: 1},
      );
      await coordinator.accrue(
        _record(rowId: 2, sessionId: 's', elapsedMicros: terrainYieldMicrosecondsPerUnit),
        {TerrainType.forest: 1},
      );

      expect(ledger.calls, hasLength(2));
      expect(ledger.calls.last.grantedAmounts, {Resource.wood: 1});
    });

    test('セッションをまたぐと経過時間0として扱われる（積算しない）', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(
        _record(rowId: 1, sessionId: 'session-a', elapsedMicros: 0),
        {TerrainType.forest: 1},
      );
      // session-b は単調時計がリセットされたことを表すため、大きな時刻差があっても
      // 経過時間として扱ってはならない。
      await coordinator.accrue(
        _record(rowId: 2, sessionId: 'session-b', elapsedMicros: terrainYieldMicrosecondsPerUnit * 10),
        {TerrainType.forest: 1},
      );

      expect(ledger.calls.last.grantedAmounts, isEmpty);
    });

    test('(a) 起動のたびに全件が流れ直しても計上済みの区間はスキップされる（二重計上しない）', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, sessionId: 's', elapsedMicros: 0);
      final r2 = _record(rowId: 2, sessionId: 's', elapsedMicros: terrainYieldMicrosecondsPerUnit);
      await coordinator.accrue(r1, {TerrainType.forest: 1});
      await coordinator.accrue(r2, {TerrainType.forest: 1});
      expect(ledger.calls, hasLength(2));

      // 「アプリ再起動」を模して、同じ ledger を使う新しいコーディネータを作り、
      // 全件（r1・r2）を最初から流し直す。
      final restarted = TerrainYieldAccrualCoordinator(ledger: ledger);
      await restarted.initialize();
      await restarted.accrue(r1, {TerrainType.forest: 1});
      await restarted.accrue(r2, {TerrainType.forest: 1});

      // ウォーターマーク以下の行なので ledger への書き込みは一切発生しない。
      expect(ledger.calls, hasLength(2));
      expect(await InventoryTotalsForTest.wood(ledger), 1);
    });

    test('(b) 再起動をまたいでも最初の未計上区間が失われない（ウォーターマークの行がprevとして復元される）', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, sessionId: 's', elapsedMicros: 0);
      // r1 のみ処理した状態で「アプリ終了」を模す（r2 はまだ届いていない）。
      await coordinator.accrue(r1, {TerrainType.forest: 1});
      expect(coordinator.watermarkRowId, 1);

      // 「再起動」: 新しいコーディネータで ledger から復元する。
      final restarted = TerrainYieldAccrualCoordinator(ledger: ledger);
      await restarted.initialize();

      // NativePositionProvider は sinceRowId=0 から全件再生するため、r1 が
      // 再び届く。ウォーターマークの行そのものなので計上はされないが、
      // 内部の「直前の点（prev）」として復元される。
      await restarted.accrue(r1, {TerrainType.forest: 1});
      expect(ledger.calls, hasLength(1)); // r1の分の書き込みは増えない

      // r1 の次に初めて届く新しい行（r2）は、prev=r1 との差分で正しく計上される
      // （r1→r2 の区間が失われていない）。
      final r2 = _record(rowId: 2, sessionId: 's', elapsedMicros: terrainYieldMicrosecondsPerUnit);
      await restarted.accrue(r2, {TerrainType.forest: 1});

      expect(ledger.calls, hasLength(2));
      expect(ledger.calls.last.grantedAmounts, {Resource.wood: 1});
    });

    test('(c) ウォーターマークより新しい行が無ければ何も起きない', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, sessionId: 's', elapsedMicros: 0);
      await coordinator.accrue(r1, {TerrainType.forest: 1});
      expect(ledger.calls, hasLength(1));

      // 同じ行（ウォーターマークそのもの）を再度渡しても ledger は一切呼ばれない。
      await coordinator.accrue(r1, {TerrainType.forest: 1});
      expect(ledger.calls, hasLength(1));
    });

    test(
      '(d) 計上の途中で失敗したら資材もウォーターマークも進まない。'
      '次に成功したときは失敗した区間を含めて正しく計上される（区間が失われない）',
      () async {
        final ledger = _FakeLedger();
        final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
        await coordinator.initialize();

        final r1 = _record(rowId: 1, sessionId: 's', elapsedMicros: 0);
        await coordinator.accrue(r1, {TerrainType.forest: 1});
        expect(coordinator.watermarkRowId, 1);

        // r2 の計上を意図的に失敗させる。
        ledger.throwOnNextApply = true;
        final r2 = _record(
          rowId: 2,
          sessionId: 's',
          elapsedMicros: terrainYieldMicrosecondsPerUnit ~/ 2, // 30分
        );
        await expectLater(
          coordinator.accrue(r2, {TerrainType.forest: 1}),
          throwsA(isA<StateError>()),
        );

        // 失敗したので watermark・remainder は r1 のまま変わっていない。
        expect(coordinator.watermarkRowId, 1);
        expect(coordinator.remainderMicros, isEmpty);
        expect(ledger.calls, hasLength(1)); // r1の分のみ

        // 次の行（r3）が届いたとき、内部の prev はまだ r1 のままのはずなので、
        // r1→r3 の区間（1時間分＝30分〔失敗したr2の分〕+30分）が丸ごと計上される。
        final r3 = _record(
          rowId: 3,
          sessionId: 's',
          elapsedMicros: terrainYieldMicrosecondsPerUnit, // r1から見て1時間後
        );
        await coordinator.accrue(r3, {TerrainType.forest: 1});

        expect(ledger.calls, hasLength(2));
        expect(ledger.calls.last.grantedAmounts, {Resource.wood: 1});
        expect(ledger.calls.last.watermarkRowId, 3);
      },
    );

    test('山（複数資材）でも独立して積算される', () async {
      final ledger = _FakeLedger();
      final coordinator = TerrainYieldAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(
        _record(rowId: 1, sessionId: 's', elapsedMicros: 0),
        {TerrainType.mountain: 1},
      );
      await coordinator.accrue(
        _record(rowId: 2, sessionId: 's', elapsedMicros: terrainYieldMicrosecondsPerUnit),
        {TerrainType.mountain: 1},
      );

      expect(ledger.calls.last.grantedAmounts, {Resource.stone: 1, Resource.iron: 1});
    });
  });
}

/// テストの可読性のための小さなヘルパー（`_FakeLedger` の最終状態から
/// 「木」の合計付与量を再構成する）。
class InventoryTotalsForTest {
  static Future<int> wood(_FakeLedger ledger) async {
    var total = 0;
    for (final call in ledger.calls) {
      total += call.grantedAmounts[Resource.wood] ?? 0;
    }
    return total;
  }
}
