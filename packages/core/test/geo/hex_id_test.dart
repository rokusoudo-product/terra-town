import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('HexId', () {
    test('同一入力からは同一の HexId が得られる（決定論性）', () {
      const a = HexId(42);
      const b = HexId(42);

      expect(a, b);
      expect(a.toInt(), b.toInt());
    });

    test('異なる入力からは異なる HexId が得られる', () {
      const a = HexId(42);
      const b = HexId(43);

      expect(a, isNot(b));
    });

    test('等価な HexId は hashCode も一致する（Map/Set キーとして安全に使える）', () {
      const a = HexId(7);
      const b = HexId(7);
      final set = <HexId>{}
        ..add(a)
        ..add(b);

      expect(a.hashCode, b.hashCode);
      expect(set.length, 1);
    });

    test('異なる HexId は hashCode が異なりうる（衝突ゼロは保証しないが単純委譲を確認）', () {
      const a = HexId(1);
      const b = HexId(2);

      expect(a.hashCode, isNot(b.hashCode));
    });

    test('toInt() は地図 Feature の整数 id に渡せる非負整数を返す', () {
      const id = HexId(100);

      expect(id.toInt(), 100);
      expect(id.toInt(), isA<int>());
    });

    test('負の値は許容しない（Feature id として不正なため）', () {
      expect(() => HexId(-1), throwsA(isA<AssertionError>()));
    });
  });
}
