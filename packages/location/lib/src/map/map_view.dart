import 'dart:convert';
import 'dart:developer' as developer;

import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

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
/// ローカル読込して表示する」ところまでを担う。fog of war（未開示ヘクスの暗幕・
/// plan.md §8・tasks.md T056）・現在地表示と地図追従（T058）は含まない。
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
/// 【後から fog レイヤを載せられる構造にしておくこと（Issue #99 の要件）】
/// `onStyleLoadedCallback`（[_addRegionPackLayers]）の中で
/// 「①地域パックの vector source を追加 → ② fill/line レイヤーを追加」の順に
/// 処理する。T056（fog of war・plan.md §8 の採用方式）は、この直後に同じ
/// [MapLibreMapController] を使って `addGeoJsonSource` + `setFeatureState` に
/// よるトグル用レイヤーを追加する形で拡張できる（[_addRegionPackLayers] 末尾の
/// コメント参照）。[MapLibreMapController] 自体は `app` には公開しない
/// （`terra_town_location` の役割は地図SDKを隠蔽すること。`app/pubspec.yaml` は
/// `maplibre_gl` に依存していない）。
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

  @override
  State<MapView> createState() => _MapViewState();
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
      onMapCreated: (controller) => _controller = controller,
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
      // 【T056（fog of war）の拡張ポイント】ここ（ベースレイヤー追加の直後）で
      // 同じ controller を使い、全ヘクスを1回だけ addGeoJsonSource で追加し、
      // fill レイヤの fill-opacity を feature-state（setFeatureState）で
      // トグルする方式を実装する（plan.md §8 の採用方式）。ベースレイヤーより後に
      // 追加することで、暗幕がベースの地図の上に重なる描画順を保証する。
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
