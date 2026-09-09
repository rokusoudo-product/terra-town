import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('PointOfInterestId', () {
    test('同一の文字列からは等価な PointOfInterestId が得られる', () {
      const a = PointOfInterestId('node/12345');
      const b = PointOfInterestId('node/12345');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('空文字は許容しない', () {
      expect(() => PointOfInterestId(''), throwsA(isA<AssertionError>()));
    });
  });

  group('PointOfInterest', () {
    test('全フィールドが等しければ等価になる', () {
      const a = PointOfInterest(
        id: PointOfInterestId('node/1'),
        name: '六創堂神社',
        kind: 'shrine',
        latitude: 35.0,
        longitude: 135.0,
      );
      const b = PointOfInterest(
        id: PointOfInterestId('node/1'),
        name: '六創堂神社',
        kind: 'shrine',
        latitude: 35.0,
        longitude: 135.0,
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('緯度が範囲外だと assert で弾く', () {
      expect(
        () => PointOfInterest(
          id: const PointOfInterestId('node/1'),
          name: 'x',
          kind: 'x',
          latitude: 90.1,
          longitude: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('経度が範囲外だと assert で弾く', () {
      expect(
        () => PointOfInterest(
          id: const PointOfInterestId('node/1'),
          name: 'x',
          kind: 'x',
          latitude: 0,
          longitude: -180.1,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
