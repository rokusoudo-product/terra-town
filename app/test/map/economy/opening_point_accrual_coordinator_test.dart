import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/map/economy/opening_point_accrual_coordinator.dart';

/// [OpeningPointLedgerStore] のオンメモリフェイク（`applyAccrual` の呼び出し回数・
/// 引数を記録できる。`terrain_yield_accrual_coordinator_test.dart` の
/// `_FakeLedger` と同じ手法）。
class _FakeLedger implements OpeningPointLedgerStore {
  int watermarkRowId = 0;
  int remainderMillimeters = 0;
  int points = 0;

  final List<_ApplyCall> calls = [];
  bool throwOnNextApply = false;

  @override
  Future<OpeningPointLedgerSnapshot> readSnapshot() async {
    return OpeningPointLedgerSnapshot(
      watermarkRowId: watermarkRowId,
      remainderMillimeters: remainderMillimeters,
      points: points,
    );
  }

  @override
  Future<void> applyAccrual({
    required int grantedPoints,
    required int remainderMillimeters,
    required int watermarkRowId,
  }) async {
    if (throwOnNextApply) {
      throwOnNextApply = false;
      throw StateError('意図的な失敗（テスト用）');
    }
    calls.add(_ApplyCall(
      grantedPoints: grantedPoints,
      remainderMillimeters: remainderMillimeters,
      watermarkRowId: watermarkRowId,
    ));
    points += grantedPoints;
    this.remainderMillimeters = remainderMillimeters;
    this.watermarkRowId = watermarkRowId;
  }
}

class _ApplyCall {
  _ApplyCall({
    required this.grantedPoints,
    required this.remainderMillimeters,
    required this.watermarkRowId,
  });

  final int grantedPoints;
  final int remainderMillimeters;
  final int watermarkRowId;
}

const double _earthRadiusMeters = 6371000.0;

double _latDeltaForMeters(double meters) => meters / (_earthRadiusMeters * math.pi / 180.0);

final DateTime _baseTime = DateTime.utc(2026, 9, 12, 9, 0, 0);

/// [rowId] の位置記録を作る。[northMeters] は基準地点（北緯35度・東経135度）から
/// 真北へ移動した距離〔m〕（経度固定・南北直進で合成することで、区間の移動距離が
/// 既知の値になるようにする。`reward_policy_test.dart` と同じ手法）。
LocationPointRecord _record({
  required int rowId,
  required double northMeters,
  required DateTime timestamp,
  String sessionId = 's',
  bool spoofSuspected = false,
  int? cumulativeStepCount,
}) {
  return LocationPointRecord(
    rowId: rowId,
    position: GeoPosition(
      latitude: 35.0 + _latDeltaForMeters(northMeters),
      longitude: 135.0,
      timestamp: timestamp,
      trackingSessionId: sessionId,
      spoofSuspected: spoofSuspected,
      cumulativeStepCount: cumulativeStepCount,
    ),
  );
}

void main() {
  group('OpeningPointAccrualCoordinator', () {
    test('初回（区間を作れる点が1つしかない）では計上は起きないがウォーターマークは進む', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(_record(rowId: 1, northMeters: 0, timestamp: _baseTime));

      expect(ledger.calls, hasLength(1));
      expect(ledger.calls.single.grantedPoints, 0);
      expect(ledger.calls.single.watermarkRowId, 1);
      expect(coordinator.watermarkRowId, 1);
      expect(coordinator.points, 0);
    });

    test('同一セッション内・徒歩相当の速度で3.2km分歩くと2P付与され、残りは端数として持ち越される', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      // 3.2km を 2160秒（時速約5.3km相当）で移動。歩数センサーは未設定
      // （cumulativeStepCount=null）→ 4条件の1により歩数不一致判定はスキップされ、
      // 倍率1のまま（RewardPolicy クラスdoc「罰しない側に倒す」参照）。
      // 【1.5kmのちょうど整数倍を避ける理由】Haversine計算はごく僅かな浮動小数点誤差を
      // 持ちうるため、換算の閾値ちょうど（1,500,000mmの整数倍）を期待値にすると
      // 境界をわずかに下回ってflakyになりうる。200,000mm（200m）の余裕を持たせる。
      await coordinator.accrue(_record(rowId: 1, northMeters: 0, timestamp: _baseTime));
      await coordinator.accrue(
        _record(
          rowId: 2,
          northMeters: 3200,
          timestamp: _baseTime.add(const Duration(seconds: 2160)),
        ),
      );

      // floor(3200m * 1.0 * 1000) = 3,200,000mm。1P=1,500,000mmなので2P・端数200,000mm。
      expect(coordinator.points, 2);
      expect(coordinator.remainderMillimeters, 200000);
      expect(coordinator.lastAppliedMultiplier, 1.0);
      expect(coordinator.lastSegmentDistanceMeters, closeTo(3200, 1));
    });

    test('セッションをまたぐと距離を積算しない（新しいセッションの1点目は計上されない）', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(
        _record(rowId: 1, northMeters: 0, timestamp: _baseTime, sessionId: 'session-a'),
      );
      // session-b は別セッション。3km分ワープしたように見えても積算してはならない。
      await coordinator.accrue(
        _record(
          rowId: 2,
          northMeters: 3000,
          timestamp: _baseTime.add(const Duration(seconds: 2160)),
          sessionId: 'session-b',
        ),
      );

      expect(coordinator.points, 0);
      expect(coordinator.remainderMillimeters, 0);
    });

    test('付与倍率0（モック位置疑い）: 距離を歩いてもポイントは増えない', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(_record(rowId: 1, northMeters: 0, timestamp: _baseTime));
      await coordinator.accrue(
        _record(
          rowId: 2,
          northMeters: 3000,
          timestamp: _baseTime.add(const Duration(seconds: 2160)),
          spoofSuspected: true,
        ),
      );

      expect(coordinator.points, 0);
      expect(coordinator.remainderMillimeters, 0);
      expect(coordinator.lastAppliedMultiplier, 0.0);
      expect(coordinator.lastReason, RewardSegmentReason.mockSuspected);
    });

    test('付与倍率0（速度超過）: 短時間で3km移動（自動車相当）してもポイントは増えない', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      await coordinator.accrue(_record(rowId: 1, northMeters: 0, timestamp: _baseTime));
      // 3kmを60秒（時速180km相当）で移動。
      await coordinator.accrue(
        _record(
          rowId: 2,
          northMeters: 3000,
          timestamp: _baseTime.add(const Duration(seconds: 60)),
        ),
      );

      expect(coordinator.points, 0);
      expect(coordinator.remainderMillimeters, 0);
      expect(coordinator.lastAppliedMultiplier, 0.0);
      expect(coordinator.lastReason, RewardSegmentReason.overSpeed);
    });

    test('付与倍率0.5（歩数不一致）: 距離は半分として積算される', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      // 3.2kmを1200秒（時速約9.6km・速度超過にはならない）で移動。歩数はほぼ増えない
      // （自転車等・歩行していない想定）ため歩数不一致となり倍率0.5になる。
      await coordinator.accrue(
        _record(rowId: 1, northMeters: 0, timestamp: _baseTime, cumulativeStepCount: 0),
      );
      await coordinator.accrue(
        _record(
          rowId: 2,
          northMeters: 3200,
          timestamp: _baseTime.add(const Duration(seconds: 1200)),
          cumulativeStepCount: 1,
        ),
      );

      expect(coordinator.lastAppliedMultiplier, 0.5);
      expect(coordinator.lastReason, RewardSegmentReason.stepMismatch);
      // floor(3200m * 0.5 * 1000) = 1,600,000mm → 1P・端数100,000mm。
      expect(coordinator.points, 1);
      expect(coordinator.remainderMillimeters, 100000);
    });

    test('上限（cap）到達後は歩いてもポイントが増えない（切り捨て）', () async {
      final ledger = _FakeLedger()..points = 50;
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger, cap: 50);
      await coordinator.initialize();

      await coordinator.accrue(_record(rowId: 1, northMeters: 0, timestamp: _baseTime));
      await coordinator.accrue(
        _record(
          rowId: 2,
          northMeters: 15000, // 10P相当
          timestamp: _baseTime.add(const Duration(seconds: 15000)), // 時速3.6km・徒歩相当
        ),
      );

      expect(coordinator.points, 50); // 上限を超えない
    });

    test('起動のたびに全件が流れ直しても計上済みの区間はスキップされる（二重計上しない）', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, northMeters: 0, timestamp: _baseTime);
      final r2 = _record(
        rowId: 2,
        northMeters: 3200,
        timestamp: _baseTime.add(const Duration(seconds: 2160)),
      );
      await coordinator.accrue(r1);
      await coordinator.accrue(r2);
      expect(ledger.calls, hasLength(2));
      expect(coordinator.points, 2);

      // 「アプリ再起動」を模して、同じ ledger を使う新しいコーディネータを作り、
      // 全件（r1・r2）を最初から流し直す。
      final restarted = OpeningPointAccrualCoordinator(ledger: ledger);
      await restarted.initialize();
      await restarted.accrue(r1);
      await restarted.accrue(r2);

      // ウォーターマーク以下の行なので ledger への書き込みは一切発生しない。
      expect(ledger.calls, hasLength(2));
      expect(restarted.points, 2);
    });

    test('再起動をまたいでも最初の未計上区間が失われない（ウォーターマークの行が窓の文脈として復元される）', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, northMeters: 0, timestamp: _baseTime);
      // r1 のみ処理した状態で「アプリ終了」を模す（r2 はまだ届いていない）。
      await coordinator.accrue(r1);
      expect(coordinator.watermarkRowId, 1);

      // 「再起動」: 新しいコーディネータで ledger から復元する。
      final restarted = OpeningPointAccrualCoordinator(ledger: ledger);
      await restarted.initialize();

      // NativePositionProvider は sinceRowId=0 から全件再生するため、r1 が
      // 再び届く。ウォーターマークの行そのものなので計上はされないが、
      // 窓の文脈（直近の点）として復元される。
      await restarted.accrue(r1);
      expect(ledger.calls, hasLength(1)); // r1の分の書き込みは増えない

      // r1 の次に初めて届く新しい行（r2）は、r1 との区間で正しく計上される
      // （r1→r2 の区間が失われていない）。
      final r2 = _record(
        rowId: 2,
        northMeters: 3200,
        timestamp: _baseTime.add(const Duration(seconds: 2160)),
      );
      await restarted.accrue(r2);

      expect(ledger.calls, hasLength(2));
      expect(restarted.points, 2);
    });

    test('ウォーターマークより新しい行が無ければ何も起きない', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, northMeters: 0, timestamp: _baseTime);
      await coordinator.accrue(r1);
      expect(ledger.calls, hasLength(1));

      // 同じ行（ウォーターマークそのもの）を再度渡しても ledger は一切呼ばれない。
      await coordinator.accrue(r1);
      expect(ledger.calls, hasLength(1));
    });

    test('計上の途中で失敗したらポイントもウォーターマークも進まない。次に成功したときは失敗した区間を含めて正しく計上される', () async {
      final ledger = _FakeLedger();
      final coordinator = OpeningPointAccrualCoordinator(ledger: ledger);
      await coordinator.initialize();

      final r1 = _record(rowId: 1, northMeters: 0, timestamp: _baseTime);
      await coordinator.accrue(r1);
      expect(coordinator.watermarkRowId, 1);

      // r2 の計上を意図的に失敗させる。
      ledger.throwOnNextApply = true;
      final r2 = _record(
        rowId: 2,
        northMeters: 1500,
        timestamp: _baseTime.add(const Duration(seconds: 1080)),
      );
      await expectLater(coordinator.accrue(r2), throwsA(isA<StateError>()));

      // 失敗したので watermark・points は r1 のまま変わっていない。
      expect(coordinator.watermarkRowId, 1);
      expect(coordinator.points, 0);
      expect(ledger.calls, hasLength(1)); // r1の分のみ

      // 次の行（r3）が届いたとき、r1→r3 の区間（3.2km分）が丸ごと計上される
      // （失敗したr2の分を含め、区間が失われていない）。
      final r3 = _record(
        rowId: 3,
        northMeters: 3200,
        timestamp: _baseTime.add(const Duration(seconds: 2160)),
      );
      await coordinator.accrue(r3);

      expect(ledger.calls, hasLength(2));
      expect(coordinator.points, 2);
      expect(ledger.calls.last.watermarkRowId, 3);
    });
  });
}
