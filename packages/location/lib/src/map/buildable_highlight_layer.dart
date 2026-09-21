import 'package:maplibre_gl/maplibre_gl.dart';

/// 建設タブで建物を選んだ際、地図上で「建てられるマス」をハイライトする
/// 塗りレイヤーの色・不透明度の設定値（Issue #192・T089）。
///
/// 【Issue #57 の注入方式を踏襲】`packages/location` は配色を一切知らない。色・
/// 不透明度は composition root である `app` がコンストラクタ引数で注入する
/// （`app/lib/map/buildable_highlight_layer_factory.dart` が DESIGN.md の
/// `success` トークンから組み立てる。`terrain_tint_layer.dart` の
/// `TerrainTintLayer` と同じ役割分担）。
class BuildableHighlightLayer {
  const BuildableHighlightLayer({
    required this.fillColorHex,
    required this.fillOpacity,
  });

  /// `#RRGGBB` 形式の16進文字列。値の正しさは呼び出し側（`app`）の責務。
  final String fillColorHex;

  /// `fill-opacity` に渡す不透明度（0.0〜1.0）。
  final double fillOpacity;
}

/// [layer] の設定から、fog と同じ GeoJSON ソースに対して追加する塗り(fill)レイヤーの
/// プロパティを組み立てる（Issue #192）。`terrain_tint_layer.dart` の
/// `terrainTintFillLayerProperties` と同じ設計（`MapLibreMapController` に依存しない
/// 純粋関数）。
///
/// 【`feature-state` はペイントプロパティでのみ使う】`fill-opacity` はペイント
/// プロパティであり、`feature-state` 式が実際に評価される（`terrain_tint_layer.dart`
/// クラスdoc「Issue #170 の教訓」と同じ理由）。feature-state のキーは `buildable`
/// （`revealed`・`terrain_type` とは別の独立したキー。同じソースの同じ Feature に
/// 複数の feature-state キーを共存させられる——MapLibre の feature-state は
/// Feature 単位のキー・バリューの集合であり、キーごとに独立してトグルできる）。
FillLayerProperties buildableHighlightFillLayerProperties(
  BuildableHighlightLayer layer,
) {
  return FillLayerProperties(
    fillColor: layer.fillColorHex,
    fillOpacity: [
      'case',
      const [
        'boolean',
        ['feature-state', 'buildable'],
        false,
      ],
      layer.fillOpacity,
      0.0,
    ],
  );
}

/// 建設タブで選んだ建物が「建てられるマス」を、fog と同じ GeoJSON ソースの
/// feature-state（`buildable`）で地図上にハイライトする（Issue #192・T089）。
///
/// [FogOfWarController]・[TerrainTintController] と並ぶ、レイヤー種別ごとの
/// コントローラ。[TerrainTintController] クラスdoc「新しいソースを追加しない」
/// 「タップを吸わない」と同じ方針を踏襲する:
///   - [install] は新しい GeoJSON ソースを追加せず、fog が追加済みのソース
///     （[sourceId]）をそのまま参照する。
///   - 追加する fill レイヤーは `enableInteraction: false` で登録し、
///     霧ヘクスのタップ（`onMapClick` → `MapView.onFogHexTapped`）を吸わない。
///
/// ## `revealed`・`terrain_type` との独立性
/// 本コントローラが読み書きするのは feature-state の `buildable` キーのみで
/// あり、fog の `revealed`（[FogOfWarController]）・地形色分けが参照する
/// `terrain_type`（Feature の `properties`、feature-state ではない）とは
/// 独立している。[setHighlighted] は `buildable` キーだけを `setFeatureState`/
/// `removeFeatureState(..., stateKey: 'buildable')` でトグルするため、
/// `revealed` の状態を誤って書き換えることはない
/// （`removeFeatureState` に `stateKey` を渡すと、そのキーだけが削除され
/// 他のキーはそのまま残る。maplibre_gl の Android 実装
/// `MapLibreMapController.java`「featureId!=null かつ stateKey!=null なら
/// そのキーだけ削除」で確認済み）。
class BuildableHighlightController {
  BuildableHighlightController._(this._controller, this.sourceId, this.layerId);

  final MapLibreMapController _controller;

  /// 参照する（fogが追加済みの）GeoJSON ソースのID。
  final String sourceId;

  /// 本コントローラが追加した fill レイヤーのID。
  final String layerId;

  static const defaultLayerId = 'terra_town_buildable_highlight_layer';

  /// 現在ハイライト中の `feature_id` の集合（[setHighlighted] が差分更新に使う）。
  final Set<int> _highlighted = {};

  /// fog と同じ [sourceId] のソースに対し、ハイライト用の fill レイヤーを1枚
  /// 追加する。[belowLayerId] を指定すると、そのレイヤーの直下に挿入する
  /// （`TerrainTintController.install` と同じ引数の意味）。
  static Future<BuildableHighlightController> install(
    MapLibreMapController controller,
    BuildableHighlightLayer layer, {
    required String sourceId,
    String layerId = defaultLayerId,
    String? belowLayerId,
  }) async {
    await controller.addFillLayer(
      sourceId,
      layerId,
      buildableHighlightFillLayerProperties(layer),
      belowLayerId: belowLayerId,
      // 【必須】クラスdoc「タップを吸わない」参照。
      enableInteraction: false,
    );

    return BuildableHighlightController._(controller, sourceId, layerId);
  }

  /// ハイライト対象を [featureIds] に置き換える（差分だけ `setFeatureState`/
  /// `removeFeatureState` を発行する）。
  ///
  /// 建設タブで建物を選ぶたびに（建物ごとに建てられるマスが変わるため）呼ぶ
  /// ことを想定する。空集合を渡すと [clear] と同じ効果になる。
  Future<void> setHighlighted(Set<int> featureIds) async {
    final toAdd = featureIds.difference(_highlighted);
    final toRemove = _highlighted.difference(featureIds);

    for (final featureId in toAdd) {
      await _controller.setFeatureState(sourceId, featureId.toString(), {
        'buildable': true,
      });
    }
    for (final featureId in toRemove) {
      await _controller.removeFeatureState(
        sourceId,
        featureId: featureId.toString(),
        stateKey: 'buildable',
      );
    }

    _highlighted
      ..clear()
      ..addAll(featureIds);
  }

  /// ハイライトを全て解除する（建設の選択をやめた・確定した場合に呼ぶ）。
  Future<void> clear() => setHighlighted(const {});
}
