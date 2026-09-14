import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:terra_town_core/terra_town_core.dart'
    show PointOfInterest, PointOfInterestId;

/// 名所ピンレイヤーの描画に使うラスタ画像一式（Issue #160・T071）。
///
/// 【Issue #57 の注入方式をさらに一歩進める】`FogOfWarLayer`・
/// `CurrentLocationMarkerStyle` は色（`#RRGGBB` 文字列）だけを `app` から
/// 注入させていたが、名所ピンは Material アイコン・種別ごとの絵柄・
/// 名称ラベル（テキスト）まで含めて見た目が決まる。これらをすべて
/// `location` 側の責務にすると `packages/location` が `terra_town` の
/// 配色・フォント・アイコン選定ロジックを知ることになり、GPS_ARCHITECTURE
/// （GPS まわりの実装を他の GPS 利用アプリでも使い回せる資産にする）の
/// 狙いに反する。そのため本Issueでは一歩進めて、**完成済みのラスタ画像
/// （PNGバイト列）そのもの**を `app`（`app/lib/map/landmark_layer_factory.dart`）
/// に組み立てさせ、`location` は受け取ったバイト列をそのまま
/// `MapLibreMapController.addImage` に渡すだけにする。
///
/// 【代表決定「画像アセットの生成は行わない」との関係】ここで扱うのは
/// `assets/` に恒久的に追加・コミットする画像ファイルではなく、実行時に
/// Material アイコン＋DESIGN.md のトークンから組み立てて
/// `MapLibreMapController.addImage` に渡すだけの一時データである。
/// そのため `IMAGE_WORKFLOW`（新規の画像アセット生成の承認ゲート）の対象には
/// あたらない（Issue #160 本文の代表決定「ピンの見た目は Material アイコン＋
/// 『？』で作る。画像アセットの生成は行わない」はこの実行時合成方式を指す）。
///
/// [images] のキーは [landmarkLockedIconId]・[landmarkRevealedIconId]・
/// [landmarkCollectedIconId] が返す文字列と一致していること（[LandmarkLayerController.install]
/// がそのままキーを画像名として `addImage` に渡す）。
@immutable
class LandmarkPinImages {
  const LandmarkPinImages(this.images);

  /// 画像名 → PNGバイト列。
  final Map<String, Uint8List> images;
}

/// [LandmarkLayerController.install] に渡す一式（GeoJSON FeatureCollection と
/// ラスタ画像）をまとめたもの。
///
/// 【なぜ [LandmarkPinImages] の生成だけ非同期にできる形にしたか】
/// ラスタ画像の生成（`dart:ui` の `Picture.toImage`/`Image.toByteData`）は
/// Skia のラスタライズを伴うため必ず非同期になる
/// （`app/lib/map/landmark_layer_factory.dart` 参照）。一方
/// [buildLandmarkFeatureCollection] は同期の純粋関数のままでよい
/// （`fog_hex_source.dart`・`buildFogHexFeatureCollectionFromRegionPack` と同じ
/// 位置づけ）。[MapView.landmarkAssets] は本クラス全体を `Future` として
/// 受け取ることで、`MapView` 側のレイヤー追加処理（`_addRegionPackLayers`。
/// 既存の1回限りの `onStyleLoadedCallback` の流れ）を変えずに、画像生成の
/// 完了を待ってから名所レイヤーを追加できるようにしている。
@immutable
class LandmarkLayerAssets {
  const LandmarkLayerAssets({
    required this.images,
    required this.featureCollection,
  });

  final LandmarkPinImages images;

  /// [buildLandmarkFeatureCollection] が組み立てた GeoJSON FeatureCollection。
  final Map<String, dynamic> featureCollection;
}

/// 未開示の名所すべてに共通の伏せピン画像のID。
///
/// `docs/landmark_objects.md` §3.2-1「名称・種別は出さない」ため、種別・
/// 名称に関わらず全POI共通の1枚（Material アイコン＋「？」）で足りる。
const landmarkLockedIconId = 'terra_town_landmark_locked';

/// [id] の「開示済み・未収集」アイコン画像のID（種別アイコン＋名称ラベル）。
String landmarkRevealedIconId(PointOfInterestId id) =>
    'terra_town_landmark_revealed_${_sanitizeForImageId(id.value)}';

/// [id] の「収集済み」アイコン画像のID（accent色でのハイライト＋名称ラベル）。
String landmarkCollectedIconId(PointOfInterestId id) =>
    'terra_town_landmark_collected_${_sanitizeForImageId(id.value)}';

/// MapLibre の画像名として安全な文字だけに正規化する。
///
/// POI ID は OSM 由来で `node/12345` のように `/` を含みうる
/// （`tools/pack-builder/extract_poi.py` 参照）ため、英数字・`_`・`-` 以外は
/// `_` に置換する。
String _sanitizeForImageId(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

/// [pointsOfInterest] から名所ピンレイヤー用の GeoJSON FeatureCollection を
/// 組み立てる（T071）。
///
/// ## Feature の `id` 要件（[FogOfWarController] と同じ理由）
/// 各 Feature は `properties` の中ではなく**直下**に整数 `id` を持つ
/// （`promoteId` は Android で機能しないため。`fog_of_war_layer.dart`
/// クラスdoc参照）。ここでの `id` は名所レイヤー内でのみ意味を持つ連番であり、
/// `hex_terrain.feature_id`（52bitマスク方式）とは無関係の別採番である
/// （ソースが別なので衝突の心配はない）。
///
/// ## `hexId` が無いPOIは除外する
/// `PointOfInterest.hexId` が `null`（`hex_poi` 非同梱の旧パック等。クラスdoc
/// 参照）のPOIは、どのヘクスの開示に連動させればよいか判定できないため
/// 本コレクションから除外する。
Map<String, dynamic> buildLandmarkFeatureCollection(
  Iterable<PointOfInterest> pointsOfInterest,
) {
  final features = <Map<String, dynamic>>[];
  var nextFeatureId = 0;
  for (final poi in pointsOfInterest) {
    if (poi.hexId == null) continue;
    features.add({
      'type': 'Feature',
      // ⚠️ properties の外（直下）に整数 id を持たせる（fog と同じ理由）。
      'id': nextFeatureId++,
      'geometry': {
        'type': 'Point',
        'coordinates': [poi.longitude, poi.latitude],
      },
      'properties': {
        'poi_id_str': poi.id.value,
        // feature-state（'revealed'/'collected'）に応じてどの登録済み画像を
        // 使うかを、スタイル式（['get', ...]）でこのプロパティから引く
        // （`LandmarkLayerController.install` 参照）。
        'revealed_icon': landmarkRevealedIconId(poi.id),
        'collected_icon': landmarkCollectedIconId(poi.id),
      },
    });
  }
  return {'type': 'FeatureCollection', 'features': features};
}

/// [featureCollection] の各 Feature が、`properties` の中ではなく直下に整数
/// `id` を持つことを検証する（[validateFogHexFeatureCollectionIds] と同じ
/// 役割。`fog_of_war_layer.dart` 参照）。違反があれば [ArgumentError] を投げる。
void validateLandmarkFeatureCollectionIds(
  Map<String, dynamic> featureCollection,
) {
  final features = featureCollection['features'];
  if (features is! List) {
    throw ArgumentError.value(
      featureCollection,
      'featureCollection',
      'FeatureCollection の features が見つかりません',
    );
  }
  for (final feature in features) {
    if (feature is! Map || feature['id'] is! int) {
      throw ArgumentError.value(
        feature,
        'feature',
        '名所レイヤーの各 Feature は直下（properties の外）に整数 id を'
        '持つ必要があります（promoteId は Android で機能しないため）。',
      );
    }
  }
}

/// 名所ピンレイヤー（T071）の地図登録・開示/収集状態のトグルを担う
/// （[FogOfWarController] と対になるクラス）。
///
/// ## 表現方式（代表決定・Issue #160）
/// 「Material アイコン＋『？』」の伏せピンと、開示後の「種別アイコン＋
/// 名称ラベル」・収集済みの accent ハイライトを、[LandmarkPinImages] として
/// 事前に組み立てたラスタ画像（`app` 側で生成。クラスdoc参照）を
/// シンボルレイヤーの `icon-image` として使い分けることで実現する。
/// 名称ラベルはラスタ画像に焼き込み済みのため、MapLibre 自体の
/// `text-field`（グリフ描画）機能は使わない
/// （下記「オフライン地図スタイルとテキストグリフについて」参照）。
///
/// ## オフライン地図スタイルとテキストグリフについて（PR本文にも記載）
/// `map_view.dart` の `_backgroundOnlyStyle` は背景色のみのインラインスタイルで
/// あり `glyphs`（フォントPBFタイルのURLテンプレート）を宣言していない。
/// MapLibre のシンボルレイヤーが `text-field` でテキストを描画するには
/// スタイルに `glyphs` が設定され、対応するフォントPBFが取得できる必要がある
/// （オンラインでもオフラインでも同様）。本アプリはオフライン専用
/// （`research.md` §6.4「demotiles.maplibre.org への依存はNG」）であり、
/// フォントPBFを別途同梱・生成する仕組みは無い。したがって
/// `SymbolLayerProperties.textField` を使う実装は本オフライン環境では
/// 文字が描画されない（またはクラッシュしうる）リスクがあり、採用しない。
/// 代わりに名称ラベルを `app` 側でラスタ画像に**焼き込む**方式
/// （[LandmarkPinImages] クラスdoc参照）を採用し、MapLibre 自体の
/// テキストレンダリングパイプラインに一切依存しない。
///
/// ## `feature-state` による O(1) トグル（[FogOfWarController] と同じ設計）
/// 各名所 Feature の `revealed`/`collected` を `setFeatureState` でトグルし、
/// `icon-image` のスタイル式（`case` 式）でその状態に応じた登録済み画像名を
/// 選ぶ。ヘクス開示のたびに GeoJSON ソース全体を作り直す必要はない
/// （名所は全国で51件程度・`docs/landmark_objects.md` 想定であり、そもそも
/// フルリプレースでも許容範囲だが、既存の fog と同じ設計に揃えることを
/// 優先した）。
///
/// ## タップを吸わない（Issue #151と同じ落とし穴・最重要）
/// `addSymbolLayer` は既定で `enableInteraction: true` になり、地物タップが
/// このレイヤーに吸われる。[install] は必ず `enableInteraction: false` で
/// 追加し、霧ヘクスのタップ（ポイント開放の選択）を妨げないようにする
/// （ピン自体のタップ機能は本Issueの対象外）。
///
/// ## 正は `disclosed_hex`・`collection` テーブルである
/// [FogOfWarController] と同じく、ここで管理する feature-state は描画のための
/// 派生状態にすぎない。正は `disclosed_hex`・`collection`（Issue #159）であり、
/// アプリ再起動後・`setStyle` 後の復元は呼び出し側（`map_screen.dart`）の
/// 責務とする。
class LandmarkLayerController {
  LandmarkLayerController._(
    this._controller,
    this.sourceId,
    this._featureIdByPoiId,
  );

  final MapLibreMapController _controller;

  /// このコントローラが管理する GeoJSON ソースのID。
  final String sourceId;

  /// `PointOfInterestId.value` → このレイヤー内での Feature の整数 `id`。
  final Map<String, int> _featureIdByPoiId;

  static const defaultSourceId = 'terra_town_landmark';
  static const defaultLayerId = 'terra_town_landmark_layer';

  /// [featureCollection] を1回だけ `addGeoJsonSource` でソースに追加し、
  /// [images] を `addImage` で登録したうえで、`icon-image` を feature-state
  /// （`revealed`/`collected`）に応じて切り替えるシンボルレイヤーを追加する。
  static Future<LandmarkLayerController> install(
    MapLibreMapController controller,
    LandmarkPinImages images,
    Map<String, dynamic> featureCollection, {
    String sourceId = defaultSourceId,
    String layerId = defaultLayerId,
    double iconSize = 1.0,
  }) async {
    validateLandmarkFeatureCollectionIds(featureCollection);

    for (final entry in images.images.entries) {
      await controller.addImage(entry.key, entry.value);
    }

    await controller.addGeoJsonSource(sourceId, featureCollection);

    await controller.addSymbolLayer(
      sourceId,
      layerId,
      SymbolLayerProperties(
        iconImage: [
          'case',
          [
            'boolean',
            ['feature-state', 'collected'],
            false,
          ],
          ['get', 'collected_icon'],
          [
            'boolean',
            ['feature-state', 'revealed'],
            false,
          ],
          ['get', 'revealed_icon'],
          landmarkLockedIconId,
        ],
        iconSize: iconSize,
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      // 【必須】クラスdoc「タップを吸わない」参照。
      enableInteraction: false,
    );

    final featureIdByPoiId = <String, int>{};
    for (final feature in featureCollection['features'] as List) {
      final map = feature as Map;
      final properties = map['properties'] as Map;
      featureIdByPoiId[properties['poi_id_str'] as String] = map['id'] as int;
    }

    return LandmarkLayerController._(controller, sourceId, featureIdByPoiId);
  }

  /// [ids] の名所を「開示済み」表示（種別アイコン＋名称ラベル）に切り替える。
  ///
  /// このレイヤーに存在しない（＝ `hexId` が無い旧パック由来等で
  /// [buildLandmarkFeatureCollection] が除外した）POI IDは無視する。
  Future<void> revealPointsOfInterest(Iterable<PointOfInterestId> ids) async {
    for (final id in ids) {
      final featureId = _featureIdByPoiId[id.value];
      if (featureId == null) continue;
      await _controller.setFeatureState(sourceId, featureId.toString(), {
        'revealed': true,
      });
    }
  }

  /// [ids] の名所を「収集済み」表示（accentハイライト）に切り替える。
  ///
  /// 収集は開示済みヘクスに対してのみ起こる（`docs/landmark_objects.md` §3.2）
  /// ため、`revealed` もあわせて true にしておく（万一の呼び出し順序の
  /// 前後でも収集済みの見た目が伏せピンに戻らないようにする多重の安全策）。
  Future<void> markCollected(Iterable<PointOfInterestId> ids) async {
    for (final id in ids) {
      final featureId = _featureIdByPoiId[id.value];
      if (featureId == null) continue;
      await _controller.setFeatureState(sourceId, featureId.toString(), {
        'revealed': true,
        'collected': true,
      });
    }
  }
}
