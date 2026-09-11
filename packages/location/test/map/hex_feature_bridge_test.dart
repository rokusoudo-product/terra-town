import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_location/terra_town_location.dart';

/// [hexIdToFeatureId]（docs/terrain.md §4.4・Issue #137）のテスト。
void main() {
  group('hexIdToFeatureId', () {
    test('実測サンプル（狭山湖パック・research.md §8.4）で feature_id と一致する', () {
      // app/assets/pack/region_pack.sqlite の hex_terrain から抜粋した実測値
      // （2026-09-11 時点の同梱パック。狭山湖周辺・pack_version=sayamako-v1-9a66e066b0d4）。
      expect(hexIdToFeatureId(626833455896940543), 833107692441599);
      expect(hexIdToFeatureId(626833455896948735), 833107692449791);
      expect(hexIdToFeatureId(626833455897014271), 833107692515327);
    });

    test('52bitを超えない値はそのまま返す', () {
      expect(hexIdToFeatureId(0), 0);
      expect(hexIdToFeatureId(1), 1);
      const maxSafe52Bit = (1 << 52) - 1;
      expect(hexIdToFeatureId(maxSafe52Bit), maxSafe52Bit);
    });

    test('結果は常に2^53-1（JSON safe integer の上限）未満', () {
      // H3 index は2^63未満（docs/terrain.md §4.4）。上位ビットが全て立っていても
      // マスク後は52bit以内に収まることを確認する。
      const largeHexIndex = 0x7FFFFFFFFFFFFFFF; // 63bit全て1
      final featureId = hexIdToFeatureId(largeHexIndex);
      expect(featureId, lessThan(9007199254740991));
      expect(featureId, (1 << 52) - 1);
    });
  });

  group('hexIdToFeatureId（同梱の実パック・存在する場合のみ、全件検証）', () {
    const packPath = '../../app/assets/pack/region_pack.sqlite';

    test('hex_terrain の全行で hex_id & mask == feature_id が成り立つ', () {
      if (!File(packPath).existsSync()) {
        markTestSkipped(
          '$packPath が存在しません（tools/pack-builder/bundle_region_pack.sh '
          '未実行の環境。Issue #85の方針により生成物はコミットしない）。',
        );
        return;
      }

      final db = sqlite3.sqlite3.open(packPath, mode: sqlite3.OpenMode.readOnly);
      addTearDown(db.close);

      final rows = db.select('SELECT hex_id, feature_id FROM hex_terrain');
      expect(rows, isNotEmpty);
      for (final row in rows) {
        final hexId = row['hex_id'] as int;
        final expectedFeatureId = row['feature_id'] as int;
        expect(
          hexIdToFeatureId(hexId),
          expectedFeatureId,
          reason: 'hex_id=$hexId で hex_bridge.py（生成側）と '
              'hexIdToFeatureId（Dart側）の計算結果が一致しない',
        );
      }
    });
  });
}
