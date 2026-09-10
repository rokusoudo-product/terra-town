import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../../map/debug/fog_debug_hex_grid.dart';
import '../../map/debug/fog_of_war_debug_panel.dart';
import '../../map/fog_of_war_layer_factory.dart';
import '../../map/initial_camera.dart';
import '../../map/map_style_factory.dart';

/// マップ（ホーム）画面（tasks.md T057・fog of war は T056・Issue #100）。
///
/// DESIGN.md「画面一覧と状態」のマップ（ホーム）行に対応する。
/// DESIGN.md が定義する4状態のうち本画面が扱うのは次の2つ + ローディングのみ:
///   - ローディング = 地域パック読込（DESIGN.md記載どおり）
///   - エラー = 地域パックの読込に失敗した状態（後述の理由により、DESIGN.md
///     記載の「GPS取得不可・権限拒否」を、本Issueのスコープに合わせて
///     「地域パック読込エラー」に拡張したもの。これは DESIGN.md からの逸脱ではなく
///     「ローディング=地域パックの読込」が失敗した場合の自然な帰結として扱う）
///   - 通常 = 地図が表示された状態
/// 「空=未開示（霧のみ）」は、開示判定ロジック（T054・Issue #101）が
/// まだ無いため、製品として到達することは無い。ただし fog of war の描画・
/// トグル自体（T056）は実装済みであり、`kDebugMode` 配下のデバッグパネル
/// （[FogOfWarDebugPanel]）で代表が実機確認できる（下記コメント参照）。
///
/// 【パックが無い場合の振る舞い（PR本文にも記載）】生成物（`app/assets/pack/`配下）
/// はコミットしない方針（Issue #85）のため、`tools/pack-builder/bundle_region_pack.sh`
/// 未実行の環境では [PackAssetMissingException] が送出される。これをクラッシュさせず、
/// 上記のエラー状態としてユーザーに提示する（DESIGN.md「破壊的操作は確認/Undo必須」
/// のような操作ではないため確認ステップは不要。単純にエラー内容を提示する）。
///
/// 【テスト容易性のための差し替えフック】`packages/location` の [MapView] は
/// MapLibre の実プラットフォームビュー（`MapLibreMap`）に依存しており、
/// widget テスト環境（`flutter test`）では動作しない
/// （プラットフォームチャンネルが未接続のため）。そのため:
///   - [resolveMbtilesPath] を差し替えることで、パック未取得/取得済みの両状態を
///     決定的に再現できる（既定は実アセットから解決する
///     [MapScreen.defaultResolveMbtilesPath]）。
///   - [mapBuilder] を差し替えることで、成功状態の描画を実 [MapView] を経由せずに
///     検証できる（既定は実際に地図を組み立てる [MapScreen.defaultMapBuilder]）。
///   本ウィジェット自体の「地図が実際に描画される」ことの検証は widget テストの
///   対象にしない（`test/features/map/map_screen_test.dart` 冒頭コメント・
///   PR本文「代表が実機で確認する手順」を参照。実機確認は代表が行う）。
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.resolveMbtilesPath,
    this.mapBuilder = defaultMapBuilder,
  });

  /// 同梱 MBTiles アセットのキー（`app/pubspec.yaml` の `flutter.assets` で
  /// `assets/pack/` ディレクトリ単位で宣言済み）。
  static const mbtilesAssetKey = 'assets/pack/tiles.mbtiles';

  /// パック（同梱 MBTiles）のローカルファイルパスを解決する関数。
  /// null の場合は [defaultResolveMbtilesPath] を使う。
  final Future<String> Function()? resolveMbtilesPath;

  /// 解決済みパスから実際の地図ウィジェットを組み立てる関数。
  final Widget Function(BuildContext context, String mbtilesFilePath)
  mapBuilder;

  /// 実アセットから解決する既定実装。
  static Future<String> defaultResolveMbtilesPath() =>
      resolveBundledMbtilesPath(assetKey: mbtilesAssetKey);

  /// 実際に [MapView] を組み立てる既定実装。
  ///
  /// 【fog of war のデバッグ表示は kDebugMode 配下のみ】fog of war 自体
  /// （T056）は製品コード（`packages/location`）として実装済みだが、
  /// 「どのヘクスを開示するか」を決める判定ロジック（T054・Issue #101）は
  /// まだ無いため、ここで渡せる開示対象は無い。代表が実機で
  /// 「霧の描画」「開示トグル」「本番相当ヘクス数でのソース構築コスト」を
  /// 確認できるよう、`kDebugMode`（release ビルドでは false）のときだけ
  /// [_DebugAwareMapView] が合成データ（`fog_debug_hex_grid.dart`）を使った
  /// デモを重ねる。release ビルドでは本メソッドは Issue #99 時点と同一の
  /// 挙動（fog 関連の引数は全て null）になる。
  static Widget defaultMapBuilder(BuildContext context, String path) {
    return _DebugAwareMapView(
      mbtilesFilePath: path,
      cameraPosition: sayamakoInitialCameraPosition(),
    );
  }

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// [MapScreen.defaultMapBuilder] が実際に返すウィジェット。
///
/// `kDebugMode` の場合のみ、[MapView] に fog of war のデバッグ用パラメータ
/// （合成ヘクス・DESIGN.md 由来の色）を渡し、地図の上に
/// [FogOfWarDebugPanel]（代表が実機確認するためのデバッグ専用UI）を重ねる。
/// [MapView.onFogLayerReady] が発火するまでパネルは表示しない（fog レイヤー
/// 追加はスタイル読込後の非同期処理のため）。
///
/// release ビルド（`kDebugMode == false`）では fog 関連のパラメータを
/// 一切渡さない、Issue #99 時点と同一の [MapView] を返す（製品UIを汚さない）。
class _DebugAwareMapView extends StatefulWidget {
  const _DebugAwareMapView({
    required this.mbtilesFilePath,
    required this.cameraPosition,
  });

  final String mbtilesFilePath;
  final MapCameraPosition cameraPosition;

  @override
  State<_DebugAwareMapView> createState() => _DebugAwareMapViewState();
}

class _DebugAwareMapViewState extends State<_DebugAwareMapView> {
  FogOfWarController? _fogController;

  /// レイヤー追加（地域パック本体・fog of war のいずれか）が失敗した場合の
  /// エラー内容。デバッグパネルが出ない＝失敗なのか単に読込中なのかが実機で
  /// 区別できないと確認手順が成立しないため、`kDebugMode` 配下で表示する
  /// （[MapView.onLayersFailed] 参照）。
  String? _layersError;

  @override
  Widget build(BuildContext context) {
    final mapView = MapView(
      mbtilesFilePath: widget.mbtilesFilePath,
      initialCameraPosition: widget.cameraPosition,
      backgroundColorHex: buildMapBackgroundColorHex(),
      sourceMinzoom: regionPackSourceMinzoom,
      sourceMaxzoom: regionPackSourceMaxzoom,
      fillLayers: buildRegionPackFillLayers(),
      lineLayers: buildRegionPackLineLayers(),
      fogOfWarLayer: kDebugMode ? buildFogOfWarLayer() : null,
      fogHexFeatureCollection: kDebugMode
          ? buildSyntheticFogHexFeatureCollection(
              centerLat: widget.cameraPosition.latitude,
              centerLon: widget.cameraPosition.longitude,
              count: FogOfWarDebugPanel.demoHexCount,
            )
          : null,
      onFogLayerReady: kDebugMode
          ? (controller) {
              if (!mounted) return;
              setState(() => _fogController = controller);
            }
          : null,
      onLayersFailed: kDebugMode
          ? (error, stackTrace) {
              if (!mounted) return;
              setState(() => _layersError = '$error');
            }
          : null,
    );

    if (!kDebugMode) return mapView;

    final fogController = _fogController;
    final layersError = _layersError;
    return Stack(
      children: [
        mapView,
        if (layersError != null)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Card(
                margin: const EdgeInsets.all(AppSpacing.sm),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Text(
                    'レイヤー追加に失敗しました（デバッグビルドのみ表示）: $layersError',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),
          )
        else if (fogController != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FogOfWarDebugPanel(controller: fogController),
          ),
      ],
    );
  }
}

class _MapScreenState extends State<MapScreen> {
  late final Future<String> _pathFuture =
      (widget.resolveMbtilesPath ?? MapScreen.defaultResolveMbtilesPath)();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _pathFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _MapLoadingView();
        }
        if (snapshot.hasError) {
          return _MapErrorView(error: snapshot.error!);
        }
        return widget.mapBuilder(context, snapshot.data!);
      },
    );
  }
}

class _MapLoadingView extends StatelessWidget {
  const _MapLoadingView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text('地図データを読み込み中…', style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _MapErrorView extends StatelessWidget {
  const _MapErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.map_outlined,
              size: AppSpacing.xxl,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('地図を表示できませんでした', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _messageFor(error),
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    if (error is PackAssetMissingException) {
      return '地域パックが未取得です。\n'
          'tools/pack-builder/bundle_region_pack.sh を実行してから、\n'
          'アプリを再起動してください。';
    }
    return 'しばらくしてからもう一度お試しください。';
  }
}
