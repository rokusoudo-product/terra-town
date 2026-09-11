import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('GeoPosition', () {
    test('等価な値からは等価な GeoPosition が得られる', () {
      final at = DateTime.utc(2026, 9, 9, 12);
      final a = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: at,
        accuracy: const Distance.meters(5),
      );
      final b = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: at,
        accuracy: const Distance.meters(5),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('accuracy を省略できる（未取得時は null）', () {
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: DateTime.utc(2026, 9, 9),
      );

      expect(position.accuracy, isNull);
    });

    // Issue #124: spoofSuspected・trackingSessionId を省略しても
    // 既存の生成箇所（本ファイルの他のテストも含む）が壊れないことを保証する。
    test('spoofSuspected・trackingSessionId を省略すると既定値（false・null）になる', () {
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: DateTime.utc(2026, 9, 9),
      );

      expect(position.spoofSuspected, isFalse);
      expect(position.trackingSessionId, isNull);
    });

    test('spoofSuspected・trackingSessionId を明示的に指定できる', () {
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: DateTime.utc(2026, 9, 9),
        spoofSuspected: true,
        trackingSessionId: 'session-a',
      );

      expect(position.spoofSuspected, isTrue);
      expect(position.trackingSessionId, 'session-a');
    });

    test('spoofSuspected・trackingSessionId のいずれかが異なれば等価にならない', () {
      final at = DateTime.utc(2026, 9, 9);
      final base = GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: at);

      expect(
        base,
        isNot(GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: at, spoofSuspected: true)),
      );
      expect(
        base,
        isNot(
          GeoPosition(
            latitude: 35.0,
            longitude: 135.0,
            timestamp: at,
            trackingSessionId: 'session-a',
          ),
        ),
      );
    });

    // Issue #108: hexId を省略しても既存の生成箇所（本ファイルの他のテストも含む）が
    // 壊れないことを保証する（spoofSuspected・trackingSessionId と同じ方針）。
    test('hexId を省略すると既定値（null）になる', () {
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: DateTime.utc(2026, 9, 9),
      );

      expect(position.hexId, isNull);
    });

    test('hexId を明示的に指定できる（2^53超の値でも精度を落とさない）', () {
      const measuredMaxHexId = 626833456793083903;
      final position = GeoPosition(
        latitude: 35.0,
        longitude: 135.0,
        timestamp: DateTime.utc(2026, 9, 9),
        hexId: const HexId(measuredMaxHexId),
      );

      expect(position.hexId, const HexId(measuredMaxHexId));
    });

    test('hexId が異なれば等価にならない', () {
      final at = DateTime.utc(2026, 9, 9);
      final base = GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: at);

      expect(
        base,
        isNot(
          GeoPosition(
            latitude: 35.0,
            longitude: 135.0,
            timestamp: at,
            hexId: const HexId(1),
          ),
        ),
      );
    });

    test('緯度が範囲外（-90.0〜90.0 の外）だと assert で弾く', () {
      expect(
        () => GeoPosition(
          latitude: 91.0,
          longitude: 0,
          timestamp: DateTime.utc(2026, 9, 9),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('経度が範囲外（-180.0〜180.0 の外）だと assert で弾く', () {
      expect(
        () => GeoPosition(
          latitude: 0,
          longitude: 181.0,
          timestamp: DateTime.utc(2026, 9, 9),
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('緯度経度・時刻・精度いずれかが異なれば等価にならない', () {
      final at = DateTime.utc(2026, 9, 9);
      final base = GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: at);

      expect(base, isNot(GeoPosition(latitude: 36.0, longitude: 135.0, timestamp: at)));
      expect(base, isNot(GeoPosition(latitude: 35.0, longitude: 136.0, timestamp: at)));
      expect(
        base,
        isNot(GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: DateTime.utc(2026, 9, 10))),
      );
      expect(
        base,
        isNot(
          GeoPosition(
            latitude: 35.0,
            longitude: 135.0,
            timestamp: at,
            accuracy: const Distance.meters(1),
          ),
        ),
      );
    });
  });
}
