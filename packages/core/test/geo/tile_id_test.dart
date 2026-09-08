import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('TileId', () {
    test('同一入力からは同一の TileId が得られる（決定論性）', () {
      const a = TileId(10);
      const b = TileId(10);

      expect(a, b);
    });

    test('異なる入力からは異なる TileId が得られる', () {
      const a = TileId(10);
      const b = TileId(11);

      expect(a, isNot(b));
    });

    test('等価な TileId は hashCode も一致する', () {
      const a = TileId(5);
      const b = TileId(5);

      expect(a.hashCode, b.hashCode);
    });

    test('負の値は許容しない', () {
      expect(() => TileId(-1), throwsA(isA<AssertionError>()));
    });
  });
}
