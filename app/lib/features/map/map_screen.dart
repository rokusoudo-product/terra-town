import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../../map/initial_camera.dart';
import '../../map/map_style_factory.dart';

/// マップ（ホーム）画面（tasks.md T057）。
///
/// DESIGN.md「画面一覧と状態」のマップ（ホーム）行に対応する。本 Issue（#99）の
/// スコープは「実地図（同梱 MBTiles）を表示する」ところまでで、fog of war（T056）・
/// 現在地表示と地図追従（T058）・権限リクエスト（T059）は含まないため、
/// DESIGN.md が定義する4状態のうち本画面が扱うのは次の2つ + ローディングのみ:
///   - ローディング = 地域パック読込（DESIGN.md記載どおり）
///   - エラー = 地域パックの読込に失敗した状態（後述の理由により、DESIGN.md
///     記載の「GPS取得不可・権限拒否」を、本Issueのスコープに合わせて
///     「地域パック読込エラー」に拡張したもの。これは DESIGN.md からの逸脱ではなく
///     「ローディング=地域パックの読込」が失敗した場合の自然な帰結として扱う）
///   - 通常 = 地図が表示された状態
/// 「空=未開示（霧のみ）」は fog of war 未実装のため本Issueでは到達しない。
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
  static Widget defaultMapBuilder(BuildContext context, String path) {
    return MapView(
      mbtilesFilePath: path,
      initialCameraPosition: sayamakoInitialCameraPosition(),
      backgroundColorHex: buildMapBackgroundColorHex(),
      sourceMinzoom: regionPackSourceMinzoom,
      sourceMaxzoom: regionPackSourceMaxzoom,
      fillLayers: buildRegionPackFillLayers(),
      lineLayers: buildRegionPackLineLayers(),
    );
  }

  @override
  State<MapScreen> createState() => _MapScreenState();
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
