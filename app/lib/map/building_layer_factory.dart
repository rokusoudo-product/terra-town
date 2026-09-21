import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Color, IconData;
import 'package:flutter/painting.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';
import '../features/build/build_screen.dart' show buildingSpecs;

/// composition root（`app`）で建物レイヤー（Issue #193・T090）用の
/// [BuildingIconImages] を組み立てる。
///
/// 【仮アイコン（Issue #193 本文「2. 仮アイコン」・代表決定「建物の正式な絵は
/// まだ無い」）】画像ファイルは追加せず、建設タブのカード
/// （`app/lib/features/build/build_screen.dart` の [buildingSpecs]）と**同じ
/// Material アイコンのグリフ**を、3系統ごとの既存トークン色の円の上に
/// `dart:ui` で焼き込む（`landmark_layer_factory.dart` の `_renderPin` と同じ
/// 手法。名称ラベル・収集済みバッジが無いぶんさらに単純）。建設タブと同じ
/// [buildingSpecs] を参照することで、「種別→アイコングリフ」の対応が
/// 二重管理にならないようにしている（`building_layer.dart` の [buildingIconId]
/// が担う「種別→画像名」の対応と合わせて、正式なスプライトへの差し替えは
/// 本関数 1箇所を書き換えるだけで済む）。
///
/// 【3系統の色分け（実装判断・PR本文に記載）】DESIGN.md に建物カテゴリごとの
/// 色トークン対応は定義されていない。8種を見分けられる（Issue #193 受け入れ
/// 基準）ことを優先し、アイコングリフ（種別ごとに異なる）に加えて系統単位で
/// 背景色を変え、次のとおり既存トークンを割り当てる:
///   - 住宅系（住宅・マンション）: `primary`（DESIGN.md「自分の街の象徴色」）
///   - 生産系（畑・農場・工場・採石場）: `secondary`
///   - 娯楽系（リゾート・ミュージアム）: `accent`
/// 名所ピンの背景色（開示済み=`primary`・収集済み=`accent`。
/// `landmark_layer_factory.dart` 参照）と同じトークンを使う組み合わせがあるが、
/// アイコングリフが異なるため「色だけで情報を伝えない」（DESIGN.md
/// アクセシビリティ規則）は満たしている。新しい色値は追加しない。
Future<BuildingIconImages> buildBuildingIconImages() async {
  final images = <String, Uint8List>{};
  for (final spec in buildingSpecs) {
    images[buildingIconId(spec.buildingType)] = await _renderBuildingIcon(
      icon: spec.icon,
      backgroundColor: _backgroundColorFor(spec.buildingType),
    );
  }
  return BuildingIconImages(images);
}

/// `docs/buildings.md` §2 の3系統（住宅系・生産系・娯楽系）ごとの背景色
/// （クラスdoc「3系統の色分け」参照）。
Color _backgroundColorFor(BuildingType type) {
  switch (type) {
    case BuildingType.house:
    case BuildingType.apartment:
      return ColorTokens.primaryLight;
    case BuildingType.cropField:
    case BuildingType.livestockFarm:
    case BuildingType.factoryBuilding:
    case BuildingType.quarry:
      return ColorTokens.secondaryLight;
    case BuildingType.resort:
    case BuildingType.museum:
      return ColorTokens.accentLight;
  }
}

/// 建物アイコン1枚分のPNGを `dart:ui` で組み立てる（`BuildContext`・
/// ウィジェットツリー不要。`landmark_layer_factory.dart` の `_renderPin` 参照）。
///
/// 名所ピンと異なり名称ラベル・収集済みバッジが無いため、上下対称レイアウトに
/// 悩む必要が無く、正方形キャンバスの中心に円を描くだけでよい（`icon-anchor` を
/// 指定しない既定値 `center` で座標に円の中心が来る。`landmark_layer.dart`の
/// `landmarkSymbolLayerProperties` と同じ考え方を [buildingSymbolLayerProperties]
/// が踏襲している）。
Future<Uint8List> _renderBuildingIcon({
  required IconData icon,
  required Color backgroundColor,
}) async {
  const double diameter = 64;
  // 縁取り（幅3）がキャンバス外にはみ出さないための余白。
  const double canvasSize = diameter + 8;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasSize, canvasSize),
  );
  const center = Offset(canvasSize / 2, canvasSize / 2);

  canvas.drawCircle(center, diameter / 2, Paint()..color = backgroundColor);
  canvas.drawCircle(
    center,
    diameter / 2,
    Paint()
      ..color = ColorTokens.surfaceLight
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3,
  );

  final iconPainter = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: diameter * 0.5,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: ColorTokens.surfaceLight,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  iconPainter.paint(
    canvas,
    center - Offset(iconPainter.width / 2, iconPainter.height / 2),
  );

  final picture = recorder.endRecording();
  final image = await picture.toImage(canvasSize.round(), canvasSize.round());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
