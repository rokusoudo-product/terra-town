import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../../map/current_location_follow_button.dart';
import '../../map/current_location_marker_factory.dart';
import '../../map/debug/disclosure_debug_panel.dart';
import '../../map/debug/fog_of_war_debug_panel.dart';
import '../../map/debug/location_tracking_debug_panel.dart';
import '../../map/debug/opening_point_debug_panel.dart';
import '../../map/debug/terrain_yield_debug_panel.dart';
import '../../map/disclosure/disclosure_restore.dart';
import '../../map/economy/opening_point_accrual_coordinator.dart';
import '../../map/economy/terrain_yield_accrual_coordinator.dart';
import '../../map/economy/terrain_yield_pipeline.dart';
import '../../map/fog_of_war_layer_factory.dart';
import '../../map/initial_camera.dart';
import '../../map/map_style_factory.dart';
import '../../map/region_pack_asset.dart';
import '../permissions/tracking_control_button.dart';
import 'widgets/walk_stats_hud.dart';

/// マップ（ホーム）画面（tasks.md T057・T058・T060・T066・T068・T069・
/// Issue #100・#101・#102・#137・#138・#141）。
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
/// ## 2026-09-11（Issue #138）: 地形産出（受動・時間ベース）を同じパイプラインに統合
/// 上記の配線を担っていた `DisclosureCoordinator` は、位置1件ごとに
/// 「地形産出の計上」→「開示判定・霧の解除」を直列に行う `TerrainYieldPipeline`
/// （`app/lib/map/economy/terrain_yield_pipeline.dart`）に置き換えた。**本番の
/// 位置ストリーム（`NativePositionProvider.recordedPositionUpdates`）を購読する
/// リスナーはこのパイプライン1つのみ**とし、`DisclosureCoordinator`
/// （テスト・単体クラスとしては残す）は composition root では使わない。
/// 詳細・判断の記録は `docs/terrain-yield.md` 参照。
///
/// ## 2026-09-12（Issue #141）: 現在地表示と地図追従（T058）
/// `TerrainYieldPipeline.currentPosition`（`stats` と同じ [ValueListenable]
/// 方式で公開する派生的な通知）を [MapView.currentLocation] にそのまま渡す。
/// **位置ストリーム（`NativePositionProvider.recordedPositionUpdates`）を
/// 新たに購読することはしない**（`terrain_yield_pipeline.dart` クラスdoc
/// 「なぜ stats に含めず別のValueNotifierにしたか」参照）。追従のオン/オフは
/// 本ウィジェットの `_isFollowing` が保持し、[CurrentLocationFollowButton] で
/// 切り替える。利用者が地図を動かして追従が解除された場合は
/// [MapView.onFollowDismissedByUser] 経由で `_isFollowing` を false に戻す。
///
/// ## 2026-09-12（Issue #143）: 開放ポイント（歩行距離換算）の入手（T063）
/// `TerrainYieldPipeline` に `OpeningPointAccrualCoordinator` を統合し、同じ
/// 直列パイプラインの中で開放ポイント（歩行距離換算・上限50P）を計上する
/// （新たな位置ストリームの購読は追加しない。詳細は
/// `docs/opening-points-impl.md`・`terrain_yield_pipeline.dart` クラスdoc参照）。
/// 自然回復（1P/日）は MVP では実装しない（`docs/opening_points.md` §2.1）。
///
/// ## 2026-09-12（Issue #142）: 位置記録の開始・停止と権限リクエスト（T059）
/// [TrackingControlButton]（`app/lib/features/permissions/`）を release ビルドを
/// 含む全ビルドに表示する。従来 `kDebugMode` 限定の [LocationTrackingDebugPanel]
/// にしか無かった起動/停止操作を、権限が無い場合の要求・拒否時の案内込みで製品UIに
/// 昇格したもの（デバッグパネル側はそのまま残す。Issue #142 提案内容1）。本ウィジェットは
/// 独自の `NativeLocationTrackingControl`/`PermissionHandlerLocationGateway` を持ち、
/// composition root の `_positionProvider`（位置**読み取り**用。`TerrainYieldPipeline` が
/// 唯一の購読者であるべき理由は上記2026-09-11の節を参照）とは別物であり、記録の
/// **起動/停止**という制御操作は複数箇所から呼んでも安全（Kotlin側は状態を持つのは
/// サービス自身であり、多重呼び出しは冪等）なため共有の必要が無い。
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
  TerrainHexCounter? _terrainHexCounter;
  InventoryRepository? _inventoryRepository;
  TerrainYieldPipeline? _pipeline;

  /// 地図追従（Issue #141・T058）のオン/オフ。既定はオフ（利用者がボタンを
  /// 押すまでカメラは動かない。地図を開いた直後に勝手にカメラが動く方が
  /// 驚きが大きいと判断した実装判断）。
  bool _isFollowing = false;

  /// 記録中かどうか（HUD 用・Issue #149）。[TrackingControlButton] へ渡し、
  /// 状態が変わるたびに書き込んでもらう（`tracking_control_button.dart`
  /// クラスdoc「なぜ必要か」参照）。位置ストリームとは別経路のため、
  /// 「2つ目のリスナー」を追加したことにはならない。
  final ValueNotifier<bool> _isRecording = ValueNotifier<bool>(false);

  /// デバッグパネル群（`kDebugMode` 限定）を表示するか。
  ///
  /// パネルが増えるたびに地図と製品UIのボタンが覆われ、実機確認が行えなくなる
  /// 問題が繰り返し起きたため、一括で隠せるようにした（2026-09-12）:
  ///   - Issue #137 の検証時: パネルが地図中心を覆い、霧が晴れる様子を目視できなかった
  ///   - Issue #138 の検証時: 位置記録パネルの「起動・停止」ボタンが覆われ、タップできなかった
  ///   - Issue #141 の検証時: 追従ボタンが位置記録パネルの下に隠れ、タップできなかった
  ///   - Issue #142 の検証時: 製品UIの「記録開始」ボタンが位置記録パネルの下に隠れ、
  ///     タップしても何も起きなかった（代表が権限の確認を試みた際に発生）
  /// 隠している間も本トグル自身と製品UI（追従ボタン・記録開始ボタン）は操作できる。
  ///
  /// **既定は非表示**（2026-09-12・Issue #142 の検証を受けて変更）。パネルを
  /// 既定で表示すると、デバッグビルドでは製品UIのボタンが覆われた状態が既定に
  /// なってしまい、「押しても何も起きない」という誤解を生む（実際に発生した）。
  /// デバッグビルドでもまず製品と同じ画面が出るようにし、内部状態を見たいときだけ
  /// 右上のトグルで開く。
  bool _debugPanelsVisible = false;

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

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: regionPack,
        known: known,
        repository: disclosedHexRepository,
      );
      // _fogController は onFogLayerReady が発火するまで null。
      // 呼び出し側は「新規開示イベントが来た時点の _fogController」を
      // 都度読むだけなので、setStyle 相当でコントローラが差し替わっても
      // （disclosure_coordinator.dart クラスdoc参照）ここを変更する必要はない。
      Future<void> reveal(int featureId) async {
        final controller = _fogController;
        if (controller == null) return;
        await controller.revealHex(featureId);
      }

      final terrainHexCounter = TerrainHexCounter();
      final inventoryRepository = InventoryRepository(widget.paths.gameDatabase);
      _terrainHexCounter = terrainHexCounter;
      _inventoryRepository = inventoryRepository;
      // 2026-09-11（Issue #138）: composition root は DisclosureCoordinator を
      // TerrainYieldPipeline に置き換えた。位置1件ごとに「地形産出の計上」→
      // 「開示判定・霧の解除」を直列に行う唯一のリスナーがこのパイプラインであり、
      // 本番の位置ストリーム（recordedPositionUpdates）を購読するのはこれだけに
      // 保つこと（`terrain_yield_pipeline.dart` クラスdoc参照）。
      // 2026-09-12（Issue #143）: 開放ポイント（歩行距離換算）の計上も同じ
      // パイプラインに統合する（新たな位置ストリームの購読は追加しない。
      // `terrain_yield_pipeline.dart` クラスdoc参照）。
      _pipeline = TerrainYieldPipeline(
        disclosureService: service,
        reveal: reveal,
        accrualCoordinator: TerrainYieldAccrualCoordinator(
          ledger: TerrainYieldLedger(widget.paths.gameDatabase),
        ),
        // rewardSettings を渡すことで、設定タブの歩数判定オプトアウト
        // （Issue #135・reward.step_check_disabled）が実際に反映される
        // （`OpeningPointAccrualCoordinator` クラスdoc「歩数判定オプトアウト設定との
        // 配線」参照。設定は次回起動時から反映される）。
        openingPointCoordinator: OpeningPointAccrualCoordinator(
          ledger: OpeningPointLedger(widget.paths.gameDatabase),
          rewardSettings: RewardSettingsRepository(widget.paths.gameDatabase),
        ),
        terrainHexCounter: terrainHexCounter,
        disclosedHexRepository: disclosedHexRepository,
        recordedPositionUpdates: positionProvider.recordedPositionUpdates,
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
    final pipeline = _pipeline;
    if (repository == null || known == null || pipeline == null) return;

    final stats = await restoreDisclosedHexes(
      repository: repository,
      known: known,
      reveal: controller.revealHex,
    );
    if (!mounted) return;
    setState(() => _restoreStats = stats);

    // known への復元が完了した後に位置ストリームの購読を開始する（advisor
    // 指摘の順序保証。`terrain_yield_pipeline.dart` クラスdoc参照）。2回目以降の
    // 呼び出し（将来のsetStyle相当）では start() は何もしない。
    await pipeline.start();
  }

  /// [CurrentLocationFollowButton] から呼ぶ。
  void _toggleFollow() {
    setState(() => _isFollowing = !_isFollowing);
  }

  /// [MapView.onFollowDismissedByUser] から呼ぶ（追従中に利用者が地図を
  /// 動かした場合。Issue #141 受け入れ基準「利用者が地図を動かすと追従が
  /// 解除される」）。
  void _onFollowDismissedByUser() {
    if (!mounted) return;
    setState(() => _isFollowing = false);
  }

  @override
  void dispose() {
    unawaited(_pipeline?.stop() ?? Future<void>.value());
    unawaited(_positionProvider?.close() ?? Future<void>.value());
    unawaited(_regionPackConnection?.close() ?? Future<void>.value());
    _isRecording.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final initError = _initError;
    if (initError != null) {
      return _MapErrorView(error: initError);
    }

    final fogHexFeatureCollection = _fogHexFeatureCollection!;
    final pipeline = _pipeline!;

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
      // 2026-09-12（Issue #141・T058）: 現在地表示と地図追従。
      // pipeline.currentPosition は TerrainYieldPipeline が唯一購読している
      // 位置ストリームから派生した ValueListenable であり、ここで新たに
      // NativePositionProvider を購読するわけではない（クラスdoc参照）。
      currentLocation: pipeline.currentPosition,
      currentLocationMarkerStyle: buildCurrentLocationMarkerStyle(),
      followCurrentLocation: _isFollowing,
      onFollowDismissedByUser: _onFollowDismissedByUser,
    );

    // 追従トグルボタン（release ビルドでも常に表示する製品UI）。
    // kDebugMode 配下ではデバッグパネル群が画面下半分（高さ height/2）を
    // 占有しうるため、それより上に置いて既存の操作ボタン（デバッグパネルの
    // 「起動・停止・状態確認」ボタン等）と重ならないようにする
    // （2026-09-12 に下部デバッグパネルを画面高の1/2までに制限した際と同じ
    // 「パネルが操作ボタンを覆わないこと」という方針を、新設するボタン側にも
    // 適用した）。release ビルドでは通常の画面右下に置く。
    final followButton = Positioned(
      right: AppSpacing.md,
      bottom: kDebugMode && _debugPanelsVisible
          ? MediaQuery.sizeOf(context).height / 2 + AppSpacing.md
          : AppSpacing.md,
      child: SafeArea(
        child: CurrentLocationFollowButton(
          isFollowing: _isFollowing,
          onPressed: _toggleFollow,
        ),
      ),
    );

    // 位置記録の起動/停止（release ビルドでも常に表示する製品UI・Issue #142・T059）。
    //
    // 【配置は画面下中央】左右の角には既存のUIが既に置かれている:
    //   - 右下: [followButton]（Issue #141）に加え、MapLibre の attribution ボタン
    //     （`MapLibreMap.attributionButtonPosition` 既定値 `bottomRight`。
    //     `map_view.dart` は本パラメータを未指定のためこの既定のまま。OSM/ODbL の
    //     帰属表示としてタップ可能である必要があるため覆えない）。
    //   - 左下: MapLibre のロゴ（`logoViewPosition` 未指定時のネイティブ既定
    //     `Gravity.BOTTOM|Gravity.START`。`MapLibreMapController.java` 参照）。
    // 左右どちらの角に置いても、追従ボタンで直した「操作ボタンが別のUIに覆われて
    // タップできない」不具合（#137・#138・#141）と同じ構造の問題を新たに作ってしまう
    // ため、本ボタンは両者と重ならない画面下**中央**に置く。
    // デバッグパネル群が画面下半分を占有しうる点への対処（上記 followButton と同じ理由）
    // も同じ計算式で揃える。
    final trackingControlButton = Positioned(
      left: 0,
      right: 0,
      bottom: kDebugMode && _debugPanelsVisible
          ? MediaQuery.sizeOf(context).height / 2 + AppSpacing.md
          : AppSpacing.md,
      child: SafeArea(
        child: Center(
          child: TrackingControlButton(recordingNotifier: _isRecording),
        ),
      ),
    );

    // 歩行距離・歩数・開放ポイントの HUD（release ビルドでも常に表示する製品UI・
    // Issue #149・T062）。画面**上部**に置き、下中央の [trackingControlButton]・
    // 右下の [followButton] とは重ならない（`walk_stats_hud.dart` クラスdoc
    // 「配置」参照）。`kDebugMode` 限定のデバッグパネル一括切替ボタン（右上・小さな
    // FAB）とは、右側にその分の余白を確保することで重ならないようにする。
    final walkStatsHud = Positioned(
      left: 0,
      top: 0,
      right: kDebugMode ? AppSpacing.xxl + AppSpacing.sm : 0,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topLeft,
          child: WalkStatsHud(
            openingPointStats: pipeline.openingPointStats,
            isRecording: _isRecording,
          ),
        ),
      ),
    );

    if (!kDebugMode) {
      return Stack(children: [mapView, followButton, trackingControlButton, walkStatsHud]);
    }

    final fogController = _fogController;
    final layersError = _layersError;
    final cameraReader = _cameraReader;
    final restoreStats = _restoreStats;
    final disclosedHexRepository = _disclosedHexRepository!;
    final known = _known!;
    final terrainHexCounter = _terrainHexCounter!;
    final inventoryRepository = _inventoryRepository!;

    return Stack(
      children: [
        mapView,
        followButton,
        trackingControlButton,
        // walkStatsHud は kDebugMode 配下の画面上部デバッグパネル列（下記
        // `_debugPanelsVisible` 配下の Positioned）より前（背面）に置く。デバッグ
        // パネルを開いている間は詳細診断（`OpeningPointDebugPanel` 等）で同等以上の
        // 情報が見えるため、意図的にそちらを手前にしている（両者を重ねて表示する
        // 精緻な配置調整はスコープ外・Issue #149 本文）。デバッグパネルを閉じた
        // 既定状態（release ビルドと同じ見た目）では walkStatsHud がそのまま見える。
        walkStatsHud,
        // 画面上部: レイヤー追加エラー（あれば）＋ 位置記録デバッグパネル
        // （Issue #124・T049・T050）を縦に並べる。位置記録パネルは fog レイヤーの
        // 準備完了を待つ必要が無いため常に表示する。
        //
        // ⚠️ composition root の NativePositionProvider（_positionProvider）は
        // 本パネルに**共有してはならない**（advisor指摘・2026-09-11。2026-09-11
        // Issue #138 で購読側が DisclosureCoordinator → TerrainYieldPipeline に
        // 置き換わった後もこの理由は変わらない）。
        // recordedPositionUpdates/positionUpdates は broadcast Stream で
        // `onListen`（履歴の全件再生・native_position_provider.dart クラスdoc
        // 「履歴の扱い」参照）は 0→1件目の購読者にのみ発火し、broadcast Stream は
        // 過去のイベントを新しい購読者に再送しない。本パネルは fog レイヤーの
        // 準備を待たず build() の初回で即座に購読を始めるため、共有すると
        // 本パネルが最初の購読者になってしまい、`onListen` の履歴再生が
        // 「復元後に購読開始」する TerrainYieldPipeline（_onFogLayerReady 参照）に
        // 届かなくなる（`_lastSeenId` が既に最新まで進んだ状態でパイプラインが
        // 購読することになり、購読前に記録された位置の産出計上・開示判定が
        // 一切行われない）。そのため本パネルは自前の NativePositionProvider
        // インスタンスを持たせる（重複ポーリングは発生するが、デバッグ専用の
        // 読み取りのみのポーリングであり実害はない。地形産出の観測は
        // 本パネルではなく `TerrainYieldDebugPanel`〔パイプライン自身が公開する
        // 派生ストリーム `stats` を読むだけで、位置ストリームを直接購読しない〕
        // が担う）。
        if (_debugPanelsVisible)
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
        if (fogController != null && _debugPanelsVisible)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            // 画面下部のデバッグパネル群は、パネルが増えるほど上へ伸びて画面上部の
            // 位置記録デバッグパネル（`LocationTrackingDebugPanel`）の「起動・停止・
            // 状態確認」ボタンを覆ってしまう（2026-09-12 実機で確認。Issue #138 の
            // `TerrainYieldDebugPanel` を足したことで、ボタンがタップできなくなった）。
            // 高さを画面の半分までに制限し、収まらない分はスクロールで読めるようにする。
            // `reverse: true` で初期表示は最下部（最後に追加したパネル）になる。
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height / 2,
              ),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cameraReader != null)
                      DisclosureDebugPanel(
                        recordManualPosition: pipeline.recordManualPosition,
                        fogHexFeatureCollection: fogHexFeatureCollection,
                        cameraReader: cameraReader,
                      ),
                    FogOfWarDebugPanel(
                      controller: fogController,
                      repository: disclosedHexRepository,
                      known: known,
                    ),
                    TerrainYieldDebugPanel(
                      stats: pipeline.stats,
                      terrainHexCounter: terrainHexCounter,
                      inventoryRepository: inventoryRepository,
                    ),
                    OpeningPointDebugPanel(
                      stats: pipeline.openingPointStats,
                    ),
                  ],
                ),
              ),
            ),
          ),
        // デバッグパネルの一括表示/非表示トグル（`kDebugMode` 限定）。
        // パネル群より後ろ（前面）に置き、パネルを表示している間も押せるようにする。
        Positioned(
          right: AppSpacing.sm,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Tooltip(
              message: _debugPanelsVisible ? 'デバッグパネルを隠す' : 'デバッグパネルを表示する',
              child: FloatingActionButton.small(
                heroTag: 'debug_panels_toggle',
                onPressed: () =>
                    setState(() => _debugPanelsVisible = !_debugPanelsVisible),
                child: Icon(
                  _debugPanelsVisible
                      ? Icons.visibility_off_outlined
                      : Icons.bug_report_outlined,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
