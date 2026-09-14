import 'package:maplibre_gl/maplibre_gl.dart';

/// 開示済みヘクスを地形タイプ別に色分けする塗り・縁取りレイヤーの設定値
/// （Issue #176・見た目の定義は #175 の承認文面）。
///
/// 【Issue #57 の注入方式を踏襲】`packages/location` は配色を一切知らない。色・
/// 不透明度・線幅は composition root である `app` がコンストラクタ引数で注入する
/// （`app/lib/map/terrain_tint_layer_factory.dart` が DESIGN.md のトークンおよび
/// Issue #175 の承認文面から組み立てる。`fog_of_war_layer.dart` の
/// `FogOfWarLayer` と同じ役割分担）。
///
/// 【空き地・未知の terrain_type は塗らない】[fillColorHexByTerrainType] の
/// キーに無い `terrain_type`（空き地 `vacant_lot`・将来追加されうる未知の値を含む）は、
/// [terrainTintFillLayerProperties] が組み立てる `fill-opacity` の `match` 式の
/// 既定値（0.0）にフォールバックし、常に塗られない（#176 受け入れ基準「開示済みの
/// 空き地は塗られず、縁取りだけが表示される」「未知の terrain_type は塗らない」）。
/// #175 承認文面の時点では forest・mountain・waterside・sea の4種のみが対象。
///
/// 【縁取りは terrain_type によらず開示済み全ヘクス】[outlineColorHex]・
/// [outlineOpacity]・[outlineWidth] は、[fillColorHexByTerrainType] に無い
/// terrain_type（空き地を含む）にも適用する（#175 承認文面「縁取り: 開示済み
/// ヘクス（空き地を含む全地形）に...」）。
class TerrainTintLayer {
  const TerrainTintLayer({
    required this.fillColorHexByTerrainType,
    required this.fillOpacity,
    required this.outlineColorHex,
    required this.outlineOpacity,
    required this.outlineWidth,
  });

  /// 地域パックの `hex_terrain.terrain_type`（スネークケース文字列。例: `forest`）
  /// → `#RRGGBB` 形式の塗り色。ここに無いキーの terrain_type は塗らない
  /// （クラスdoc「空き地・未知の terrain_type は塗らない」参照）。値の正しさ
  /// （DESIGN.md・#175 承認文面のトークンと一致すること）は呼び出し側（`app`）の責務。
  final Map<String, String> fillColorHexByTerrainType;

  /// [fillColorHexByTerrainType] に列挙された地形タイプに共通で使う、開示済み時の
  /// 塗りの不透明度（0.0〜1.0）。#175 承認文面はいずれの地形も 0.22 で統一されて
  /// いるため単一値とする（将来地形ごとに不透明度を変える必要が生じた場合は
  /// [fillColorHexByTerrainType] と同様の `Map<String, double>` に拡張する）。
  final double fillOpacity;

  /// 縁取りの色（`#RRGGBB`）。terrain_type によらず開示済み全ヘクスに適用する。
  final String outlineColorHex;

  /// 縁取りの不透明度（0.0〜1.0。開示済み時のみ）。
  final double outlineOpacity;

  /// 縁取りの線幅（ピクセル）。
  final double outlineWidth;
}

/// [layer] の設定から、fog と同じ GeoJSON ソースに対して追加する塗り(fill)レイヤーの
/// プロパティを組み立てる（Issue #176）。
///
/// 【`MapLibreMapController` に依存しない純粋関数にした理由】
/// `TerrainTintController.install` 本体から切り出すことで、プラットフォーム
/// チャンネルが無い `flutter test` 環境でも、組み立てた式そのものを検証できる
/// （`landmark_layer.dart` の `landmarkSymbolLayerProperties` と同じ設計。
/// `packages/location/test/map/terrain_tint_layer_test.dart` 参照）。
///
/// 【`feature-state` はペイントプロパティでのみ使う（Issue #170 の教訓）】
/// `fill-opacity` は MapLibre のスタイル仕様上のペイントプロパティであり、
/// `feature-state` 式が実際に評価される（`fill_of_war_layer.dart` の
/// `FogOfWarController.install` と同じ理由）。`fill-color` 側は `feature-state` を
/// 使わず `['get', 'terrain_type']` の `match` のみで組み立てる（terrain_type は
/// Feature の `properties` に格納済みの静的な値であり、`revealed` のような
/// 開示状態のトグルとは無関係のため）。
///
/// 【fog と同じソースの feature-state `revealed` を共有する】本関数が返す
/// `fill-opacity` は fog の `fill-opacity`（`fog_of_war_layer.dart`）と同じ
/// `['feature-state', 'revealed']` を参照する。同じソースの同じ Feature に対する
/// 状態なので、`FogOfWarController.revealHex`（新規開示）・
/// `restoreDisclosedHexes`（起動時復元）のどちらでも、本レイヤーは追加の状態管理
/// 無しに追従する（Issue #176 提案内容「feature-stateはソースのFeature単位の状態
/// なので、同じfogソースに追加したレイヤーは、開示状態を自動で共有する」）。
FillLayerProperties terrainTintFillLayerProperties(TerrainTintLayer layer) {
  final colorMatch = <dynamic>['match', const ['get', 'terrain_type']];
  final opacityMatch = <dynamic>['match', const ['get', 'terrain_type']];
  for (final entry in layer.fillColorHexByTerrainType.entries) {
    colorMatch
      ..add(entry.key)
      ..add(entry.value);
    opacityMatch
      ..add(entry.key)
      ..add(layer.fillOpacity);
  }
  // 既定値（未知の terrain_type・空き地 vacant_lot のように
  // fillColorHexByTerrainType に無いキー）。色自体は不透明度が常に0のため
  // 画面には出ないプレースホルダである。
  colorMatch.add('#000000');
  opacityMatch.add(0.0);

  return FillLayerProperties(
    fillColor: colorMatch,
    fillOpacity: [
      'case',
      const [
        'boolean',
        ['feature-state', 'revealed'],
        false,
      ],
      opacityMatch,
      0.0,
    ],
  );
}

/// [layer] の設定から、開示済みヘクス全種（空き地を含む）に適用する縁取り(line)
/// レイヤーのプロパティを組み立てる（Issue #176）。[terrainTintFillLayerProperties]
/// と対になる純粋関数（同じ理由で `MapLibreMapController` に依存しない）。
///
/// 縁取りは terrain_type によらず一律の色・幅のため、`line-color`・`line-width`
/// は定数のまま（`match`/`get` を使わない）。`line-opacity` のみ、塗りと同じ
/// `['feature-state', 'revealed']` で開示済み/未開示を切り替える。
LineLayerProperties terrainTintOutlineLayerProperties(TerrainTintLayer layer) {
  return LineLayerProperties(
    lineColor: layer.outlineColorHex,
    lineWidth: layer.outlineWidth,
    lineOpacity: [
      'case',
      const [
        'boolean',
        ['feature-state', 'revealed'],
        false,
      ],
      layer.outlineOpacity,
      0.0,
    ],
  );
}

/// 開示済みヘクスの地形タイプ別色分け（塗り→縁取り）の地図登録を担う
/// （Issue #176。[FogOfWarController]・[LandmarkLayerController] と並ぶ、
/// 各レイヤー種別ごとのコントローラ）。
///
/// ## 新しいソースを追加しない（最重要・Issue #176 提案内容）
/// [install] は `addGeoJsonSource` を呼ばない。fog が既に追加済みの GeoJSON
/// ソース（[sourceId] に渡す）をそのまま参照する。これにより:
///   - 新規ソース追加によるメモリ・構築コストの増加が無い（plan.md §8 の性能基準
///     「開示1ヘクス追加 200ms 以内・1万ヘクスで 55fps 以上」を悪化させない）。
///   - `feature-state`（`revealed`）は fog と自動的に共有される
///     （[terrainTintFillLayerProperties] クラスdoc参照）。
///
/// ## 描画順は `belowLayerId` で制御する
/// 受け入れ基準の描画順（ベース地図 → **地形の塗り → 縁取り** → fog → 名所ピン →
/// 現在地マーカー）を満たすため、[MapView]（`map_view.dart`）は本メソッドを
/// **fog レイヤー追加後**に、[belowLayerId] に fog のレイヤーIDを渡して呼ぶ。
/// `MapLibreMapController.addFillLayer`/`addLineLayer` の `belowLayerId` は
/// 「指定レイヤーの直下に挿入する」という意味（maplibre_gl のドキュメント参照）
/// であるため、fill→line の順に同じ `belowLayerId`（fogのレイヤーID）を指定して
/// 追加すると、最終的な重なり順は下から
/// `...地域パック → 塗り(fill) → 縁取り(line) → fog` になる
/// （後から追加した line が fog の直下に割り込むため、先に追加した fill は
/// その分だけ line の下に押し下げられる）。
///
/// ## タップを吸わない（Issue #151・#160 と同じ落とし穴・最重要）
/// [install] は両レイヤーとも `enableInteraction: false` で追加する。塗り・
/// 縁取りのどちらか一方でも既定（`enableInteraction: true`）のまま追加すると、
/// 霧ヘクスのタップ（`onMapClick` → ポイント開放シート。`map_view.dart`
/// `_handleMapClick` 参照）がこのレイヤーに吸われてしまう。
class TerrainTintController {
  TerrainTintController._(this.fillLayerId, this.lineLayerId);

  /// 塗り(fill)レイヤーのID。
  final String fillLayerId;

  /// 縁取り(line)レイヤーのID。
  final String lineLayerId;

  static const defaultFillLayerId = 'terra_town_terrain_tint_fill_layer';
  static const defaultLineLayerId = 'terra_town_terrain_tint_line_layer';

  /// fog と同じ [sourceId] のソースに対し、塗り(fill)→縁取り(line)の順で2レイヤーを
  /// 追加する。[belowLayerId] を指定すると、両レイヤーとも指定レイヤーの直下に
  /// 挿入する（クラスdoc「描画順は belowLayerId で制御する」参照）。
  static Future<TerrainTintController> install(
    MapLibreMapController controller,
    TerrainTintLayer layer, {
    required String sourceId,
    String fillLayerId = defaultFillLayerId,
    String lineLayerId = defaultLineLayerId,
    String? belowLayerId,
  }) async {
    await controller.addFillLayer(
      sourceId,
      fillLayerId,
      terrainTintFillLayerProperties(layer),
      belowLayerId: belowLayerId,
      // 【必須】クラスdoc「タップを吸わない」参照。
      enableInteraction: false,
    );
    await controller.addLineLayer(
      sourceId,
      lineLayerId,
      terrainTintOutlineLayerProperties(layer),
      belowLayerId: belowLayerId,
      // 【必須】クラスdoc「タップを吸わない」参照。
      enableInteraction: false,
    );

    return TerrainTintController._(fillLayerId, lineLayerId);
  }
}
