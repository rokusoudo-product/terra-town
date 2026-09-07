import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('Distance', () {
    test('meters をそのまま保持する（単位はメートル固定・2026-08-11 代表回答）', () {
      const d = Distance.meters(123.4);

      expect(d.meters, 123.4);
    });

    test('等価性は meters の値で判定する', () {
      expect(const Distance.meters(50), const Distance.meters(50));
      expect(const Distance.meters(50), isNot(const Distance.meters(51)));
    });

    test('加算すると meters が合算される', () {
      final total = const Distance.meters(30) + const Distance.meters(20);

      expect(total, const Distance.meters(50));
    });

    test('比較演算子で大小を判定できる', () {
      expect(const Distance.meters(10) < const Distance.meters(20), isTrue);
      expect(const Distance.meters(20) > const Distance.meters(10), isTrue);
      expect(const Distance.meters(10) <= const Distance.meters(10), isTrue);
    });

    test('負の距離は許容しない', () {
      expect(() => Distance.meters(-1), throwsA(isA<AssertionError>()));
    });
  });
}
