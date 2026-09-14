import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town/map/landmark_layer_factory.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [pngBytes] をデコードし、縦方向の列 [x] 上で不透明
/// （alpha > [alphaThreshold]）なピクセルが連続する**最初の**区間の
/// (開始y, 終了y)（両端 inclusive）を返す。
///
/// `landmark_layer_factory.dart` の `_renderPin` は、円を描いたあと
/// （伏せピン以外は）2px の間隔を空けてラベルを描く。列の中央（x = 画像幅/2）
/// は円の直径の範囲に収まり、かつラベルもおおむね中央寄せで描かれるため
/// 交差しうるが、円とラベルの間には必ず透明な間隔があるため、
/// 「最初に見つかる連続した不透明区間」は常に円だけを指す
/// （Issue #173 のテスト方針: 円の中心が画像の中心に一致することを、
/// 実装の内部定数に依存せずピクセルから直接検証する）。
Future<(int, int)> _findFirstOpaqueRunOnColumn(
  Uint8List pngBytes,
  int x, {
  int alphaThreshold = 10,
}) async {
  final codec = await ui.instantiateImageCodec(pngBytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final bytes = byteData!.buffer.asUint8List();
  final width = image.width;
  final height = image.height;

  int? start;
  int? end;
  for (var y = 0; y < height; y++) {
    final alpha = bytes[(y * width + x) * 4 + 3];
    if (alpha > alphaThreshold) {
      start ??= y;
      end = y;
    } else if (start != null) {
      break;
    }
  }
  if (start == null || end == null) {
    throw StateError('列 x=$x に不透明なピクセルが見つかりません（$pngBytes）');
  }
  return (start, end);
}

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

  // Issue #173: 名所ピンの円がヘクスより上に描かれ、ピンを押すと隣のヘクスが
  // 選ばれてしまっていた（原因: 円の下にラベルを焼き込んだ画像の「画像全体の
  // 中心」が座標に来ていたため）。`landmark_layer.dart` は `icon-anchor` を
  // 指定せず既定値 `center`（画像全体の中心を座標に合わせる）に委ねる方式の
  // ままにしたため、修正は本関数（`_renderPin`）側で「円の中心が画像の中心に
  // 一致する」レイアウトに直すことで行った。伏せ・開示済み・収集済みの
  // 3状態すべてで、実際にピクセルレベルで円の中心が画像の中心（縦方向）に
  // 一致することを確認する。
  testWidgets(
    '伏せ・開示済み・収集済みの3状態すべてで、円の中心が画像の中心（縦方向）に一致する（Issue #173）',
    (tester) async {
      final images = await tester.runAsync(
        () => buildLandmarkPinImages([withHex]),
      );

      // 伏せピン・開示済み・収集済みの3枚（withoutHexは除外されるため
      // withHexのみ渡す）。
      expect(images!.images.length, 3);

      for (final entry in images.images.entries) {
        final bytes = entry.value;
        final codec = await tester.runAsync(
          () => ui.instantiateImageCodec(bytes),
        );
        final frame = await tester.runAsync(() => codec!.getNextFrame());
        final image = frame!.image;
        final centerX = image.width ~/ 2;

        final run = await tester.runAsync(
          () => _findFirstOpaqueRunOnColumn(bytes, centerX),
        );
        final circleCenterY = (run!.$1 + run.$2) / 2;
        final imageCenterY = image.height / 2;

        expect(
          circleCenterY,
          closeTo(imageCenterY, 2),
          reason:
              '${entry.key}: 円の中心 (y=$circleCenterY) が画像の中心 '
              '(y=$imageCenterY) からずれています（幅=${image.width}, '
              '高さ=${image.height}）',
        );
      }
    },
  );
}
