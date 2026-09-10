import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/map/debug/fog_debug_hex_grid.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【本ファイルの位置づけ】ここでの「デバッグ用の合成グリッド」は本物の
  // ヘクスではない（fog_debug_hex_grid.dart 冒頭コメント参照）。ここで検証する
  // のは、代表が実機で fog of war を確認する手順（Issue #100 の受け入れ基準）が
  // 依存する最低限の性質、すなわち
  //   (a) 要求した件数ちょうどのFeatureが生成されること
  //   (b) FogOfWarController.install の受け入れ条件（Feature直下に整数id・
  //       重複なし）を満たすこと
  // の2点のみ。ジオメトリの正確な形・実際の緯度経度との対応は検証対象外。
  test('要求した件数ちょうどの合成ヘクスFeatureを生成する', () {
    final fc = buildSyntheticFogHexFeatureCollection(
      centerLat: 35.79,
      centerLon: 139.38,
      count: 61,
    );

    final features = fc['features'] as List;
    expect(features.length, 61);
  });

  test('各Featureが直下に整数idを重複なく持つ（FogOfWarController.installの受け入れ条件）', () {
    final fc = buildSyntheticFogHexFeatureCollection(
      centerLat: 35.79,
      centerLon: 139.38,
      count: 200,
      firstFeatureId: 1000,
    );

    // FogOfWarController.install が実際に呼ぶ検証と同じ関数を通す。
    // ここで例外が出ないこと自体が「Feature直下に整数idを持つ」ことの検証になる。
    expect(() => validateFogHexFeatureCollectionIds(fc), returnsNormally);

    final features = fc['features'] as List;
    final ids = features.map((f) => (f as Map)['id'] as int).toList();
    expect(ids.toSet().length, ids.length, reason: 'idに重複が無いこと');
    expect(ids.reduce((a, b) => a < b ? a : b), 1000, reason: 'firstFeatureIdからの連番');
  });

  test('本番相当の13,106件でも整数idの受け入れ条件を満たす', () {
    // 受け入れ基準「本番パックのヘクス数（13,106）でのソース構築コストを
    // 計測する手順」で使う件数と同じものを、まずデータ生成レベルで検証する。
    final fc = buildSyntheticFogHexFeatureCollection(
      centerLat: 35.79,
      centerLon: 139.38,
      count: 13106,
      firstFeatureId: 1000000,
    );

    final features = fc['features'] as List;
    expect(features.length, 13106);
    expect(() => validateFogHexFeatureCollectionIds(fc), returnsNormally);
  });
}
