import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../../map/debug/disclosure_debug_panel.dart';
import '../../map/debug/fog_of_war_debug_panel.dart';
import '../../map/debug/location_tracking_debug_panel.dart';
import '../../map/disclosure/disclosure_coordinator.dart';
import '../../map/disclosure/disclosure_restore.dart';
import '../../map/fog_of_war_layer_factory.dart';
import '../../map/initial_camera.dart';
import '../../map/map_style_factory.dart';
import '../../map/region_pack_asset.dart';

/// マップ（ホーム）画面（tasks.md T057・T060・T069・Issue #100・#101・#102・#137）。
///
/// DESIGN.md「画面一覧と状態」のマップ（ホーム）行に対応する。
/// DESIGN.md が定義する4状態のうち本画面が扱うのは次の2つ + ローディングのみ:
///   - ローディング = 地域パック読込（DESIGN.md記載どおり。MBTiles・
///     `region_pack.sqlite` 両方のファイルパス解決を含む）
///   - エラー = パックの読込に失敗した状態（後述の理由により、DESIGN.md
///     記載の「GPS取得不可・権限拒否」を、本画面のスコープに合わせて
///     「地域パック読込エラー」に拡張したもの。これは DESIGN.md からの逸脱ではなく
///     「ローディング=地域パックの読込」が失敗した場合の自然な帰結として扱う）
///   - 通常 = 地図が表示された状態
/// 「空=未開示（霧のみ）」は、実機で最初に到達する状態そのもの（fog of war は
/// 本画面がすべてのビルドで実データを表示するため、初回起動時は全ヘクスが
/// 霧に覆われた状態になる）。
///
/// ## 2026-09-11（Issue #137）: 位置→開示判定→保存→霧の解除を composition root として配線
/// 以前は `kDebugMode` 配下でのみ合成データによる fog of war のデモを表示していたが
/// （T054 の開示判定ロジックが無かったため）、Issue #101（`DisclosureService`）・
/// #83/#96（`disclosed_hex`）が先に実装済みとなった今、実際に組み立てる責務が
/// ここに無かった。本 Issue で、**release ビルドを含む全ビルド**で実データ
/// （`region_pack.sqlite` の実ヘクス・約13,106件）による fog of war を表示し、
/// `NativePositionProvider` → `DisclosureService` → `disclosed_hex`（永続化）→
/// `FogOfWarController.revealHex` までを配線する（[_DisclosureAwareMapView] 参照）。
/// `kDebugMode` 限定なのは、代表・秘書セッションが実機確認するための補助パネル
/// （デバッグパネル群・「地図の中心のヘクスを開示」）のみである。
///
/// ## パックが無い場合の振る舞い（PR本文にも記載）
/// 生成物（`app/assets/pack/`配下）はコミットしない方針（Issue #85）のため、
/// `tools/pack-builder/bundle_region_pack.sh` 未実行の環境では
/// [PackAssetMissingException] が送出される。これをクラッシュさせず、
/// 上記のエラー状態としてユーザーに提示する。
///
/// ## テスト容易性のための差し替えフック・責務分担（Issue #137 で変更）
/// `packages/location` の [MapView] は MapLibre の実プラットフォームビュー
/// （`MapLibreMap`）に依存しており、widget テスト環境（`flutter test`）では
/// 動作しない（プラットフォームチャンネルが未接続のため）。そのため:
///   - [resolveMbtilesPath]・[resolveRegionPackPath] を差し替えることで、
///     パック未取得/取得済みの両状態を決定的に再現できる。**本ウィジェット自体は
///     ファイルパス文字列を解決するだけで、実際に地域パックDBを開く
///     （`RegionPackConnection.open`・sqlite3 の実ファイルI/O）ことはしない**
///     （widget テストでフェイクの文字列パスを渡せるようにするため。実際に開くのは
///     [_DisclosureAwareMapView] の責務）。
///   - [mapBuilder] を差し替えることで、成功状態の描画を実 [MapView] を経由せずに
///     検証できる（既定は実際に地図を組み立てる [MapScreen.defaultMapBuilder]）。
///   本ウィジェット自体の「地図が実際に描画される」ことの検証は widget テストの
///   対象にしない（`test/features/map/map_screen_test.dart` 冒頭コメント・
///   PR本文「実機確認は未実施」参照）。
class MapScreen extends StatefulWidget {
  const MapScreen({
    super.key,
    this.resolveMbtilesPath,
    this.resolveRegionPackPath,
    this.gameDatabase,
    this.mapBuilder = defaultMapBuilder,
  });

  /// 同梱 MBTiles アセットのキー（`app/pubspec.yaml` の `flutter.assets` で
  /// `assets/pack/` ディレクトリ単位で宣言済み）。
  static const mbtilesAssetKey = 'assets/pack/tiles.mbtiles';

  /// パック（同梱 MBTiles）のローカルファイルパスを解決する関数。
  /// null の場合は [defaultResolveMbtilesPath] を使う。
  final Future<String> Function()? resolveMbtilesPath;

  /// 地域パック（`region_pack.sqlite`。地形属性・fog of war 用ヘクス境界を含む）の
  /// ローカルファイルパスを解決する関数。null の場合は
  /// `region_pack_asset.dart` の `defaultResolveRegionPackPath` を使う。
  final Future<String> Function()? resolveRegionPackPath;

  /// ゲーム状態DB（開示済みヘクスの永続化・T060 に使用）。
  ///
  /// 省略時は本ウィジェットが自前で [GameDatabase.defaultConnection] を開く
  /// （その場合は本ウィジェットの破棄時に自前で閉じる）。`RootScaffold`
  /// （`main.dart`）は設定タブと共有する既存インスタンスをここに渡す。
  final GameDatabase? gameDatabase;

  /// 解決済みパス一式から実際の地図ウィジェットを組み立てる関数。
  final Widget Function(BuildContext context, MapScreenPaths paths) mapBuilder;

  /// 実アセットから解決する既定実装。
  static Future<String> defaultResolveMbtilesPath() =>
      resolveBundledMbtilesPath(assetKey: mbtilesAssetKey);

  /// 実際に開示配線込みの地図を組み立てる既定実装。
  static Widget defaultMapBuilder(BuildContext context, MapScreenPaths paths) {
    return _DisclosureAwareMapView(paths: paths);
  }

  @override
  State<MapScreen> createState() => _MapScreenState();
}

/// [MapScreen] が非同期に解決する、地図表示に必要なファイルパス一式（Issue #137）。
///
/// MBTiles（表示専用のベクタタイル）と地域パック（`region_pack.sqlite`。地形属性・
/// fog of war 用ヘクス境界・`core` の `RegionPack` 実装のソース）は別ファイルだが、
/// どちらも `tools/pack-builder/bundle_region_pack.sh` が同時に生成するため、
/// 1つの非同期処理・1つのローディング/エラー状態にまとめる。
///
/// **本クラスはファイルパス文字列を保持するだけで、実際に地域パックDBを開く処理
/// （`RegionPackConnection.open`）はここでは行わない**（`MapScreen` クラスdoc
/// 「テスト容易性のための差し替えフック」参照）。
class MapScreenPaths {
  const MapScreenPaths({
    required this.mbtilesFilePath,
    required this.regionPackFilePath,
    required this.gameDatabase,
  });

  final String mbtilesFilePath;
  final String regionPackFilePath;
  final GameDatabase gameDatabase;
}

class _MapScreenState extends State<MapScreen> {
  late final GameDatabase _gameDatabase =
      widget.gameDatabase ?? GameDatabase.defaultConnection();
  late final Future<MapScreenPaths> _pathsFuture = _resolvePaths();

  Future<MapScreenPaths> _resolvePaths() async {
    final mbtilesPath =
        await (widget.resolveMbtilesPath ?? MapScreen.defaultResolveMbtilesPath)();
    final regionPackPath =
        await (widget.resolveRegionPackPath ?? defaultResolveRegionPackPath)();
    return MapScreenPaths(
      mbtilesFilePath: mbtilesPath,
      regionPackFilePath: regionPackPath,
      gameDatabase: _gameDatabase,
    );
  }

  @override
  void dispose() {
    if (widget.gameDatabase == null) {
      unawaited(_gameDatabase.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MapScreenPaths>(
      future: _pathsFuture,
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
    if (error is RegionPackMissingHexGeometryException) {
      return '地域パックにヘクス境界がありません。\n'
          'tools/pack-builder/bundle_region_pack.sh を最新のコードで\n'
          '再実行してから、アプリを再起動してください。';
    }
    return 'しばらくしてからもう一度お試しください。';
  }
}

/// 実際に地図・fog of war・開示配線を組み立てるウィジェット（Issue #137）。
///
/// [MapScreenPaths] で解決済みのファイルパスから、地域パックDBへの接続
/// （[RegionPackConnection]）・fog of war 用の実ヘクス GeoJSON・`core` の
/// [RegionPack] 実装（[RegionPackRepository]）を**同期的に**組み立てる
/// （`RegionPackConnection.open`・`buildFogHexFeatureCollectionFromRegionPack`・
/// `RegionPackRepository.load` はいずれも同期 API であり、`MapView` 側で
/// 従来から行っていたのと同じ主スレッド上の一括処理である。`specs/001-mvp/plan.md`
/// §3.5 の「ソース構築2秒以内」の budget に含まれる想定の処理であり、本 Issue で
/// 新たに追加した非同期境界ではない）。
///
/// 【release ビルドでも fog of war を表示する】以前（Issue #99〜#100 時点）は
/// `kDebugMode` 配下でのみ合成データによる fog デモを表示していたが、
/// 実データを使うようになった本 Issue 以降は常に表示する。`kDebugMode` 配下に
/// 残るのは、実機確認のための補助パネル（位置記録・fog・開示の各デバッグパネル）
/// のみである。
class _DisclosureAwareMapView extends StatefulWidget {
  const _DisclosureAwareMapView({required this.paths});

  final MapScreenPaths paths;

  @override
  State<_DisclosureAwareMapView> createState() =>
      _DisclosureAwareMapViewState();
}

class _DisclosureAwareMapViewState extends State<_DisclosureAwareMapView> {
  FogOfWarController? _fogController;
  MapCameraReader? _cameraReader;
  String? _layersError;
  RestoreStats? _restoreStats;
  Object? _initError;

  RegionPackConnection? _regionPackConnection;
  Map<String, dynamic>? _fogHexFeatureCollection;
  DisclosedHexRepository? _disclosedHexRepository;
  DisclosedHexSet? _known;
  NativePositionProvider? _positionProvider;
  DisclosureCoordinator? _coordinator;

  @override
  void initState() {
    super.initState();
    try {
      final connection = RegionPackConnection.open(widget.paths.regionPackFilePath);
      _regionPackConnection = connection;
      _fogHexFeatureCollection = buildFogHexFeatureCollectionFromRegionPack(connection);
      final regionPack = RegionPackRepository.load(connection);

      final disclosedHexRepository = DisclosedHexRepository(widget.paths.gameDatabase);
      final known = DisclosedHexSet();
      final positionProvider = NativePositionProvider();
      _disclosedHexRepository = disclosedHexRepository;
      _known = known;
      _positionProvider = positionProvider;
      _coordinator = DisclosureCoordinator(
        service: DisclosureService(
          hexLocator: const RecordedHexLocator(),
          regionPack: regionPack,
          known: known,
          repository: disclosedHexRepository,
        ),
        positionUpdates: positionProvider.positionUpdates,
        // _fogController は onFogLayerReady が発火するまで null。
        // DisclosureCoordinator は「新規開示イベントが来た時点の _fogController」を
        // 都度読むだけなので、setStyle 相当でコントローラが差し替わっても
        // （disclosure_coordinator.dart クラスdoc参照）ここを変更する必要はない。
        reveal: (featureId) async {
          final controller = _fogController;
          if (controller == null) return;
          await controller.revealHex(featureId);
        },
      );
    } catch (e) {
      // 【本Issueが解消しようとしているリスクそのもの】地域パックDBが壊れている・
      // hex_terrain にヘクス境界が無い等の失敗を、ここで確実に捕捉して
      // エラー状態として提示する（クラッシュさせない。`_MapErrorView` を再利用する）。
      _initError = e;
    }
  }

  /// [MapView.onFogLayerReady] から呼ぶ（アプリ起動時の初回ソース構築後、
  /// および将来 `setStyle` 経由で再度発火した場合の両方をこの1経路でカバーする。
  /// `disclosure_restore.dart` クラスdoc参照）。
  Future<void> _onFogLayerReady(FogOfWarController controller) async {
    _fogController = controller;

    final repository = _disclosedHexRepository;
    final known = _known;
    final coordinator = _coordinator;
    if (repository == null || known == null || coordinator == null) return;

    final stats = await restoreDisclosedHexes(
      repository: repository,
      known: known,
      reveal: controller.revealHex,
    );
    if (!mounted) return;
    setState(() => _restoreStats = stats);

    // known への復元が完了した後に位置ストリームの購読を開始する（advisor
    // 指摘の順序保証。disclosure_coordinator.dart クラスdoc参照）。2回目以降の
    // 呼び出し（将来のsetStyle相当）では start() は何もしない。
    coordinator.start();
  }

  @override
  void dispose() {
    unawaited(_coordinator?.stop() ?? Future<void>.value());
    unawaited(_positionProvider?.close() ?? Future<void>.value());
    unawaited(_regionPackConnection?.close() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) {
      return _MapErrorView(error: initError);
    }

    final fogHexFeatureCollection = _fogHexFeatureCollection!;

    final mapView = MapView(
      mbtilesFilePath: widget.paths.mbtilesFilePath,
      initialCameraPosition: sayamakoInitialCameraPosition(),
      backgroundColorHex: buildMapBackgroundColorHex(),
      sourceMinzoom: regionPackSourceMinzoom,
      sourceMaxzoom: regionPackSourceMaxzoom,
      fillLayers: buildRegionPackFillLayers(),
      lineLayers: buildRegionPackLineLayers(),
      fogOfWarLayer: buildFogOfWarLayer(),
      fogHexFeatureCollection: fogHexFeatureCollection,
      onFogLayerReady: (controller) {
        unawaited(_onFogLayerReady(controller));
      },
      onLayersFailed: (error, stackTrace) {
        if (!mounted) return;
        setState(() => _layersError = '$error');
      },
      // カメラ中心の読み取りは「地図の中心のヘクスを開示」デバッグボタンにのみ
      // 必要（kDebugMode限定）。release ビルドでは購読しない。
      onMapControllerReady: kDebugMode
          ? (reader) {
              if (!mounted) return;
              setState(() => _cameraReader = reader);
            }
          : null,
    );

    if (!kDebugMode) return mapView;

    final fogController = _fogController;
    final layersError = _layersError;
    final cameraReader = _cameraReader;
    final restoreStats = _restoreStats;
    final coordinator = _coordinator!;
    final disclosedHexRepository = _disclosedHexRepository!;
    final known = _known!;

    return Stack(
      children: [
        mapView,
        // 画面上部: レイヤー追加エラー（あれば）＋ 位置記録デバッグパネル
        // （Issue #124・T049・T050）を縦に並べる。位置記録パネルは fog レイヤーの
        // 準備完了を待つ必要が無いため常に表示する。
        //
        // ⚠️ composition root の NativePositionProvider（_positionProvider）は
        // 本パネルに**共有してはならない**（advisor指摘・2026-09-11）。
        // positionUpdates は broadcast Stream で `onListen`（履歴の全件再生・
        // native_position_provider.dart クラスdoc「履歴の扱い」参照）は
        // 0→1件目の購読者にのみ発火し、broadcast Stream は過去のイベントを
        // 新しい購読者に再送しない。本パネルは fog レイヤーの準備を待たず
        // build() の初回で即座に購読を始めるため、共有すると本パネルが
        // 最初の購読者になってしまい、`onListen` の履歴再生が
        // 「復元後に購読開始」する DisclosureCoordinator（_onFogLayerReady 参照）
        // に届かなくなる（`_lastSeenId` が既に最新まで進んだ状態で
        // coordinator が購読することになり、購読前に記録された位置の開示判定が
        // 一切行われない）。そのため本パネルは自前の NativePositionProvider
        // インスタンスを持たせる（重複ポーリングは発生するが、デバッグ専用の
        // 読み取りのみのポーリングであり実害はない）。
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (layersError != null)
                SafeArea(
                  bottom: false,
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
              if (restoreStats != null)
                SafeArea(
                  bottom: false,
                  child: Card(
                    margin: const EdgeInsets.all(AppSpacing.sm),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Text(
                        '起動時の復元（Issue #102）: ${restoreStats.hexCount}件 / '
                        '${restoreStats.elapsedMs}ms',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ),
                ),
              const LocationTrackingDebugPanel(),
            ],
          ),
        ),
        if (fogController != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (cameraReader != null)
                  DisclosureDebugPanel(
                    coordinator: coordinator,
                    fogHexFeatureCollection: fogHexFeatureCollection,
                    cameraReader: cameraReader,
                  ),
                FogOfWarDebugPanel(
                  controller: fogController,
                  repository: disclosedHexRepository,
                  known: known,
                ),
              ],
            ),
          ),
      ],
    );
  }
}
