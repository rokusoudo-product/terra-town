import 'package:maplibre_gl/maplibre_gl.dart';

/// Fog of war（未開示ヘクスの暗幕）レイヤーの色・不透明度の設定値。
///
/// 【設計方針・Issue #57（代表決定 2026-09-07・注入方式）】
/// `packages/location` は配色を一切知らない。色・不透明度は
/// composition root である `app` がコンストラクタ引数で注入する。
/// `location` に `terra_town` の配色パッケージへの依存を持たせないのは、
/// `GPS_ARCHITECTURE.md` の狙い（GPS まわりの実装を今後の GPS 利用アプリ間で
/// 使い回せる資産にすること）と整合させるため。`location` が特定アプリの
/// 配色に依存すると、他アプリへ移植する際に配色が付いてきてしまい、
/// この狙いに反する。
///
/// 色の正しさ（DESIGN.md のトークンと一致すること）を担保する責務は
/// `app` 側（`app/lib/map/fog_of_war_layer_factory.dart` とそのテスト）にあり、
/// `location` 側のテストはフェイク値を渡して「受け取った値をそのまま保持する」
/// ことだけを検証する。
///
/// MapLibre への実際のレイヤー登録・`feature-state` によるトグル処理は
/// [FogOfWarController]（本ファイル下部・タスク T056）が担う。本クラス自体は
/// 純粋な設定値であり、`maplibre_gl` の型には依存しない。
class FogOfWarLayer {
  const FogOfWarLayer({required this.fillColorHex, required this.fillOpacity});

  /// MapLibre のスタイル式（`fill-color`）に渡す `#RRGGBB` 形式の16進文字列。
  /// 値の正しさは呼び出し側（`app`）の責務であり、ここでは検証しない。
  final String fillColorHex;

  /// `fill-opacity` に渡す不透明度（0.0〜1.0）。未開示ヘクスの暗幕の濃さ。
  final double fillOpacity;
}

/// 全ヘクスを表す GeoJSON FeatureCollection から fog of war のソース/レイヤーを
/// 地図に登録し、以後の開示トグルの窓口を提供する（tasks.md T056・plan.md §8）。
///
/// ## 採用方式（plan.md §8・変更不可）
/// 全ヘクスを起動時／エリア切替時に**1回だけ** [MapLibreMapController.addGeoJsonSource]
/// でソースに追加し、開示は fill レイヤの `fill-opacity` を feature-state
/// （[MapLibreMapController.setFeatureState]）のトグルで切り替える。更新コストが
/// 開示済みヘクス数に依存しない（O(1)）ことが実機計測（research.md §6.4）で
/// 確認されている。
///
/// ## Feature の `id` 要件
/// [hexFeatureCollection] の各 Feature は `properties` の中ではなく**直下**に
/// 整数 `id` を持つ必要がある。`promoteId` は Web 専用で Android では機能しない
/// ため（research.md §6.3）、[install] はこれを実行時に検証し、違反があれば
/// [ArgumentError] を投げる。
///
/// ## スコープ（Issue #100）
/// 本クラスが提供するのは「任意のヘクスを開示する API」までである。以下は
/// 本クラスの責務**外**:
///   - どのヘクスを開示すべきかの判定（歩行による開示判定・T054・Issue #101）
///   - [hexFeatureCollection] そのものの組み立て。**2026-09-10・Issue #105 で解決**:
///     地域パックの `hex_terrain` テーブルは、ヘクス境界ジオメトリ
///     （`boundary_geojson` 列）を**パック生成時に事前計算済み**として持つ
///     （`tools/pack-builder/hex_geometry.py`・代表決定の案A）。本パッケージの
///     [buildFogHexFeatureCollectionFromRegionPack]（`fog_hex_source.dart`）が
///     [RegionPackConnection] からこれを読み出し、そのまま渡せる
///     FeatureCollection を組み立てる（T056 の責務。`core` の `RegionPack` 抽象
///     ＝ T069・`RegionPackRepository` は幾何を扱えないため、この処理は
///     構造的に T069 には属さない — `fog_hex_source.dart` の docstring参照）。
///     本クラス（[install]）自体は従来どおり、組み立て済みの FeatureCollection
///     を受け取るだけに留める（責務を分離するため、本クラスが直接
///     [RegionPackConnection] を読むことはしない）
///   - 開示状態の永続化・復元（T060・Issue #102）
///
/// ## ⚠️ 開示状態の正は永続ストレージである（最重要）
/// ここで管理する feature-state は**描画のための派生状態にすぎず、開示状態の
/// 正ではない**。正は `disclosed_hex` テーブル
/// （`packages/core/lib/src/pack/disclosed_hex.dart`）である。
///
/// 2026-09-09 の実機検証で、`setStyle`（スタイル再読み込み）を呼ぶと feature-state が
/// **全て失われる**ことが確認されている（plan.md §8・research.md §6.4）。したがって
/// アプリ再起動時・および任意の `setStyle` の後は、`disclosed_hex` から読み直して
/// [revealHex] を必要な回数呼び直すことで feature-state を再構築する必要がある。
/// **その復元処理そのものは本クラスの責務ではなく別 Issue（T060）の範囲**であり、
/// 本クラスは「呼ばれれば安全にトグルできる」ことだけを保証する。
///
/// MVP では実行時に `setStyle` を伴う機能を入れない方針が確定している
/// （plan.md §8・2026-09-09 代表決定）ため、本 Issue の時点では上記の再構築が
/// 実際に発生する経路はまだ無い。
class FogOfWarController {
  FogOfWarController._(this._controller, this.sourceId, this._layer);

  final MapLibreMapController _controller;

  /// このコントローラが管理する GeoJSON ソースのID。
  final String sourceId;

  /// [install] に渡された色・不透明度設定（`app` から注入された値）。
  /// [installBenchmarkLayerForDebug] が再利用する（`location` はここでも
  /// 独自の色を持たない。Issue #57 の注入方式を計測用レイヤーにも適用する）。
  final FogOfWarLayer _layer;

  static const defaultSourceId = 'terra_town_fog';
  static const defaultLayerId = 'terra_town_fog_layer';

  /// 【デバッグ専用】本番相当のヘクス数でのソース構築コストを計測するための
  /// 一時的な別ソース/レイヤーのID（[installBenchmarkSourceForDebug] 参照）。
  /// 表示中の fog ソース（[sourceId]）とは独立しており、計測が表示中の霧に
  /// 影響を与えない。
  static const benchmarkSourceId = 'terra_town_fog_benchmark';
  static const benchmarkLayerId = 'terra_town_fog_benchmark_layer';

  /// [hexFeatureCollection] を**1回だけ** `addGeoJsonSource` でソースに追加し、
  /// fill レイヤの `fill-opacity` を feature-state（`revealed`）で切り替える
  /// 表現で追加する（plan.md §8 の採用方式）。
  ///
  /// [layer] の色・不透明度をそのまま使う（`location` はここでも配色を知らない。
  /// Issue #57 の注入方式）。
  static Future<FogOfWarController> install(
    MapLibreMapController controller,
    FogOfWarLayer layer,
    Map<String, dynamic> hexFeatureCollection, {
    String sourceId = defaultSourceId,
    String layerId = defaultLayerId,
  }) async {
    validateFogHexFeatureCollectionIds(hexFeatureCollection);

    await controller.addGeoJsonSource(sourceId, hexFeatureCollection);
    await controller.addFillLayer(
      sourceId,
      layerId,
      FillLayerProperties(
        fillColor: layer.fillColorHex,
        // feature-state 'revealed' が true なら透明（霧が晴れる）、
        // 未設定/false なら [layer.fillOpacity]（未開示ヘクスの暗幕の不透明度）。
        // plan.md §8 に実装例として記載された式をそのまま採用する。
        fillOpacity: [
          'case',
          [
            'boolean',
            ['feature-state', 'revealed'],
            false,
          ],
          0.0,
          layer.fillOpacity,
        ],
      ),
    );

    return FogOfWarController._(controller, sourceId, layer);
  }

  /// 指定ヘクスを開示済みにする（`setFeatureState` の1回のトグル・O(1)）。
  ///
  /// 【正は disclosed_hex であることの再掲】ここでの状態変更は描画のための
  /// 派生状態の更新にすぎない。恒久的な記録（`disclosed_hex` テーブルへの
  /// 書き込み）は呼び出し側（開示判定ロジック・T054）の責務であり、本メソッド
  /// 自体はデータベースに一切触れない。
  Future<void> revealHex(int featureId) {
    return _controller.setFeatureState(sourceId, featureId.toString(), {
      'revealed': true,
    });
  }

  /// 【デバッグ専用】指定ヘクスを未開示（霧）に戻す。
  /// 開示は不可逆（plan.md）であり、製品ロジックとして「開示を取り消す」機能は
  /// 存在しない。代表が実機で確認する際に「もう一度霧を張り直して再確認したい」
  /// というニーズのためだけに用意する。
  Future<void> hideHexForDebug(int featureId) {
    return _controller.setFeatureState(sourceId, featureId.toString(), {
      'revealed': false,
    });
  }

  /// 【デバッグ専用】このソースの feature-state を全てリセットする
  /// （全ヘクスを霧に戻す）。
  Future<void> resetAllForDebug() {
    return _controller.removeFeatureState(sourceId);
  }

  /// 【デバッグ専用】指定ヘクスが開示済みかを問い合わせる（feature-state からの
  /// 読み出し）。あくまで描画状態の確認用であり、正の判定には使わないこと。
  Future<bool> isRevealedForDebug(int featureId) async {
    final state = await _controller.getFeatureState(
      sourceId,
      featureId.toString(),
    );
    return state?['revealed'] == true;
  }

  /// 【デバッグ専用・受け入れ基準「本番パックのヘクス数（13,106）でのソース構築
  /// コストを計測する手順」に対応】表示中の fog ソース（[sourceId]）とは独立の
  /// 一時ソースとして [hexFeatureCollection] を追加し、`addGeoJsonSource` 単体の
  /// 所要時間を呼び出し側で計測できるようにする。計測後は必ず
  /// [removeBenchmarkSourceForDebug] で片付けること。
  Future<void> installBenchmarkSourceForDebug(
    Map<String, dynamic> hexFeatureCollection,
  ) {
    return _controller.addGeoJsonSource(
      benchmarkSourceId,
      hexFeatureCollection,
    );
  }

  /// 【デバッグ専用】[installBenchmarkSourceForDebug] の直後に呼び、レイヤー追加
  /// までを含めた「合計」コスト（plan.md §8 の実測値の言い回しに合わせる）を
  /// 計測できるようにする。不透明度0で追加するため画面には影響しない
  /// （色は [_layer]＝`app` から注入された値をそのまま使う。計測用レイヤーの
  /// ためだけに `location` 側で独自の色リテラルを持たない）。
  Future<void> installBenchmarkLayerForDebug() {
    return _controller.addFillLayer(
      benchmarkSourceId,
      benchmarkLayerId,
      FillLayerProperties(fillColor: _layer.fillColorHex, fillOpacity: 0.0),
    );
  }

  /// 【デバッグ専用】計測用の一時ソース/レイヤーを片付ける。計測が
  /// レイヤー追加前に失敗した場合でも安全に呼べるよう、個別に例外を握りつぶす
  /// （デバッグ用の後始末であり、本番の失敗検知経路には影響させない）。
  Future<void> removeBenchmarkSourceForDebug() async {
    try {
      await _controller.removeLayer(benchmarkLayerId);
    } catch (_) {
      // レイヤー未追加のまま呼ばれた場合等は無視する（デバッグ後始末のため）。
    }
    try {
      await _controller.removeSource(benchmarkSourceId);
    } catch (_) {
      // 同上。
    }
  }
}

/// [featureCollection] の各 Feature が、`properties` の中ではなく直下に整数 `id`
/// を持つことを検証する（受け入れ基準「各 Feature が直下に整数 `id` を持つ形で
/// ソースに追加されている（`promoteId` を使っていない）」）。
///
/// [FogOfWarController.install] が実際の地図登録の直前に呼ぶ。`MapLibreMapController`
/// に依存しない純粋関数として切り出してあるため、プラットフォームチャンネルが
/// 無い `flutter test` 環境でも単体で検証できる
/// （`packages/location/test/map/fog_of_war_layer_test.dart` 参照）。
///
/// 違反があれば [ArgumentError] を投げる。`promoteId`（Web 専用）で `properties`
/// から昇格させる誤った実装を、実機で気づく前に検知するための安全弁。
void validateFogHexFeatureCollectionIds(
  Map<String, dynamic> featureCollection,
) {
  final features = featureCollection['features'];
  if (features is! List) {
    throw ArgumentError.value(
      featureCollection,
      'hexFeatureCollection',
      'FeatureCollection の features が見つかりません',
    );
  }
  for (final feature in features) {
    if (feature is! Map || feature['id'] is! int) {
      throw ArgumentError.value(
        feature,
        'feature',
        'fog of war の各 Feature は直下（properties の外）に整数 id を'
        '持つ必要があります（promoteId は Android で機能しないため）。'
        'plan.md §8 参照。',
      );
    }
  }
}
