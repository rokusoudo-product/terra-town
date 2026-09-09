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
