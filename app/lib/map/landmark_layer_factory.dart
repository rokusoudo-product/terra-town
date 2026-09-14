import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Icons, IconData;
import 'package:flutter/painting.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';

/// composition root（`app`）で名所ピンレイヤー（T071・Issue #160）用の
/// [LandmarkPinImages] を組み立てる。
///
/// 【Issue #57 の注入方式をさらに一歩進める（`landmark_layer.dart` クラスdoc参照）】
/// `packages/location` は配色・Material アイコン・フォントのいずれも知らない。
/// 本関数が DESIGN.md のカラートークン（[ColorTokens]）と Material アイコン
/// （[Icons]）・名称ラベルを `dart:ui` で1枚のPNGに焼き込み、完成済みの
/// バイト列だけを [LandmarkPinImages] として渡す。
///
/// 【名称ラベルをラスタ画像に焼き込む理由（MapLibreの`text-field`を使わない）】
/// `landmark_layer.dart`（[LandmarkLayerController]）クラスdoc
/// 「オフライン地図スタイルとテキストグリフについて」参照。本アプリの地図
/// スタイルはオフライン専用のインラインJSON（`glyphs` 未設定）であり、
/// MapLibre 自身のテキストレンダリング（`text-field`）に必要なフォントPBFを
/// 提供する仕組みが無い。そのため名称ラベルは Flutter の `TextPainter`
/// （Skia側のフォントレンダリング。`glyphs` 設定とは無関係に動作する）で
/// アイコンと同じラスタ画像に直接描き込む。
///
/// 【色以外での区別（DESIGN.md アクセシビリティ・受け入れ基準）】
/// - 伏せピン（未開示）: 種別を問わず同一の `Icons.help`（＝ Material の
///   「？」アイコン）＋名称ラベル無し。
/// - 開示済み・未収集: 種別ごとのアイコン（[_iconForKind]）＋名称ラベル、
///   背景は `primary`（探索の緑）。
/// - 収集済み: 開示済みと同じアイコン・ラベルに加え、背景を `accent`
///   （DESIGN.md「獲得・名所ハイライト」）にしたうえで、右下に
///   `Icons.check_circle` の小さな収集済みバッジを重ねる。色だけでなく
///   バッジの有無でも区別できるようにする。
Future<LandmarkPinImages> buildLandmarkPinImages(
  Iterable<PointOfInterest> pointsOfInterest,
) async {
  final images = <String, Uint8List>{};

  images[landmarkLockedIconId] = await _renderPin(
    icon: Icons.help,
    backgroundColor: ColorTokens.textSecondaryLight,
  );

  // hexId が無いPOIは buildLandmarkFeatureCollection 側で除外されるため、
  // ここで無駄に画像を作らないよう同じ条件で絞り込む。
  final relevant = pointsOfInterest.where((poi) => poi.hexId != null);

  for (final poi in relevant) {
    final icon = _iconForKind(poi.kind);
    images[landmarkRevealedIconId(poi.id)] = await _renderPin(
      icon: icon,
      backgroundColor: ColorTokens.primaryLight,
      label: poi.name,
    );
    images[landmarkCollectedIconId(poi.id)] = await _renderPin(
      icon: icon,
      backgroundColor: ColorTokens.accentLight,
      label: poi.name,
      showCollectedBadge: true,
    );
  }

  return LandmarkPinImages(images);
}

/// POIの `kind`（`tools/pack-builder/extract_poi.py` が書き出す
/// `"{OSMタグキー}={OSMタグ値}"` 形式。`docs/landmark_objects.md` §2.1 参照）から
/// 種別アイコンを選ぶ。
///
/// 網羅的な対応表ではなく、実装判断による代表アイコンの割り当てである
/// （DESIGN.md にアイコン対応表の定義は無い）。未知の種別は汎用の
/// `Icons.place` にフォールバックする。
IconData _iconForKind(String kind) {
  final tagValue = kind.contains('=') ? kind.split('=').last : kind;
  switch (tagValue) {
    case 'museum':
      return Icons.museum;
    case 'gallery':
      return Icons.palette;
    case 'zoo':
      return Icons.pets;
    case 'theme_park':
      return Icons.attractions;
    case 'viewpoint':
      return Icons.visibility;
    case 'artwork':
      return Icons.brush;
    case 'castle':
      return Icons.castle;
    case 'monument':
    case 'memorial':
    case 'wayside_cross':
    case 'milestone':
      return Icons.account_balance;
    case 'ruins':
    case 'archaeological_site':
      return Icons.history_edu;
    case 'park':
    case 'tree':
      return Icons.park;
    case 'place_of_worship':
      return Icons.church;
    case 'tower':
    case 'lighthouse':
      return Icons.signpost;
    case 'picnic_site':
      return Icons.deck;
    case 'information':
      return Icons.info;
    case 'attraction':
    default:
      return Icons.place;
  }
}

/// ピン1枚分のPNGを `dart:ui` で組み立てる（`BuildContext`・ウィジェットツリー
/// 不要。`Icons` の字形は Flutter フレームワークが `uses-material-design: true`
/// 〔`app/pubspec.yaml`〕により同梱する `MaterialIcons` フォントから
/// `TextPainter` で直接描画できる）。
///
/// キャンバスは固定サイズとし、[label] が長い場合は1行に収まるよう省略記号で
/// 切り詰める（POI名称の長さは実データにより様々なため、可変サイズにすると
/// 実装が複雑になる。DESIGN.mdにアイコン/ラベルのサイズトークンは無いため、
/// 本関数のサイズ定数は実装判断の値である。`current_location_marker.dart`の
/// `radius`と同じ位置づけ）。
///
/// 【円の中心を画像の中心に一致させる（Issue #173）】
/// `landmark_layer.dart` の [landmarkSymbolLayerProperties] は `icon-anchor`
/// を指定せず、MapLibre のスタイル仕様の既定値 `center`（画像全体の中心を
/// 座標に合わせる）に委ねている。これは「円の中心が名所の座標に来る」
/// 受け入れ基準を、`icon-anchor`/`icon-offset`（ピクセル単位で
/// `icon-size` 倍率・端末の devicePixelRatio との関係を考慮する必要があり、
/// 事故りやすい）を使わずに満たすための設計判断である。そのために本関数は
/// キャンバスを**円の中心を軸に上下対称**にレイアウトする。
///
/// 具体的には、円の下側にラベル用の余白（[labelTop] から [canvasHeight] まで、
/// 常に一定）を確保したうえで、円の**上側にも同じ高さの余白**
/// （[verticalPadding]）を確保する。これにより
/// `center.dy`（= [verticalPadding] + 半径）と `canvasHeight / 2` が一致し、
/// 画像全体の中心＝円の中心になる。ラベルが無い伏せピン画像も含め、
/// 3状態すべて同じキャンバスサイズ・同じ円の位置で描くため（[canvasWidth]・
/// [canvasHeight]・円中心が呼び出し元の [label] 有無によらず常に同一）、
/// `icon-anchor: center` 1つの既定値で3状態すべてに対応できる。
Future<Uint8List> _renderPin({
  required IconData icon,
  required Color backgroundColor,
  String? label,
  bool showCollectedBadge = false,
}) async {
  const double diameter = 64;
  const double canvasWidth = 176;

  // 円の上下対称のレイアウトにする余白。下側は「ラベルの行の高さ + 円との
  // 間隔」に相当し、上側も同じ値にすることで円の中心が画像の中心
  // （canvasHeight / 2）に一致する（クラスdoc「円の中心を画像の中心に
  // 一致させる」参照）。労力を割いて可変にする理由が無いため、旧実装の
  // ラベル領域の高さ（26px）から逆算した固定値。
  const double verticalPadding = 28;
  const double canvasHeight = verticalPadding * 2 + diameter; // = 120

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, canvasWidth, canvasHeight),
  );
  final center = const Offset(canvasWidth / 2, verticalPadding + diameter / 2);

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

  if (showCollectedBadge) {
    final badgeCenter = center + Offset(diameter * 0.32, diameter * 0.32);
    const badgeRadius = diameter * 0.22;
    canvas.drawCircle(
      badgeCenter,
      badgeRadius,
      Paint()..color = ColorTokens.surfaceLight,
    );
    final badgePainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.check_circle.codePoint),
        style: TextStyle(
          fontSize: badgeRadius * 1.6,
          fontFamily: Icons.check_circle.fontFamily,
          package: Icons.check_circle.fontPackage,
          color: ColorTokens.primaryLight,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    badgePainter.paint(
      canvas,
      badgeCenter - Offset(badgePainter.width / 2, badgePainter.height / 2),
    );
  }

  if (label != null) {
    // 円の下端（verticalPadding + diameter）から2px空けた位置。
    // canvasHeight（= verticalPadding * 2 + diameter）との差である
    // 「verticalPadding - 2」がラベル1行分の描画領域になる（クラスdoc参照）。
    const labelTop = verticalPadding + diameter + 2;
    // 縁取り（ハロー）付きラベル。DESIGN.md「地図オーバーレイのラベルのみ
    // 視認性のため縁取り可」の例外規定を用いる。
    final haloPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          foreground: Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = ColorTokens.surfaceLight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: canvasWidth);
    haloPainter.paint(
      canvas,
      Offset((canvasWidth - haloPainter.width) / 2, labelTop),
    );

    final fillPainter = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: ColorTokens.textPrimaryLight,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: canvasWidth);
    fillPainter.paint(
      canvas,
      Offset((canvasWidth - fillPainter.width) / 2, labelTop),
    );
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    canvasWidth.round(),
    canvasHeight.round(),
  );
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData!.buffer.asUint8List();
}
