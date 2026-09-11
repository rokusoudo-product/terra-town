import 'dart:math' as math;

import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// [RewardPolicy] のテスト（Issue #126・T099・T101）。
///
/// `speed_check_test.dart` と同じ手法（Haversine公式の恒等式で経度固定・南北
/// 直進の合成ルートを作り、狙った距離になるよう緯度を逆算する）でルートを合成する。
/// 期待値はすべてリテラル値で書く（`RewardPolicy.defaultXxx` 等の定数は参照しない。
/// `speed_check_test.dart` 冒頭のコメント参照・Issue #50 の教訓）。

const double _earthRadiusMeters = 6371000.0;

double _latDeltaForMeters(double meters) => meters / (_earthRadiusMeters * math.pi / 180.0);

final DateTime _baseTime = DateTime.utc(2026, 9, 11, 9, 0, 0);

/// 一定速度 [speedKmh] で経度固定・南北直進する合成ルートを [count] 点作る。
/// [stepsPerPoint] が非null なら、各点間で歩数がその値だけ増える累積歩数を付与する
/// （最初の点は [initialStepCount]）。
List<GeoPosition> _walkingRoute({
  required int count,
  required double speedKmh,
  Duration interval = const Duration(seconds: 15),
  double startLat = 35.0,
  double longitude = 135.0,
  int? stepsPerPoint,
  int initialStepCount = 0,
}) {
  final intervalSeconds = interval.inMicroseconds / Duration.microsecondsPerSecond;
  final metersPerStep = speedKmh / 3.6 * intervalSeconds;
  final latDeltaPerStep = _latDeltaForMeters(metersPerStep);
  return List.generate(
    count,
    (i) => GeoPosition(
      latitude: startLat + latDeltaPerStep * i,
      longitude: longitude,
      timestamp: _baseTime.add(interval * i),
      trackingSessionId: 'session-a',
      cumulativeStepCount: stepsPerPoint == null ? null : initialStepCount + stepsPerPoint * i,
    ),
  );
}

void main() {
  group('RewardPolicy.allowsDisclosure', () {
    test('spoofSuspectedがfalseなら開拓を許可する', () {
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: _baseTime,
      );
      expect(RewardPolicy.allowsDisclosure(position), isTrue);
    });

    test('spoofSuspectedがtrueなら開拓を許可しない', () {
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: _baseTime,
        spoofSuspected: true,
      );
      expect(RewardPolicy.allowsDisclosure(position), isFalse);
    });
  });

  group('RewardPolicy.classify - 歩数突合', () {
    test('歩幅相応の歩数が伴う徒歩は倍率1のまま（不一致なし）', () {
      // 時速5km・15秒間隔（1点あたり約20.83m）。歩幅0.69m/歩相当の歩数を付与
      // （2歩/秒 × 15秒 = 30歩/点）。maxStrideMeters(1.5m)を大きく下回るため
      // 不一致にならないはず。
      final route = _walkingRoute(count: 10, speedKmh: 5.0, stepsPerPoint: 30);
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, hasLength(9));
      for (final segment in segments) {
        expect(segment.multiplier, 1.0);
        expect(segment.reason, RewardSegmentReason.none);
      }
    });

    test('歩数センサーが無い（cumulativeStepCountが常にnull）場合は罰しない', () {
      final route = _walkingRoute(count: 10, speedKmh: 8.0); // stepsPerPoint未指定→null
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, hasLength(9));
      for (final segment in segments) {
        expect(segment.multiplier, 1.0);
        expect(segment.reason, RewardSegmentReason.none);
      }
    });

    test('移動距離に対して歩数がほぼ伴わない場合、ウィンドウが100m以上になった区間から倍率が下がる（0にはしない）', () {
      // 時速8km・15秒間隔（1点あたり約33.33m）。歩数は一切増えない
      // （自転車等・歩行していない想定）。
      final route = _walkingRoute(count: 6, speedKmh: 8.0, stepsPerPoint: 0);
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, hasLength(5));
      // 累積距離: 33.33, 66.67, 100.0, 133.33, 166.67
      // minWindowDistanceMeters(100)未満の最初の2区間は判定しない。
      expect(segments[0].multiplier, 1.0);
      expect(segments[0].reason, RewardSegmentReason.none);
      expect(segments[1].multiplier, 1.0);
      expect(segments[1].reason, RewardSegmentReason.none);
      // 3区間目以降はウィンドウ距離が100mを超え、歩数0では説明できないため
      // 不一致（0にはしない穏やかな倍率）。
      for (final segment in segments.sublist(2)) {
        expect(segment.multiplier, greaterThan(0.0));
        expect(segment.multiplier, lessThan(1.0));
        expect(segment.reason, RewardSegmentReason.stepMismatch);
      }
    });

    test('ウィンドウ内の移動距離が下限未満なら歩数が0でも罰しない（静止・短距離）', () {
      final route = [
        GeoPosition(
          latitude: 35.0,
          longitude: 135.0,
          timestamp: _baseTime,
          trackingSessionId: 'session-a',
          cumulativeStepCount: 0,
        ),
        GeoPosition(
          // 約50m（下限100m未満）。30秒かけて移動＝時速6km（速度超過閾値10km未満）。
          latitude: 35.0 + _latDeltaForMeters(50),
          longitude: 135.0,
          timestamp: _baseTime.add(const Duration(seconds: 30)),
          trackingSessionId: 'session-a',
          cumulativeStepCount: 0,
        ),
      ];
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, hasLength(1));
      expect(segments.single.multiplier, 1.0);
      expect(segments.single.reason, RewardSegmentReason.none);
    });

    test('セッション内で歩数が減少（端末再起動等）した区間を含むウィンドウは不明扱いで罰しない', () {
      // 距離は歩数不一致になりうる設定だが、ウィンドウ内に歩数減少区間が
      // 1つでもあれば、そのウィンドウを参照する区間はすべて倍率1のまま。
      final route = [
        GeoPosition(
          latitude: 35.0,
          longitude: 135.0,
          timestamp: _baseTime,
          trackingSessionId: 'session-a',
          cumulativeStepCount: 100,
        ),
        GeoPosition(
          // 60mを30秒かけて移動＝時速7.2km（速度超過閾値10km未満）。
          latitude: 35.0 + _latDeltaForMeters(60),
          longitude: 135.0,
          timestamp: _baseTime.add(const Duration(seconds: 30)),
          trackingSessionId: 'session-a',
          cumulativeStepCount: 40, // 減少（例: 端末再起動）
        ),
        GeoPosition(
          latitude: 35.0 + _latDeltaForMeters(120),
          longitude: 135.0,
          timestamp: _baseTime.add(const Duration(seconds: 60)),
          trackingSessionId: 'session-a',
          cumulativeStepCount: 40, // 増えない（歩数不一致になりうる設定）
        ),
      ];
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, hasLength(2));
      for (final segment in segments) {
        expect(segment.multiplier, 1.0);
        expect(segment.reason, RewardSegmentReason.none);
      }
    });
  });

  group('RewardPolicy.classify - 速度超過との関係', () {
    test('速度超過区間は歩数が一致していても倍率0・reasonはoverSpeed（二重に扱わない）', () {
      // 時速15km（閾値10km超）で、歩幅相応の歩数（歩数的には一致）を付与しても
      // 速度超過が優先され倍率0になる。
      final route = _walkingRoute(count: 10, speedKmh: 15.0, stepsPerPoint: 90);
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      for (final segment in segments) {
        expect(segment.multiplier, 0.0);
        expect(segment.reason, RewardSegmentReason.overSpeed);
      }
    });
  });

  group('RewardPolicy.classify - モック位置との関係', () {
    test('モック位置に触れる区間は倍率0・reasonはmockSuspectedで、前後の正規区間には影響しない', () {
      final legitBefore = _walkingRoute(count: 5, speedKmh: 5.0, stepsPerPoint: 30);
      final mockJumpTime = legitBefore.last.timestamp.add(const Duration(seconds: 15));
      final mockPosition = GeoPosition(
        // 約5km離れた位置へテレポート。
        latitude: legitBefore.last.latitude + _latDeltaForMeters(5000),
        longitude: 135.0,
        timestamp: mockJumpTime,
        trackingSessionId: 'session-a',
        spoofSuspected: true,
        cumulativeStepCount: legitBefore.last.cumulativeStepCount,
      );
      final legitAfterStart = mockPosition.latitude; // モック地点から歩行再開
      final legitAfter = List.generate(5, (i) {
        final t = mockJumpTime.add(Duration(seconds: 15 * (i + 1)));
        return GeoPosition(
          latitude: legitAfterStart + _latDeltaForMeters(5.0 / 3.6 * 15 * (i + 1)),
          longitude: 135.0,
          timestamp: t,
          trackingSessionId: 'session-a',
          cumulativeStepCount: (mockPosition.cumulativeStepCount ?? 0) + 30 * (i + 1),
        );
      });

      final route = [...legitBefore, mockPosition, ...legitAfter];
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, hasLength(route.length - 1));

      // legitBefore同士の区間（0〜3）は正規の徒歩のまま。
      for (final segment in segments.sublist(0, 4)) {
        expect(segment.multiplier, 1.0);
        expect(segment.reason, RewardSegmentReason.none);
      }
      // legitBefore最後→mock、mock→legitAfter最初 の2区間はモック起因で倍率0。
      expect(segments[4].reason, RewardSegmentReason.mockSuspected);
      expect(segments[4].multiplier, 0.0);
      expect(segments[5].reason, RewardSegmentReason.mockSuspected);
      expect(segments[5].multiplier, 0.0);
      // mock後の正規区間（legitAfter同士）は、モックのテレポートによる速度
      // スパイクの影響を一切受けず、通常の徒歩として満額のまま
      // （SpeedFilterの平滑化窓にモック地点を混ぜていないことの検証）。
      for (final segment in segments.sublist(6)) {
        expect(segment.multiplier, 1.0);
        expect(segment.reason, RewardSegmentReason.none);
      }
    });
  });

  group('RewardPolicy.classify - セッション境界', () {
    test('trackingSessionIdが異なる隣接点同士は区間を作らない', () {
      final route = [
        GeoPosition(
          latitude: 35.0,
          longitude: 135.0,
          timestamp: _baseTime,
          trackingSessionId: 'session-a',
        ),
        GeoPosition(
          latitude: 35.001,
          longitude: 135.0,
          timestamp: _baseTime.add(const Duration(seconds: 15)),
          trackingSessionId: 'session-b',
        ),
      ];
      final policy = RewardPolicy();

      final segments = policy.classify(route);

      expect(segments, isEmpty);
    });
  });
}
