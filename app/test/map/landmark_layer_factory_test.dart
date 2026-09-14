import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/map/landmark_layer_factory.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  const withHex = PointOfInterest(
    id: PointOfInterestId('node/1'),
    name: '名所A',
    kind: 'tourism=museum',
    latitude: 35.0,
    longitude: 139.0,
    hexId: HexId(1),
  );
  const withoutHex = PointOfInterest(
    id: PointOfInterestId('node/2'),
    name: '名所B（旧パック由来でhexIdなし）',
    kind: 'tourism=attraction',
    latitude: 35.1,
    longitude: 139.1,
  );

  // 【役割分担・Issue #57 の考え方の延長】配色・アイコン選定・ラベル焼き込みの
  // 「中身」が正しいことを検証するのは本テスト（app側）の責務。
  // packages/location 側は `LandmarkPinImages` が受け取ったMapをそのまま
  // 保持するだけであることのみを検証する（landmark_layer_test.dart 参照）。
  testWidgets(
    'buildLandmarkPinImages は伏せピン1枚と、hexIdを持つPOIごとに開示/収集済み画像を生成する',
    (tester) async {
      // 【`runAsync` が必須な理由】`buildLandmarkPinImages` は `dart:ui` の
      // `Picture.toImage`/`Image.toByteData` で実際にラスタライズを行う。
      // これらはエンジンのラスタスレッドからの本物の非同期コールバックであり、
      // `testWidgets` の本体を包む `FakeAsync` ゾーンの中では完了が届かず
      // ハングする（初回実装時に「Test timed out after 10 minutes」で発覚）。
      // `tester.runAsync` で実ゾーンに逃がすことで解決する。
      final images = await tester.runAsync(
        () => buildLandmarkPinImages([withHex, withoutHex]),
      );

      // 伏せピンは種別・名称を問わず全POI共通の1枚（docs/landmark_objects.md
      // §3.2-1「名称・種別は出さない」）。
      expect(images!.images.containsKey(landmarkLockedIconId), isTrue);

      // hexIdを持つPOIのみ生成する（buildLandmarkFeatureCollectionが同じ条件で
      // 除外するPOIに対して無駄な画像を作らないことの確認）。
      expect(images.images.containsKey(landmarkRevealedIconId(withHex.id)), isTrue);
      expect(images.images.containsKey(landmarkCollectedIconId(withHex.id)), isTrue);
      expect(
        images.images.containsKey(landmarkRevealedIconId(withoutHex.id)),
        isFalse,
      );
      expect(
        images.images.containsKey(landmarkCollectedIconId(withoutHex.id)),
        isFalse,
      );

      // 伏せピン1枚 + (開示済み・収集済み) × hexIdありPOI1件 = 3枚。
      expect(images.images.length, 3);

      // PNGのマジックナンバー（89 50 4E 47）で有効なPNGバイト列であることを確認する
      // （見た目の正しさそのものはピクセル差分に頼らず、実機確認〔PR本文記載〕に委ねる）。
      for (final bytes in images.images.values) {
        expect(bytes.length, greaterThan(8));
        expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      }
    },
  );

  testWidgets('POIが1件も無い場合でも伏せピン画像だけは生成する', (tester) async {
    final images = await tester.runAsync(() => buildLandmarkPinImages(const []));

    expect(images!.images.keys, [landmarkLockedIconId]);
  });
}
