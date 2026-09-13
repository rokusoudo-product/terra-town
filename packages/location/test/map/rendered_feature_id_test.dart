import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  group('parseRenderedFeatureId', () {
    test(
      'Android の queryRenderedFeatures が返す文字列の id を整数にする（2026-09-13 実機で発見した不具合）',
      () {
        // MapLibre の GeoJSON モデル（org.maplibre.geojson.Feature）は id を文字列で
        // 保持するため、toJson() → jsonDecode 後の id は文字列になる。
        expect(parseRenderedFeatureId('833107801608191'), 833107801608191);
      },
    );

    test('整数の id はそのまま返す', () {
      expect(parseRenderedFeatureId(833107801608191), 833107801608191);
    });

    test('小数部の無い double は整数にする', () {
      expect(parseRenderedFeatureId(42.0), 42);
    });

    test('解釈できない値は null を返す', () {
      expect(parseRenderedFeatureId(null), isNull);
      expect(parseRenderedFeatureId(1.5), isNull);
      expect(parseRenderedFeatureId('abc'), isNull);
      expect(parseRenderedFeatureId(''), isNull);
      expect(parseRenderedFeatureId(<String, dynamic>{}), isNull);
    });

    test('前後の空白は無視する', () {
      expect(parseRenderedFeatureId(' 123 '), 123);
    });
  });
}
