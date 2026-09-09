import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('DistrictId', () {
    test('同一の文字列からは等価な DistrictId が得られる', () {
      const a = DistrictId('13101');
      const b = DistrictId('13101');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('異なる文字列からは異なる DistrictId が得られる', () {
      expect(const DistrictId('13101'), isNot(const DistrictId('13102')));
    });

    test('空文字は許容しない', () {
      expect(() => DistrictId(''), throwsA(isA<AssertionError>()));
    });
  });

  group('District', () {
    test('id・name が等しければ等価になる', () {
      const a = District(id: DistrictId('13101'), name: '千代田区');
      const b = District(id: DistrictId('13101'), name: '千代田区');

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('name が異なれば等価にならない', () {
      const a = District(id: DistrictId('13101'), name: '千代田区');
      const b = District(id: DistrictId('13101'), name: '中央区');

      expect(a, isNot(b));
    });
  });
}
