import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'fog_of_war_layer.dart';
import 'map_camera_position.dart';
import 'mbtiles_source.dart';

/// vector タイルの1層に対する塗り(fill)の見た目。
///
/// 【Issue #57 の注入方式を踏襲】`location` は配色を知らない。色は composition root
/// （`app`）が DESIGN.md のトークンから導出し、`#RRGGBB` 文字列として注入する
/// （`app/lib/design/map_style_colors.dart` の `MapStyleColor` 拡張・
/// `app/lib/map/fog_of_war_layer_factory.dart` と同じ役割分担）。
@immutable
class MapFillLayerStyle {
  const MapFillLayerStyle({
    required this.id,
    required this.sourceLayer,
    required this.fillColorHex,
    this.fillOpacity = 1.0,
    this.minzoom,
    this.maxzoom,
  });

  /// レイヤーID（同一 [MapView] 内で一意であること）。
  final String id;

  /// 参照する MBTiles 内のソースレイヤー名（例: `water`・`landcover`・`building`。
  /// 推測せず実測で確認したレイヤー名を渡すこと。呼び出し側の責務）。
  final String sourceLayer;

  /// `#RRGGBB` 形式の16進文字列。値の正しさは呼び出し側の責務。
  final String fillColorHex;

  /// 0.0〜1.0。
  final double fillOpacity;

  /// 表示するズーム範囲（省略時は [MapView.sourceMinzoom]/[MapView.sourceMaxzoom]）。
  final double? minzoom;
  final double? maxzoom;
}

/// vector タイルの1層に対する線の見た目（例: 道路）。
@immutable
class MapLineLayerStyle {
  const MapLineLayerStyle({
    required this.id,
    required this.sourceLayer,
    required this.lineColorHex,
    this.lineOpacity = 1.0,
    this.lineWidth = 1.0,
    this.minzoom,
    this.maxzoom,
  });

  final String id;
  final String sourceLayer;
  final String lineColorHex;
  final double lineOpacity;
  final double lineWidth;
  final double? minzoom;
  final double? maxzoom;
}

/// 同梱 MBTiles をローカル読込して表示する地図ビュー（tasks.md T055）。
///
/// 【スコープ】本ウィジェットは「同梱の地域パック（ベクタタイル MBTiles）を
/// ローカル読込して表示する」ところと、fog of war（未開示ヘクスの暗幕・
/// plan.md §8・tasks.md T056。[fogOfWarLayer]/[fogHexFeatureCollection] が
/// 渡された場合のみ）を担う。現在地表示と地図追従（T058）は含まない。
///
/// 【入力】[mbtilesFilePath] は呼び出し側が [resolveBundledMbtilesPath] 等で
/// あらかじめ書き込み可能な領域に用意した、実ファイルシステム上の絶対パスを渡すこと
/// （アセットバンドルのキーをそのまま渡しても読めない。`mbtiles_asset.dart` 参照）。
///
/// 【スタイルはオフライン】`styleString` に外部URL（MapLibre 公式デモ等）を
/// 使わず、背景色のみのインラインスタイルJSONを組み立てる。research.md §6.4 で
/// `demotiles.maplibre.org` への依存が HTTP 429（レート制限）を起こすことが
/// 実測で判明しているため、オンラインのデモスタイルには依存しない。
///
/// 【fog of war（T056・plan.md §8）を後から載せられる構造にしていた（Issue #99 の
/// 要件）ことの結果】`onStyleLoadedCallback`（[_addRegionPackLayers]）の中で
/// 「①地域パックの vector source を追加 → ② fill/line レイヤーを追加 →
/// ③（任意）fog of war のソース/レイヤーを追加」の順に処理する。③は
/// [fogOfWarLayer] と [fogHexFeatureCollection] の両方が渡された場合のみ実行され、
/// 同じ [MapLibreMapController] を [FogOfWarController.install] に渡す形で
/// 拡張した。[MapLibreMapController] 自体は `app` には公開しない
/// （`terra_town_location` の役割は地図SDKを隠蔽すること。`app/pubspec.yaml` は
/// `maplibre_gl` に依存していない）。fog 側の操作窓口は [onFogLayerReady] で
/// 返す [FogOfWarController]（同じく地図SDK型を漏らさない不透明ハンドル）を
/// 経由する。
///
/// 【色を知らない】fill/line の色は呼び出し側から `#RRGGBB` 文字列で受け取るのみで、
/// `Color` 型・DESIGN.md のトークンには一切依存しない（Issue #57 と同じ設計。
/// `tools/check_design_tokens.sh` は `packages/location/lib` も検査対象に含む）。
class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.mbtilesFilePath,
    required this.initialCameraPosition,
    required this.backgroundColorHex,
    this.sourceId = 'terra_town_pack',
    this.sourceMinzoom = 0,
    this.sourceMaxzoom = 14,
    this.fillLayers = const [],
    this.lineLayers = const [],
    this.onLayersFailed,
    this.fogOfWarLayer,
    this.fogHexFeatureCollection,
    this.fogSourceId = FogOfWarController.defaultSourceId,
    this.fogLayerId = FogOfWarController.defaultLayerId,
    this.onFogLayerReady,
    this.onMapControllerReady,
  });

  /// [resolveBundledMbtilesPath] 等で解決済みの、書き込み可能な領域にある
  /// MBTiles ファイルの絶対パス。
  final String mbtilesFilePath;

  final MapCameraPosition initialCameraPosition;

  /// スタイルの背景色（`#RRGGBB`）。地域パックの読込前・データが無い範囲に見える。
  final String backgroundColorHex;

  /// 地域パックの vector source ID。
  final String sourceId;

  /// 地域パック全体のズーム範囲（同梱パックの実測値: 0〜14。
  /// `tools/pack-builder/README.md`「実測（2026-09-10・狭山湖周辺エリア）」参照）。
  final double sourceMinzoom;
  final double sourceMaxzoom;

  final List<MapFillLayerStyle> fillLayers;
  final List<MapLineLayerStyle> lineLayers;

  /// 地域パックの source/layer 追加（[_MapViewState._addRegionPackLayers]）に
  /// 失敗した場合に呼ばれる。地図SDKの例外型を `app` に露出させないよう、
  /// 引数はプレーンな [Object]/[StackTrace] とする。
  ///
  /// 【本Issueがまさに解消しようとしているリスク】plan.md §8「未計測」＝
  /// 「実際の地域パック（Planetiler生成・高ズーム）でのMBTiles読込は未実施」に対し、
  /// 実機で失敗した場合に「レイヤー追加が失敗した」ことを判別できるようにする
  /// （失敗しても背景色のみの画面になるだけで、成功時との見分けが付きにくいため）。
  final void Function(Object error, StackTrace stackTrace)? onLayersFailed;

  /// fog of war の色・不透明度（T056・plan.md §8）。`app`（composition root）が
  /// DESIGN.md の `fog` トークンから導出して注入する（Issue #57 の注入方式。
  /// `location` はここでも配色を知らない）。
  ///
  /// これと [fogHexFeatureCollection] の**両方**が非 null の場合のみ、
  /// ベースレイヤーの追加後に fog of war のソース/レイヤーを追加する。
  /// どちらか一方でも null の場合は fog of war を一切追加しない（既存の
  /// Issue #99 の挙動を変えない。パック未取得時のテスト・ビルドを壊さないため）。
  final FogOfWarLayer? fogOfWarLayer;

  /// fog of war の対象となる全ヘクスの GeoJSON FeatureCollection。
  ///
  /// 【本 Issue（#100）のスコープ外であること】このデータそのものの組み立て
  /// （地域パックの `hex_terrain` テーブルから実際のヘクス境界ジオメトリを
  /// 算出する処理）は `RegionPackRepository`（tasks.md T069・本 Issue 時点で
  /// 未実装）の責務であり、[MapView] は呼び出し側が用意した完成品を
  /// 受け取るだけである。各 Feature は直下（`properties` の外）に整数 `id` を
  /// 持つ必要がある（[FogOfWarController.install] が実行時に検証する）。
  final Map<String, dynamic>? fogHexFeatureCollection;

  /// fog of war の GeoJSON ソース ID。
  final String fogSourceId;

  /// fog of war の fill レイヤー ID。
  final String fogLayerId;

  /// fog of war のソース/レイヤー追加が成功した直後に、開示トグルの窓口となる
  /// [FogOfWarController] を渡す。[MapLibreMapController] 自体は公開しない
  /// （[MapView] クラス doc コメント参照）。
  final void Function(FogOfWarController controller)? onFogLayerReady;

  /// マップ作成直後（`onMapCreated`）に、[MapCameraReader]（カメラ中心の取得のみに
  /// 限定した窓口。Issue #137）を渡す。[MapLibreMapController] 自体は公開しない
  /// （[MapView] クラス doc コメント参照）。
  ///
  /// 【用途】デバッグパネルの「地図の中心のヘクスを開示」ボタン（`kDebugMode` 限定・
  /// `app/lib/map/debug/`）が、地図の中心に最も近いパック内ヘクスを選ぶために
  /// カメラ中心の緯度経度を必要とする。本コールバックはそのためだけに用意した
  /// 最小限の口であり、カメラ移動・ズーム操作等は含まない。
  final void Function(MapCameraReader reader)? onMapControllerReady;

  @override
  State<MapView> createState() => _MapViewState();
}

/// [MapView.onMapControllerReady] が渡す、カメラ中心の読み取りに限定した窓口
/// （Issue #137）。
///
/// `location` は地図SDKの型（`MapLibreMapController`）を `app` に公開しない方針
/// （[MapView] クラス doc コメント参照）を保つため、必要な操作（カメラ中心の取得）
/// だけをピンポイントで許可する薄いラッパーとして用意した。
@immutable
class MapCameraReader {
  const MapCameraReader(this._controller);

  final MapLibreMapController _controller;

  /// 現在のカメラ中心。スタイル読込前・`onCameraMove`/`onCameraIdle` が
  /// まだ一度も発火していない場合は null（`MapLibreMapController.cameraPosition`
  /// のドキュメント参照）。利用者の操作に追従するには `MapLibreMap` の
  /// `trackCameraPosition: true` が必要（[_MapViewState.build] で指定済み）。
  MapCameraPosition? get center {
    final position = _controller.cameraPosition;
    if (position == null) return null;
    return MapCameraPosition(
      latitude: position.target.latitude,
      longitude: position.target.longitude,
      zoom: position.zoom,
      tilt: position.tilt,
      bearing: position.bearing,
    );
  }
}

class _MapViewState extends State<MapView> {
  MapLibreMapController? _controller;

  @override
  Widget build(BuildContext context) {
    return MapLibreMap(
      styleString: _backgroundOnlyStyle(widget.backgroundColorHex),
      initialCameraPosition: CameraPosition(
        target: LatLng(
          widget.initialCameraPosition.latitude,
          widget.initialCameraPosition.longitude,
        ),
        zoom: widget.initialCameraPosition.zoom,
        tilt: widget.initialCameraPosition.tilt,
        bearing: widget.initialCameraPosition.bearing,
      ),
      // maplibre_gl の `MapLibreMapController.cameraPosition` は、これを true に
      // しないと利用者が地図を動かしても更新されず、初期カメラ位置のままになる
      // （既定は false）。[MapCameraReader.center] が「現在の」カメラ中心を返すために
      // 必要（2026-09-11 実機検証で、地図を動かしても初期中心のヘクスしか選ばれない
      // ことを確認して追加）。
      trackCameraPosition: true,
      onMapCreated: (controller) {
        _controller = controller;
        widget.onMapControllerReady?.call(MapCameraReader(controller));
      },
      onStyleLoadedCallback: _addRegionPackLayers,
    );
  }

  /// 【ログの二重出力について】`developer.log` は Dart VM Service の
  /// ロギングストリームに流れるだけで、`flutter run` のコンソールには出るが
  /// `adb install` + `adb logcat` では拾えない可能性が高い（未検証）。
  /// そのため `debugPrint`（Flutter の通常の標準出力経由。Android では logcat
  /// にも出る）を併用し、どちらの経路で確認しても追えるようにする。
  void _log(String message) {
    developer.log(message, name: 'terra_town_location.map_view');
    debugPrint('[terra_town_location.map_view] $message');
  }

  Future<void> _addRegionPackLayers() async {
    final controller = _controller;
    if (controller == null) {
      _log('失敗: onStyleLoadedCallback 発火時点で MapLibreMapController が未取得');
      return;
    }

    try {
      final sourceUrl = mbtilesSourceUrl(widget.mbtilesFilePath);
      await controller.addSource(
        widget.sourceId,
        VectorSourceProperties(
          url: sourceUrl,
          minzoom: widget.sourceMinzoom,
          maxzoom: widget.sourceMaxzoom,
        ),
      );
      _log('地域パックのベクタソースを追加しました（sourceId=${widget.sourceId}, url=$sourceUrl）');

      for (final layer in widget.fillLayers) {
        await controller.addFillLayer(
          widget.sourceId,
          layer.id,
          FillLayerProperties(
            fillColor: layer.fillColorHex,
            fillOpacity: layer.fillOpacity,
          ),
          sourceLayer: layer.sourceLayer,
          minzoom: layer.minzoom,
          maxzoom: layer.maxzoom,
        );
      }
      for (final layer in widget.lineLayers) {
        await controller.addLineLayer(
          widget.sourceId,
          layer.id,
          LineLayerProperties(
            lineColor: layer.lineColorHex,
            lineOpacity: layer.lineOpacity,
            lineWidth: layer.lineWidth,
          ),
          sourceLayer: layer.sourceLayer,
          minzoom: layer.minzoom,
          maxzoom: layer.maxzoom,
        );
      }
      _log(
        '地域パックのレイヤーを追加しました'
        '（fill=${widget.fillLayers.length}件・line=${widget.lineLayers.length}件）',
      );

      // 【T056（fog of war・plan.md §8 の採用方式）】ベースレイヤー追加の直後に、
      // 同じ controller を使って全ヘクスを1回だけ addGeoJsonSource で追加し、
      // fill レイヤの fill-opacity を feature-state（setFeatureState）で
      // トグルする方式を追加する。ベースレイヤーより後に追加することで、
      // 暗幕がベースの地図の上に重なる描画順を保証する。
      //
      // fogOfWarLayer・fogHexFeatureCollection のいずれかが null の場合は
      // 何もしない（Issue #99 時点の挙動を変えない。呼び出し側が fog を
      // まだ配線していない場合でも地図表示自体は成立させるため）。
      final fogLayer = widget.fogOfWarLayer;
      final fogHexes = widget.fogHexFeatureCollection;
      if (fogLayer != null && fogHexes != null) {
        try {
          final fogController = await FogOfWarController.install(
            controller,
            fogLayer,
            fogHexes,
            sourceId: widget.fogSourceId,
            layerId: widget.fogLayerId,
          );
          final hexCount = (fogHexes['features'] as List?)?.length ?? 0;
          _log('fog of war のソース/レイヤーを追加しました（ヘクス数=$hexCount）');
          widget.onFogLayerReady?.call(fogController);
        } catch (e, stackTrace) {
          // 【本Issueが解消しようとしているリスクそのもの】plan.md §8「未計測」＝
          // 実際の地域パック規模（13,106ヘクス）でのソース構築が実機で失敗した
          // 場合、ここで確実に捕捉してログに残す。地域パックの基盤レイヤーとは
          // 独立した try/catch にすることで、「地域パックは表示できたが fog だけ
          // 失敗した」ことを区別できるようにする。
          _log('失敗: fog of war のソース/レイヤー追加でエラー: $e');
          developer.log(
            'fog of war のソース/レイヤー追加に失敗しました',
            name: 'terra_town_location.map_view',
            error: e,
            stackTrace: stackTrace,
            level: 1000,
          );
          widget.onLayersFailed?.call(e, stackTrace);
        }
      }
    } catch (e, stackTrace) {
      // 【本Issueが解消しようとしているリスクそのもの】plan.md §8「未計測」＝
      // 実際の地域パック（高ズーム・Planetiler生成）での addSource/addLayer が
      // 実機で失敗した場合、ここで確実に捕捉してログに残す（fire-and-forget の
      // 非同期例外として握りつぶさない。onStyleLoadedCallback は VoidCallback の
      // ため、ここで catch しない限り例外は誰にも拾われない）。
      _log('失敗: 地域パックの source/layer 追加でエラー: $e');
      developer.log(
        '地域パックの source/layer 追加に失敗しました',
        name: 'terra_town_location.map_view',
        error: e,
        stackTrace: stackTrace,
        level: 1000,
      );
      widget.onLayersFailed?.call(e, stackTrace);
    }
  }
}

/// 背景色のみを持つ、外部通信を伴わないインラインの MapLibre スタイルJSON。
String _backgroundOnlyStyle(String backgroundColorHex) {
  final style = <String, dynamic>{
    'version': 8,
    'sources': <String, dynamic>{},
    'layers': [
      {
        'id': 'terra_town_background',
        'type': 'background',
        'paint': {'background-color': backgroundColorHex},
      },
    ],
  };
  return jsonEncode(style);
}
