import 'dart:typed_data';

import 'package:flutter/foundation.dart' show immutable;
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:terra_town_core/terra_town_core.dart' show BuildingType;

import '../db/game_database.dart' show BuildingRow;
import 'hex_feature_bridge.dart';

/// 建物レイヤー（Issue #193・T090）の描画に使うラスタ画像一式。
///
/// [landmark_layer.dart] の `LandmarkPinImages` と同じ役割分担（`location` は
/// 配色・Material アイコンのいずれも知らず、`app`〔`building_layer_factory.dart`〕
/// が完成済みのラスタ画像〔PNGバイト列〕を組み立てて渡す）。名所ピンと異なり、
/// 建物の見た目は**建物種別（[BuildingType]。8種）だけ**で決まり POI 単位の
/// 個体差（名称ラベル・収集状態）が無いため、画像は建物種別の数（8枚）だけで足りる。
@immutable
class BuildingIconImages {
  const BuildingIconImages(this.images);

  /// 画像名（[buildingIconId] が返す文字列）→ PNGバイト列。
  final Map<String, Uint8List> images;
}

/// [BuildingLayerController.install] に渡す一式（Issue #193・T090）。
///
/// [LandmarkLayerAssets] と同じく、画像生成（`dart:ui` のラスタライズを伴い
/// 非同期）と featureCollection の組み立て（同期）をまとめて `Future` として
/// `MapView.buildingAssets` に渡せるようにしている。
@immutable
class BuildingLayerAssets {
  const BuildingLayerAssets({
    required this.images,
    required this.featureCollection,
  });

  final BuildingIconImages images;

  /// [buildBuildingFeatureCollection] が組み立てた GeoJSON FeatureCollection。
  final Map<String, dynamic> featureCollection;
}

/// [type] の仮アイコン画像のID（Issue #193 本文「種別 → 画像名の対応を
/// 1か所にまとめる」）。
///
/// **正式なスプライトに差し替える際は、この関数の戻り値の組み立て方だけを
/// 変えれば足りる**——`app` 側の `building_layer_factory.dart` はこの関数が
/// 返すキーに対して画像を登録するだけで、`location` 側（本レイヤーの GeoJSON
/// 組み立て・シンボルレイヤーの `icon-image` 式）はキーの中身（Material アイコン
/// 合成か、正式なPNG読込か）を一切知らない設計にしている。[BuildingType.name] は
/// `building` テーブルの `buildingType` 列の永続化にも使われる安定した識別子
/// （`building_type.dart` クラスdoc「列挙値の名前は1文字も変えていない」）であり、
/// 画像名としてもそのまま使って問題ない。
String buildingIconId(BuildingType type) => 'terra_town_building_${type.name}';

/// [buildings] の各行を、対応するヘクス中心（[hexCenterLonLatByHexId]。
/// `building_hex_center.dart` の `hexCentersFromRegionPack` 参照）に配置する
/// シンボル用 GeoJSON FeatureCollection に変換する（Issue #193・T090）。
///
/// 名所ピン（`buildLandmarkFeatureCollection`）と同じく、各 Feature は
/// `properties` の外（直下）に整数 `id` を持つ（`promoteId` が Android で
/// 機能しないため。`hex_feature_bridge.dart`・`landmark_layer.dart` 参照）。
/// 1ヘクスにつき建物は最大1棟（`Buildings.uniqueKeys`）であるため、
/// [hexIdToFeatureId]（地域パックの `hex_terrain.feature_id` と同じ体系。
/// H3 index の下位52bitマスク）をそのまま使って一意な整数 `id` を割り当てる。
///
/// [hexCenterLonLatByHexId] に対応する中心が無い建物（`hex_terrain` に該当行が
/// 無い・境界ジオメトリが読めない等。forward-compat。`hexCentersFromRegionPack`
/// クラスdoc参照）は除外する。
Map<String, dynamic> buildBuildingFeatureCollection(
  Iterable<BuildingRow> buildings,
  Map<int, List<double>> hexCenterLonLatByHexId,
) {
  final features = <Map<String, dynamic>>[];
  for (final building in buildings) {
    final center = hexCenterLonLatByHexId[building.hexId];
    if (center == null) continue;
    features.add({
      'type': 'Feature',
      // ⚠️ properties の外（直下）に整数 id を持たせる（promoteId は Android
      // 非対応。名所ピン・fog と同じ理由。
      // `validateBuildingFeatureCollectionIds` が検証する）。
      'id': hexIdToFeatureId(building.hexId),
      'geometry': {'type': 'Point', 'coordinates': center},
      'properties': {
        // hex_id（H3 index）は 2^53-1 を超えうるため文字列で持たせる
        // （`fog_hex_source.dart` の `hex_id_str` と同じ理由）。
        'hex_id_str': building.hexId.toString(),
        'building_type': building.buildingType.name,
        'icon': buildingIconId(building.buildingType),
      },
    });
  }
  return {'type': 'FeatureCollection', 'features': features};
}

/// [featureCollection] の各 Feature が、`properties` の中ではなく直下に整数
/// `id` を持つことを検証する（[validateLandmarkFeatureCollectionIds] と同じ
/// 役割）。違反があれば [ArgumentError] を投げる。
void validateBuildingFeatureCollectionIds(
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
        '建物レイヤーの各 Feature は直下（properties の外）に整数 id を'
            '持つ必要があります（promoteId は Android で機能しないため）。',
      );
    }
  }
}

/// [BuildingLayerController.install] が追加するシンボルレイヤーの見た目
/// （レイアウトプロパティ）を組み立てる。`landmarkSymbolLayerProperties` と
/// 同じ理由（`MapLibreMapController`〔プラットフォームチャンネル必須〕に
/// 依存せず、組み立てた式そのものを `flutter test` で検証できるようにする）で
/// `install` 本体から切り出した純粋関数にしている。
///
/// `icon-image` は `['get', 'icon']`（Issue #193 本文「`properties.icon` を
/// `['get', 'icon']` で描き分ける」・名所ピンと同じ方式）。**feature-state は
/// レイアウトプロパティでは評価されない**（Issue #170 の教訓・
/// `landmark_layer.dart` クラスdoc参照）ため使わない。建物は一度建てたら
/// 見た目が変わらない（新規建設は Feature の集合が増えるだけ。
/// [BuildingLayerController] クラスdoc参照）ため、そもそも feature-state で
/// トグルする対象自体が存在しない。
SymbolLayerProperties buildingSymbolLayerProperties({double iconSize = 1.0}) {
  return SymbolLayerProperties(
    iconImage: const ['get', 'icon'],
    iconSize: iconSize,
    iconAllowOverlap: true,
    iconIgnorePlacement: true,
  );
}

/// 建物レイヤー（Issue #193・T090）の地図登録・再構築を担う
/// （[LandmarkLayerController]・[TerrainTintController] と並ぶ、各レイヤー
/// 種別ごとのコントローラ）。
///
/// ## 名所ピンと異なり feature-state / 個別トグルを持たない
/// 名所ピンは「伏せ→開示済み→収集済み」と同一 Feature の見た目が変化するが、
/// 建物は一度建てたら見た目は変わらない。変化するのは Feature の**集合**
/// （新規建設のたびに1件増える）だけであるため、[refresh] は常に
/// `setGeoJsonSource` で全件差し替えるだけの単純な設計にしている。想定される
/// 建物の件数（1ヘクス1棟・1人のプレイヤーが建てた分のみ）では、フルリプレースでも
/// 負荷は問題にならない（[LandmarkLayerController] クラスdoc「名所は全国で
/// 51件程度のためフルリプレースでも負荷は問題にならない」と同じ考え方。建物は
/// さらに件数が少ない）。
///
/// ## タップを吸わない（Issue #151・#160・#176 と同じ落とし穴・最重要）
/// [install] は必ず `enableInteraction: false` で追加し、霧のヘクスのタップ・
/// 名所ピンの表示を妨げない（Issue #193 受け入れ基準「霧のヘクスのタップ・
/// 名所ピンの表示を妨げない」）。
///
/// ## 正は `building` テーブルである
/// ここで管理する GeoJSON ソースは描画のための派生状態にすぎない。正は
/// `packages/location` の `building` テーブル（`BuildingRepository`）であり、
/// [install] 呼び出し時点の全件が初期表示になる（名所ピンと異なり「まず伏せて
/// 後から反映する」復元手順は不要）。新規建設の反映（**再起動なしで表示が
/// 増える**。Issue #193 受け入れ基準）は、呼び出し側（`map_screen.dart`）が
/// 建築成功のたびに [refresh] を呼ぶことで実現する。
class BuildingLayerController {
  BuildingLayerController._(this._controller, this.sourceId);

  final MapLibreMapController _controller;

  /// このコントローラが管理する GeoJSON ソースのID。
  final String sourceId;

  static const defaultSourceId = 'terra_town_building';
  static const defaultLayerId = 'terra_town_building_layer';

  /// [featureCollection] を1回だけ `addGeoJsonSource` でソースに追加し、
  /// [images] を `addImage` で登録したうえで、`icon-image` が
  /// `properties.icon`（[buildingSymbolLayerProperties] 参照）を参照する
  /// シンボルレイヤーを追加する。
  static Future<BuildingLayerController> install(
    MapLibreMapController controller,
    BuildingIconImages images,
    Map<String, dynamic> featureCollection, {
    String sourceId = defaultSourceId,
    String layerId = defaultLayerId,
    double iconSize = 1.0,
  }) async {
    validateBuildingFeatureCollectionIds(featureCollection);

    for (final entry in images.images.entries) {
      await controller.addImage(entry.key, entry.value);
    }

    await controller.addGeoJsonSource(sourceId, featureCollection);

    await controller.addSymbolLayer(
      sourceId,
      layerId,
      buildingSymbolLayerProperties(iconSize: iconSize),
      // 【必須】クラスdoc「タップを吸わない」参照。
      enableInteraction: false,
    );

    return BuildingLayerController._(controller, sourceId);
  }

  /// 新規建設の反映（Issue #193 受け入れ基準「建てた建物が、再起動なしで
  /// ヘクス中心に種別ごとの仮アイコンで表示される」）。[featureCollection] で
  /// ソース全体を差し替える（クラスdoc「feature-state / 個別トグルを持たない」
  /// 参照）。呼び出し側（`map_screen.dart`）が `BuildingRepository.findAll()` を
  /// 再取得し、[buildBuildingFeatureCollection] で組み立て直したものを渡すこと。
  Future<void> refresh(Map<String, dynamic> featureCollection) {
    validateBuildingFeatureCollectionIds(featureCollection);
    return _controller.setGeoJsonSource(sourceId, featureCollection);
  }
}
