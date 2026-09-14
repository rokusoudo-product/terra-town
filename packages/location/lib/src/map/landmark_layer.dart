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
        // 開示済み・収集済みそれぞれの状態で使う登録済み画像IDの候補
        // （`LandmarkLayerController.install` がこれらを基に、実際に
        // `icon-image` が参照する可変プロパティ `icon` を組み立てる。
        // Issue #170「なぜ `icon` を別に持たせるか」参照）。
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
/// ## Feature の `properties.icon` を書き換えて `icon-image` に `['get', ...]`
/// で参照させる方式（Issue #170。[FogOfWarController] とは異なる設計）
/// 当初は [FogOfWarController] に合わせて、`icon-image`（**レイアウトプロパティ**）
/// のスタイル式（`case` 式）で `['feature-state', 'collected']`／
/// `['feature-state', 'revealed']` を参照する実装にしていたが、これは
/// **MapLibre のスタイル仕様違反**だった。`feature-state` 式は
/// **データ駆動スタイリングに対応したペイントプロパティでのみ評価**され、
/// レイアウトプロパティ（`icon-image`・`icon-size`・`text-field` 等）や
/// `filter` では一切評価されない（常に既定値になる）。[FogOfWarController] の
/// `fill-opacity` は**ペイントプロパティ**なので問題にならなかったが、
/// `icon-image` はレイアウトプロパティのため、開示・収集後もピンが常に
/// 既定値（伏せピン）のまま切り替わらないという不具合を起こした
/// （PR #168 マージ後に秘書が実機で発見・Issue #170）。widget テストでは
/// 実プラットフォームの描画・スタイル評価が動かないため、実機でしか
/// 見つからない種類の不具合だった。
///
/// **⚠️ 落とし穴: レイアウトプロパティ・`filter` に `feature-state` を使わない。**
/// 本ファイルで新たにトグル可能な見た目を追加する際は、必ずペイントプロパティ
/// （`icon-opacity`・`fill-opacity`・`icon-color` 等）側で `feature-state` を
/// 使うか、本クラスの方式（下記）を踏襲すること。
///
/// 代わりに、各名所 Feature の `properties` に「今表示すべきアイコン画像ID」
/// （`icon`）を持たせ、`icon-image` は [landmarkSymbolLayerProperties] が
/// 組み立てる `['get', 'icon']` 式で参照する。`['get', ...]` は
/// `feature-state` に依存しないため、レイアウトプロパティでも安全に評価される。
/// [revealPointsOfInterest]／[markCollected]／[restoreState] は、[install] が
/// 保持するミュータブルな Feature 一覧（[_features]）の該当 POI の
/// `properties['icon']` を書き換えたうえで、ソース全体を
/// `setGeoJsonSource` で差し替える。名所は全国で51件程度
/// （`docs/landmark_objects.md` 想定）のため、フルリプレースでも負荷は
/// 問題にならない（Issue #170 提案内容）。
///
/// ## 起動時の復元をバッチ化する（[restoreState]）
/// アプリ起動時の復元（`map_screen.dart` の `_onLandmarkLayerReady`）は
/// 開示済みヘクスの数だけループする。[revealPointsOfInterest] を都度呼ぶと
/// その都度ソース全体を差し替えることになり無駄が大きいため、[restoreState]
/// で開示済み・収集済みの全POI IDをまとめて受け取り、`setGeoJsonSource` の
/// 呼び出しを1回に抑える。
///
/// ## タップを吸わない（Issue #151と同じ落とし穴・最重要）
/// `addSymbolLayer` は既定で `enableInteraction: true` になり、地物タップが
/// このレイヤーに吸われる。[install] は必ず `enableInteraction: false` で
/// 追加し、霧ヘクスのタップ（ポイント開放の選択）を妨げないようにする
/// （ピン自体のタップ機能は本Issueの対象外）。
///
/// ## 正は `disclosed_hex`・`collection` テーブルである
/// ここで管理する Feature の `properties.icon` は描画のための派生状態に
/// すぎない。正は `disclosed_hex`・`collection`（Issue #159）であり、
/// アプリ再起動後・`setStyle` 後の復元は呼び出し側（`map_screen.dart`）の
/// 責務とする（[restoreState] 参照）。
class LandmarkLayerController {
  LandmarkLayerController._(
    this._controller,
    this.sourceId,
    this._features,
    this._propertiesByPoiId,
  );

  final MapLibreMapController _controller;

  /// このコントローラが管理する GeoJSON ソースのID。
  final String sourceId;

  /// [install] 時に組み立てたミュータブルな Feature 一覧。各 Feature の
  /// `properties`（[_propertiesByPoiId] と同じ Map インスタンスを指す）を
  /// 書き換えたうえで、本リストごと [_syncSource] で `setGeoJsonSource` に
  /// 渡す（Issue #170 クラスdoc「Feature の `properties.icon` を書き換えて」
  /// 参照）。
  final List<Map<String, dynamic>> _features;

  /// `PointOfInterestId.value` → 対応する Feature の `properties`
  /// （[_features] 内の Map と同一インスタンス。ここを書き換えると
  /// [_features] 側にも反映される）。
  final Map<String, Map<String, dynamic>> _propertiesByPoiId;

  /// 収集済みとして扱った POI ID（[_reveal] が誤って収集済み表示を伏せピン側に
  /// 巻き戻さないための状態。[markCollected]/[restoreState] が追加する）。
  final Set<String> _collectedPoiIds = {};

  static const defaultSourceId = 'terra_town_landmark';
  static const defaultLayerId = 'terra_town_landmark_layer';

  /// [featureCollection] を1回だけ `addGeoJsonSource` でソースに追加し、
  /// [images] を `addImage` で登録したうえで、`icon-image` が
  /// `properties.icon`（[landmarkSymbolLayerProperties] 参照）を参照する
  /// シンボルレイヤーを追加する。追加直後は全 Feature が伏せピン
  /// （[landmarkLockedIconId]）になる（開示済み・収集済みの復元は
  /// [restoreState] を呼ぶ呼び出し側の責務。`map_screen.dart` の
  /// `_onLandmarkLayerReady` 参照）。
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

    // 渡された featureCollection をそのまま保持すると、呼び出し側が保持する
    // Map を本コントローラが暗黙に書き換えてしまう（呼び出し側から見て
    // 予期しない副作用になる）ため、独立したミュータブルなコピーを作る。
    final features = <Map<String, dynamic>>[];
    final propertiesByPoiId = <String, Map<String, dynamic>>{};
    for (final rawFeature in featureCollection['features'] as List) {
      final feature = Map<String, dynamic>.from(rawFeature as Map);
      final properties = Map<String, dynamic>.from(
        feature['properties'] as Map,
      );
      // icon-image が実際に参照する可変プロパティ。install 直後は常に
      // 伏せピン（クラスdoc参照）。
      properties['icon'] = landmarkLockedIconId;
      feature['properties'] = properties;
      features.add(feature);
      propertiesByPoiId[properties['poi_id_str'] as String] = properties;
    }

    await controller.addGeoJsonSource(sourceId, {
      'type': 'FeatureCollection',
      'features': features,
    });

    await controller.addSymbolLayer(
      sourceId,
      layerId,
      landmarkSymbolLayerProperties(iconSize: iconSize),
      // 【必須】クラスdoc「タップを吸わない」参照。
      enableInteraction: false,
    );

    return LandmarkLayerController._(
      controller,
      sourceId,
      features,
      propertiesByPoiId,
    );
  }

  /// [ids] の名所を「開示済み」表示（種別アイコン＋名称ラベル）に切り替える。
  ///
  /// このレイヤーに存在しない（＝ `hexId` が無い旧パック由来等で
  /// [buildLandmarkFeatureCollection] が除外した）POI IDは無視する。
  /// 実際に見た目が変わる Feature が1件も無ければ `setGeoJsonSource` 自体を
  /// 呼ばない（無駄な全件差し替えを避ける）。
  Future<void> revealPointsOfInterest(Iterable<PointOfInterestId> ids) async {
    var changed = false;
    for (final id in ids) {
      if (_reveal(id.value)) changed = true;
    }
    if (changed) await _syncSource();
  }

  /// [ids] の名所を「収集済み」表示（accentハイライト）に切り替える。
  ///
  /// 収集は開示済みヘクスに対してのみ起こる（`docs/landmark_objects.md` §3.2）
  /// ため、以後 [_reveal] が呼ばれても収集済み表示を伏せピン側に巻き戻さない
  /// （[_collectedPoiIds] 参照。万一の呼び出し順序の前後への安全策）。
  Future<void> markCollected(Iterable<PointOfInterestId> ids) async {
    var changed = false;
    for (final id in ids) {
      if (_collect(id.value)) changed = true;
    }
    if (changed) await _syncSource();
  }

  /// アプリ起動時の復元用の一括反映（Issue #170）。
  ///
  /// `map_screen.dart` の `_onLandmarkLayerReady` は開示済みヘクスの数だけ
  /// ループして名所を集める。[revealPointsOfInterest] をループのたびに
  /// 呼ぶと、その都度ソース全体を `setGeoJsonSource` で差し替えることになり
  /// 無駄が大きい。本メソッドは [revealed]・[collected] をまとめて受け取り、
  /// `setGeoJsonSource` の呼び出しを（変更があった場合）1回に抑える。
  Future<void> restoreState({
    required Iterable<PointOfInterestId> revealed,
    required Iterable<PointOfInterestId> collected,
  }) async {
    var changed = false;
    for (final id in revealed) {
      if (_reveal(id.value)) changed = true;
    }
    for (final id in collected) {
      if (_collect(id.value)) changed = true;
    }
    if (changed) await _syncSource();
  }

  /// [poiId] の Feature を「開示済み」表示に切り替える（見た目が変わった場合
  /// [_syncSource] を呼ぶ必要があることを示す `true` を返す）。
  bool _reveal(String poiId) {
    if (_collectedPoiIds.contains(poiId)) return false;
    final properties = _propertiesByPoiId[poiId];
    if (properties == null) return false;
    if (properties['icon'] == properties['revealed_icon']) return false;
    properties['icon'] = properties['revealed_icon'];
    return true;
  }

  /// [poiId] の Feature を「収集済み」表示に切り替える（戻り値は [_reveal] と
  /// 同じ）。
  bool _collect(String poiId) {
    final properties = _propertiesByPoiId[poiId];
    if (properties == null) return false;
    _collectedPoiIds.add(poiId);
    if (properties['icon'] == properties['collected_icon']) return false;
    properties['icon'] = properties['collected_icon'];
    return true;
  }

  /// 現在の [_features]（各 Feature の `properties.icon` を書き換え済み）を
  /// まるごと `setGeoJsonSource` でソースに反映する（Issue #170 クラスdoc
  /// 「名所は全国で51件程度のためフルリプレースでも負荷は問題にならない」）。
  Future<void> _syncSource() {
    return _controller.setGeoJsonSource(sourceId, {
      'type': 'FeatureCollection',
      'features': _features,
    });
  }
}

/// [LandmarkLayerController.install] が追加するシンボルレイヤーの見た目
/// （レイアウトプロパティ）を組み立てる。
///
/// 【`feature-state` を使わない・再発防止（Issue #170）】MapLibre のスタイル
/// 仕様では `feature-state` 式は**データ駆動スタイリングに対応したペイント
/// プロパティでのみ評価**され、`icon-image` のようなレイアウトプロパティや
/// `filter` では一切評価されない。過去の実装はこれを見落とし、`icon-image`
/// の `case` 式で `['feature-state', ...]` を参照したため、開示・収集後も
/// ピンが常に伏せピンのまま切り替わらない不具合を起こした
/// （[LandmarkLayerController] クラスdoc参照）。本関数が組み立てる
/// `['get', 'icon']` は `feature-state` に依存しない `get` 式であり、
/// レイアウトプロパティでも安全に評価される。
///
/// `install` 本体から切り出したのは、`MapLibreMapController`
/// （プラットフォームチャンネル必須・`flutter test` では動作しない）に
/// 依存せず、本関数が組み立てる式そのものに `feature-state` が含まれて
/// いないことを単体テストで検証できるようにするため
/// （`packages/location/test/map/landmark_layer_test.dart` 参照。
/// `fog_of_war_layer_test.dart` 冒頭コメント「install 自体は
/// プラットフォームチャンネルが必要なため flutter test では検証できない」と
/// 同じ制約への対処）。
SymbolLayerProperties landmarkSymbolLayerProperties({double iconSize = 1.0}) {
  return SymbolLayerProperties(
    iconImage: const ['get', 'icon'],
    iconSize: iconSize,
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );
}
