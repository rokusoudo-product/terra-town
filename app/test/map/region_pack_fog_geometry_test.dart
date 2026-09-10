import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// 受け入れ基準「13,106ヘクスの実データで fog of war の GeoJSON が組み立てられる
/// （`FogOfWarController` に載せられる）」（Issue #105）を、実機なしで検証する。
///
/// 【なぜ widget テストではなく直接ファイルを読むか】`assets/pack/region_pack.sqlite`
/// は `flutter test` の実行時カレントディレクトリ（`app/` パッケージルート）から
/// 相対パスでそのまま読める実ファイルである（Flutter アセットバンドルの
/// 仮想ファイルシステムを経由する必要はない。実機/アプリでは
/// `resolveBundledMbtilesPath` 経由のコピーが必要だが、それは
/// 「アセットバンドル→書き込み可能な実ファイル」変換の都合であり、
/// テスト実行環境では最初から実ファイルとして存在するため不要）。
///
/// 【`tools/pack-builder/bundle_region_pack.sh` 未実行の環境でも失敗しない】
/// 生成物はコミットしない方針（Issue #85）のため、CI・他の開発者の環境では
/// このファイルが存在しないことがある。存在しない場合はテストをスキップする
/// （`markTestSkipped`）。「パック未取得の状態でもビルドとテストが通る」という
/// 受け入れ基準に対応する。
void main() {
  const packPath = 'assets/pack/region_pack.sqlite';

  test(
    '実際の同梱地域パックから、13,106件の実ヘクスでfog of war用GeoJSONが組み立てられる',
    () {
      if (!File(packPath).existsSync()) {
        markTestSkipped(
          '$packPath が存在しません（tools/pack-builder/bundle_region_pack.sh '
          '未実行の環境。Issue #85の方針により生成物はコミットしない）。',
        );
        return;
      }

      final connection = RegionPackConnection.open(packPath);
      addTearDown(connection.close);

      final fc = buildFogHexFeatureCollectionFromRegionPack(connection);

      // FogOfWarController.install が実行時に呼ぶのと同じ検証をそのまま通す
      // （fog_of_war_layer.dart 参照。promoteId を使っていないことの確認を含む）。
      expect(() => validateFogHexFeatureCollectionIds(fc), returnsNormally);

      final features = (fc['features'] as List).cast<Map<String, dynamic>>();

      // tools/pack-builder/README.md・research.md §8.0 実測の本番ヘクス数。
      // 対象エリア（狭山湖周辺）が変わらない限りこの値は決定論的に一致する
      // （verify_determinism.py が同じ入力から同じ hex_terrain 行数になることを
      // 別途保証している）。
      expect(features, hasLength(13106));

      final ids = features.map((f) => f['id']).toList();
      expect(ids, everyElement(isA<int>()));
      expect(ids.toSet(), hasLength(ids.length), reason: 'feature_id に重複がないこと');

      final maxId = ids.cast<int>().reduce((a, b) => a > b ? a : b);
      // docs/terrain.md §4.4・research.md §8.4: 52bitマスクによりJSON安全整数の
      // 範囲(2^53-1)に収まる。
      expect(maxId, lessThan(9007199254740991));

      // hex_id は properties に文字列で持たせる（2^53を超えうるため）。
      for (final feature in features.take(5)) {
        expect(feature['properties']['hex_id_str'], isA<String>());
      }
    },
  );
}
