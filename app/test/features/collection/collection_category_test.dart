// LandmarkCategory 対応表（Issue #161・T075）のテスト。
//
// 「対応表はコード上で一箇所にまとめ、テストする」（Issue #161 提案内容）を満たす。

import 'package:flutter_test/flutter_test.dart';

import 'package:terra_town/features/collection/collection_category.dart';

void main() {
  group('categoryOf', () {
    test('現行パック（51件）の内訳に登場する8種の kind をすべて分類できる', () {
      expect(categoryOf('amenity=place_of_worship'), LandmarkCategory.shrineTemple);
      expect(categoryOf('historic=memorial'), LandmarkCategory.historicMemorial);
      expect(categoryOf('tourism=museum'), LandmarkCategory.museum);
      expect(categoryOf('tourism=viewpoint'), LandmarkCategory.viewpoint);
      expect(categoryOf('tourism=artwork'), LandmarkCategory.artwork);
      expect(categoryOf('leisure=park'), LandmarkCategory.park);
      expect(categoryOf('tourism=information'), LandmarkCategory.informationCenter);
      expect(categoryOf('tourism=attraction'), LandmarkCategory.attraction);
    });

    test('未知の kind は「その他」に分類され、落ちない（forward-compat）', () {
      expect(categoryOf('shop=bakery'), LandmarkCategory.other);
      expect(categoryOf(''), LandmarkCategory.other);
    });

    test('kind が null（v2以前の collection 行）でも「その他」に分類され、落ちない', () {
      expect(categoryOf(null), LandmarkCategory.other);
    });

    test('カテゴリラベルはすべて空でない日本語文字列', () {
      for (final category in LandmarkCategory.values) {
        expect(category.label, isNotEmpty);
      }
    });

    test('表示順（categoryDisplayOrder）の最後は other', () {
      expect(categoryDisplayOrder.last, LandmarkCategory.other);
    });
  });
}
