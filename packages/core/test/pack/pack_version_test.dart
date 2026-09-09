import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('PackVersion', () {
    test('同一の文字列からは等価な PackVersion が得られる', () {
      const a = PackVersion('2026-09-09-01');
      const b = PackVersion('2026-09-09-01');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('異なる文字列からは異なる PackVersion が得られる', () {
      const a = PackVersion('2026-09-09-01');
      const b = PackVersion('2026-09-09-02');

      expect(a, isNot(b));
    });

    test('空文字は許容しない', () {
      expect(() => PackVersion(''), throwsA(isA<AssertionError>()));
    });
  });
}
