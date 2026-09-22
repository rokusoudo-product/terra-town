import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/features/build/build_screen.dart' show buildingSpecs;
import 'package:terra_town/map/building_layer_factory.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [buildBuildingIconImages] のテスト（Issue #193・T090）。
///
/// 【役割分担・Issue #57 の考え方の延長】配色・アイコン選定の「中身」が
/// 正しいことを検証するのは本テスト（app側）の責務。`packages/location` 側
/// （`building_layer_test.dart`）は `buildingIconId`・GeoJSON組み立てのみを
/// 検証する。
void main() {
  testWidgets('建物種別8種すべてに対して仮アイコン画像を生成する（Issue #193 受け入れ基準「8種が見分けられる」）', (
    tester,
  ) async {
    // 【`runAsync` が必須な理由】`landmark_layer_factory_test.dart` と同じ
    // （`dart:ui` の `Picture.toImage`/`Image.toByteData` が実ラスタスレッドの
    // 非同期コールバックのため、`testWidgets` の `FakeAsync` ゾーンでは
    // ハングする）。
    final images = await tester.runAsync(() => buildBuildingIconImages());

    expect(images!.images.length, 8);
    for (final type in BuildingType.values) {
      expect(images.images.containsKey(buildingIconId(type)), isTrue);
    }

    // buildingSpecs（建設タブのカード一覧）と1対1で対応することを確認する
    // （種別→アイコングリフの対応を二重管理しない設計。クラスdoc参照）。
    expect(
      buildingSpecs.map((spec) => spec.buildingType).toSet(),
      BuildingType.values.toSet(),
    );

    // PNGのマジックナンバー（89 50 4E 47）で有効なPNGバイト列であることを
    // 確認する（見た目の正しさそのものは実機確認〔PR本文記載〕に委ねる。
    // `flutter test` のウィジェットテスト環境では MaterialIcons フォントの
    // 実際のグリフが読み込まれないことがあり、種別ごとのグリフが視覚的に
    // 異なることをピクセル差分で検証するのは信頼できないため行わない
    // 〔`landmark_layer_factory_test.dart` も同じ理由でグリフの違いまでは
    // 検証していない〕）。
    for (final bytes in images.images.values) {
      expect(bytes.length, greaterThan(8));
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    }
  });
}
