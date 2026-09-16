import 'dart:async';

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/color_tokens.dart';
import '../../design/spacing.dart';
import '../../map/buildable_highlight_layer_factory.dart';
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
import '../../map/hex_feature_lookup.dart';
import '../../map/initial_camera.dart';
import '../../map/landmark_layer_factory.dart';
import '../../map/map_style_factory.dart';
import '../../map/region_pack_asset.dart';
import '../../map/terrain_tint_layer_factory.dart';
import '../build/build_screen.dart' show buildingSpecs;
import '../build/build_selection_controller.dart';
import '../permissions/tracking_control_button.dart';
import 'widgets/build_confirm_sheet.dart';
import 'widgets/hex_opening_sheet.dart';
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
/// ## 2026-09-14（Issue #176）: 開示済みヘクスの地形タイプ別色分け
/// `terrain_tint_layer_factory.dart`（`buildTerrainTintLayer`）が DESIGN.md の
/// トークン・Issue #175 の承認文面から組み立てた [TerrainTintLayer] を
/// `MapView.terrainTintLayer` へそのまま渡す。新規の位置ストリーム購読・
/// 状態管理は追加しない（fog と同じ GeoJSON ソースの feature-state を
/// 共有するため。`packages/location` の `TerrainTintController` クラスdoc参照）。
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
    this.buildSelection,
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

  /// 建設タブ横断の「今選んでいる建物」状態（Issue #192・T089）。
  ///
  /// `RootScaffold`（`main.dart`）が建設タブ（`BuildScreen`）と本ウィジェットの
  /// 両方に同じインスタンスを渡す（`build_selection_controller.dart` クラスdoc
  /// 「タブ切り替えをまたいで状態を持ち回す理由」参照）。null（省略時。既存の
  /// widget テストを含む）の場合は建設の選択機能自体が無効になり、従来どおり
  /// 霧のヘクスのタップは常に開放ポイントのシートを開く。
  final BuildSelectionController? buildSelection;

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
    this.buildSelection,
  });

  final String mbtilesFilePath;
  final String regionPackFilePath;
  final GameDatabase gameDatabase;

  /// [MapScreen.buildSelection] をそのまま橋渡しする（Issue #192・T089）。
  final BuildSelectionController? buildSelection;
}

class _MapScreenState extends State<MapScreen> {
  late final GameDatabase _gameDatabase =
      widget.gameDatabase ?? GameDatabase.defaultConnection();
  late final Future<MapScreenPaths> _pathsFuture = _resolvePaths();

  Future<MapScreenPaths> _resolvePaths() async {
    final mbtilesPath =
        await (widget.resolveMbtilesPath ??
            MapScreen.defaultResolveMbtilesPath)();
    final regionPackPath =
        await (widget.resolveRegionPackPath ?? defaultResolveRegionPackPath)();
    return MapScreenPaths(
      mbtilesFilePath: mbtilesPath,
      regionPackFilePath: regionPackPath,
      gameDatabase: _gameDatabase,
      buildSelection: widget.buildSelection,
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

  /// 名所ピンレイヤー（Issue #160・T071）。`_regionPack`・`_collectionRepository`
  /// は開示/収集の復元（[_onLandmarkLayerReady]）・新規開示時の反映
  /// （`revealLandmarks`。initState内のローカル関数）の両方で必要なため、
  /// initState のローカル変数ではなくフィールドとして保持する。
  RegionPack? _regionPack;
  CollectionRepository? _collectionRepository;
  LandmarkLayerController? _landmarkController;
  Future<LandmarkLayerAssets>? _landmarkAssets;

  /// タップされた fog 地物の `feature_id` → `core` の [HexId] への逆引き表
  /// （Issue #151・T064）。`hex_feature_lookup.dart` 参照。
  Map<int, HexId>? _hexIdByFeatureId;
  DisclosedHexRepository? _disclosedHexRepository;
  DisclosedHexSet? _known;
  NativePositionProvider? _positionProvider;
  TerrainHexCounter? _terrainHexCounter;
  InventoryRepository? _inventoryRepository;
  TerrainYieldPipeline? _pipeline;

  /// 建設（Issue #192・T089）。[_buildableHexEvaluator] は建設タブで選んだ建物
  /// についての「建てられるマス」判定（ハイライト用の全件評価・タップ時の単体
  /// 再評価）を、[_buildingConstructionService] は実際の建築（資材消費＋
  /// `building` 追加の1トランザクション）を担う。`BuildingRepository` 自体は
  /// 両者のコンストラクタに渡すためだけに `initState` のローカル変数として
  /// 組み立て、フィールドとしては保持しない（読み出しは常に上記2クラス経由）。
  BuildableHexEvaluator? _buildableHexEvaluator;
  BuildingConstructionService? _buildingConstructionService;
  BuildableHighlightController? _buildableHighlightController;

  /// `feature_id`（fog 地物のid）→ `core` の [HexId] の逆引き表
  /// （[_hexIdByFeatureId] の逆写像）。建てられるマスのハイライト
  /// （[BuildableHighlightController.setHighlighted]）に featureId が必要なため、
  /// 起動時に一度だけ組み立てる（`hex_feature_lookup.dart` と同じ「都度の
  /// 走査を避ける」考え方）。
  Map<HexId, int>? _featureIdByHexId;

  /// 建設タブで建物を選んだが、建てられるマスが1つも無い場合のメッセージ
  /// （DESIGN.md「画面一覧と状態」建設行「空=建設可能地なし」）。null は
  /// 該当なし（＝建てられるマスがある、または建設モードでない）を意味する。
  String? _buildEmptyMessage;

  bool _computingBuildHighlight = false;

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
      final connection = RegionPackConnection.open(
        widget.paths.regionPackFilePath,
      );
      _regionPackConnection = connection;
      _fogHexFeatureCollection = buildFogHexFeatureCollectionFromRegionPack(
        connection,
      );
      final regionPack = RegionPackRepository.load(connection);
      _regionPack = regionPack;
      // タップされた fog 地物の featureId → HexId の逆引き表（Issue #151・T064）。
      // 起動時に一度だけ組み立て、地域パックへの追加のDBアクセスなしにタップの
      // たびの変換を完結させる（hex_feature_lookup.dart クラスdoc参照）。
      _hexIdByFeatureId = buildHexIdByFeatureId(_fogHexFeatureCollection!);
      // 建てられるマスのハイライト（Issue #192・T089）が featureId で
      // setFeatureState するための逆引き表。上記の逆写像として一度だけ作る。
      _featureIdByHexId = {
        for (final entry in _hexIdByFeatureId!.entries) entry.value: entry.key,
      };

      final disclosedHexRepository = DisclosedHexRepository(
        widget.paths.gameDatabase,
      );
      // 徒歩経路（LandmarkAwareDisclosedHexRepository）・ポイント開放経路
      // （HexOpeningSpendService）の両方が同じインスタンスを共有する
      // （二重管理しない。`HexOpeningSpendService` クラスdocと同じ方針）。
      // 図鑑画面（Issue #12・T075）等の将来の読み出し口はこのクラス自体
      // （`CollectionRepository`）が担う想定で、本ウィジェットの状態としては
      // 保持しない（Issue #159「読み出し口を用意する」はクラスの存在で満たす）。
      final collectionRepository = CollectionRepository(
        widget.paths.gameDatabase,
      );
      _collectionRepository = collectionRepository;

      // 名所ピンレイヤー（Issue #160・T071）。GeoJSON（同期）はここで組み立て、
      // ラスタ画像（`dart:ui` のラスタライズを伴い非同期。`landmark_layer_factory.dart`
      // クラスdoc参照）は Future のまま MapView に渡す
      // （`MapView.landmarkAssets` クラスdoc「`Future` で受け取る理由」参照）。
      final landmarkFeatureCollection = buildLandmarkFeatureCollection(
        regionPack.pointsOfInterest,
      );
      _landmarkAssets = buildLandmarkPinImages(regionPack.pointsOfInterest)
          .then(
            (images) => LandmarkLayerAssets(
              images: images,
              featureCollection: landmarkFeatureCollection,
            ),
          );

      final known = DisclosedHexSet();
      final positionProvider = NativePositionProvider();
      _disclosedHexRepository = disclosedHexRepository;
      _known = known;
      _positionProvider = positionProvider;

      // 建設（Issue #192・T089）。`BuildingRepository` は `disclosedHexRepository`
      // と同じ `GameDatabase` に対する薄いラッパー（内部状態を持たない）ため、
      // 別インスタンスを作っても二重管理にはならない
      // （`disclosed_hex_repository.dart`・`inventory_repository.dart` と同じ）。
      final buildingRepository = BuildingRepository(widget.paths.gameDatabase);
      final inventoryRepositoryForBuild = InventoryRepository(
        widget.paths.gameDatabase,
      );
      _buildableHexEvaluator = BuildableHexEvaluator(
        widget.paths.gameDatabase,
        regionPack: regionPack,
        disclosedHexRepository: disclosedHexRepository,
        buildingRepository: buildingRepository,
        inventoryRepository: inventoryRepositoryForBuild,
      );
      _buildingConstructionService = BuildingConstructionService(
        widget.paths.gameDatabase,
        regionPack: regionPack,
        disclosedHexRepository: disclosedHexRepository,
        buildingRepository: buildingRepository,
        inventoryRepository: inventoryRepositoryForBuild,
      );
      // 建設タブで既に建物が選ばれた状態でこのウィジェットが作られた場合
      // （「建設タブで選ぶ→地図タブに切り替わる」という通常の流れ。
      // `build_selection_controller.dart` クラスdoc参照）は、ハイライト
      // レイヤーの準備が整うタイミング（[_onBuildableHighlightLayerReady]）で
      // 初期値を反映する（ハイライトレイヤーが無い間は
      // `setFeatureState`/`removeFeatureState` を呼べないため）。以後の変化は
      // 本リスナーで拾う。
      widget.paths.buildSelection?.addListener(_onBuildSelectionChanged);

      // 徒歩経路: disclosed_hex への保存と名所の収集記録を同一トランザクションで
      // 行うデコレータ（Issue #159・T070）。`DisclosureService` 自体
      // （`core`）は変更せず、`repository`（`Repository<DisclosedHex, HexId>`）の
      // 実装だけをこれに差し替える（`LandmarkAwareDisclosedHexRepository`
      // クラスdoc参照）。復元（`restoreDisclosedHexes`）・デバッグパネル・
      // `TerrainYieldPipeline.disclosedHexRepository`（地形カウンタ初期化用）は
      // 引き続きプレーンな [disclosedHexRepository] を使う（`save` 以外の
      // 操作には名所判定は不要なため）。
      final landmarkAwareDisclosedHexRepository =
          LandmarkAwareDisclosedHexRepository(
            widget.paths.gameDatabase,
            regionPack: regionPack,
            disclosedHexRepository: disclosedHexRepository,
            collectionRepository: collectionRepository,
            onCollected: _showLandmarkCollectedSnackBar,
          );

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: regionPack,
        known: known,
        repository: landmarkAwareDisclosedHexRepository,
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

      // 名所ピンレイヤー（Issue #160・T071）: ヘクスが新規開示されるたびに
      // TerrainYieldPipeline から呼ばれ、そのヘクスに属する名所を「開示済み」
      // 表示へ切り替える（`_landmarkController` は onLandmarkLayerReady が
      // 発火するまで null。`reveal` と同じ「都度読むだけ」の方針）。
      Future<void> revealLandmarks(HexId hexId) async {
        final controller = _landmarkController;
        if (controller == null) return;
        await controller.revealPointsOfInterest(
          regionPack.pointsOfInterestIn(hexId).map((poi) => poi.id),
        );
      }

      final terrainHexCounter = TerrainHexCounter();
      final inventoryRepository = InventoryRepository(
        widget.paths.gameDatabase,
      );
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
        revealLandmarks: revealLandmarks,
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
        // ポイント消費による未踏破ヘクスの開放（Issue #151・T064）。既定の
        // OpeningPointBalanceRepository・DisclosedHexRepository を使うため、
        // 上記 openingPointCoordinator（入手側）・disclosedHexRepository（開示の
        // 保存先）と同じ opening_point.points・disclosed_hex を読み書きする
        // （二重管理しない。`HexOpeningSpendService` クラスdoc参照）。
        // regionPack・collectionRepository を渡すことで、開放と同一トランザクション
        // で名所の収集記録（collect_method=point）も行う（Issue #159・T070）。
        // 収集結果の通知は `onCollected` ではなく `HexOpeningSpendResult.
        // collectedLandmarks` → `HexOpeningAttemptResult` 経由で
        // `_handleFogHexTapped` に渡す（`HexOpeningSheet` が閉じた後に
        // SnackBar を出すため。`HexOpeningSheet` クラスdoc参照）。
        hexOpeningSpendService: HexOpeningSpendService(
          widget.paths.gameDatabase,
          regionPack: regionPack,
          collectionRepository: collectionRepository,
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

  /// [MapView.onLandmarkLayerReady] から呼ぶ（Issue #160・T071）。
  ///
  /// [_onFogLayerReady] の fog 復元（`restoreDisclosedHexes`）と対になる処理。
  /// アプリ起動時点で既に開示済みのヘクス・既に収集済みの名所を、レイヤー
  /// 追加直後に一括で反映する（そうしないと、新規にヘクスを開示するまで
  /// 既存の開示済みヘクスの名所が伏せピンのまま表示され続けてしまう）。
  /// `_landmarkController` 自体は fog と異なりラスタ画像の生成完了を待つため
  /// 発火が遅れうるが、`onLandmarkLayerReady` は `MapView` 側で画像生成完了後に
  /// 呼ばれるため、本メソッドが呼ばれた時点では常に画像は登録済みである
  /// （`map_view.dart` の `_addRegionPackLayers` 参照）。
  ///
  /// 【`restoreState` でまとめて反映する（Issue #170）】開示済みヘクスの数だけ
  /// ループする点は変わらないが、ループのたびに
  /// `LandmarkLayerController.revealPointsOfInterest` を呼ぶと、その都度
  /// ソース全体が `setGeoJsonSource` で差し替わり無駄が大きい
  /// （`landmark_layer.dart` の `LandmarkLayerController.restoreState`
  /// クラスdoc参照）。ここでは開示済み・収集済みの全POI IDをまず集めてから、
  /// `restoreState` で1回にまとめて反映する。
  Future<void> _onLandmarkLayerReady(LandmarkLayerController controller) async {
    _landmarkController = controller;

    final regionPack = _regionPack;
    final disclosedHexRepository = _disclosedHexRepository;
    final collectionRepository = _collectionRepository;
    if (regionPack == null ||
        disclosedHexRepository == null ||
        collectionRepository == null) {
      return;
    }

    final disclosedHexes = await disclosedHexRepository.findAll();
    final revealedIds = <PointOfInterestId>{};
    for (final hex in disclosedHexes) {
      revealedIds.addAll(
        regionPack.pointsOfInterestIn(hex.hexId).map((poi) => poi.id),
      );
    }

    final collected = await collectionRepository.findAll();

    await controller.restoreState(
      revealed: revealedIds,
      collected: collected.map((row) => PointOfInterestId(row.poiId)),
    );
  }

  /// [MapView.onBuildableHighlightLayerReady] から呼ぶ（Issue #192・T089）。
  ///
  /// [_onLandmarkLayerReady] と同じ「レイヤー追加後に初期状態をまとめて反映
  /// する」考え方——建設タブで既に建物が選ばれた状態でこのウィジェットが
  /// 作られた場合（`initState` の `widget.paths.buildSelection?.addListener`
  /// コメント参照）は、本コールバックが発火した時点で初めてハイライトを
  /// 計算・適用できる（ハイライトレイヤーが無い間は `setFeatureState` を
  /// 呼べないため）。
  void _onBuildableHighlightLayerReady(BuildableHighlightController controller) {
    _buildableHighlightController = controller;
    final selection = widget.paths.buildSelection?.value;
    if (selection != null) {
      unawaited(_computeAndApplyBuildHighlight(selection));
    }
  }

  /// [BuildSelectionController]（`widget.paths.buildSelection`）の変化を拾う
  /// リスナー（Issue #192・T089）。建物が選ばれれば建てられるマスをハイライト、
  /// 選択が解除されれば（「やめる」・建築成功後）ハイライトを消す。
  void _onBuildSelectionChanged() {
    final selection = widget.paths.buildSelection?.value;
    if (selection == null) {
      unawaited(_clearBuildHighlight());
      return;
    }
    unawaited(_computeAndApplyBuildHighlight(selection));
  }

  /// [buildingType] について開示済み全ヘクスを評価し、`canBuild` なマスだけを
  /// 地図上でハイライトする（Issue #192 本文「2. 建設の流れ（画面）」
  /// 「選んだ建物を建てられるマスをハイライトする」）。
  ///
  /// 建てられるマスが1つも無い場合は [_buildEmptyMessage] を設定する
  /// （DESIGN.md「画面一覧と状態」建設行「空=建設可能地なし」）。
  Future<void> _computeAndApplyBuildHighlight(BuildingType buildingType) async {
    final evaluator = _buildableHexEvaluator;
    final featureIdByHexId = _featureIdByHexId;
    if (evaluator == null || featureIdByHexId == null) return;
    // 同時に複数の評価を走らせない（連続して建物を切り替えた場合の競合を防ぐ。
    // 古い結果は下の選択チェックで捨てられるが、DBアクセスの重複自体も避ける）。
    if (_computingBuildHighlight) return;
    _computingBuildHighlight = true;
    try {
      final evaluations = await evaluator.evaluateAll(buildingType: buildingType);
      if (!mounted) return;
      // 評価中に選択が変わっていた場合、古い結果で上書きしない。
      if (widget.paths.buildSelection?.value != buildingType) return;

      final buildableFeatureIds = <int>{};
      for (final entry in evaluations.entries) {
        if (!entry.value.canBuild) continue;
        final featureId = featureIdByHexId[entry.key];
        if (featureId != null) buildableFeatureIds.add(featureId);
      }

      setState(() {
        _buildEmptyMessage = buildableFeatureIds.isEmpty
            ? '建てられる場所がありません（開示済みの空き地がない／条件を満たす空き地がない等）'
            : null;
      });
      await _buildableHighlightController?.setHighlighted(buildableFeatureIds);
    } finally {
      _computingBuildHighlight = false;
    }
  }

  /// 建設の選択をやめた・建築が成功した際にハイライトを消す（Issue #192）。
  Future<void> _clearBuildHighlight() async {
    if (mounted) {
      setState(() => _buildEmptyMessage = null);
    }
    await _buildableHighlightController?.clear();
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

  /// [MapView.onFogHexTapped] から呼ぶ（Issue #151・T064「ポイント消費による
  /// 未踏破ヘクスの開放」）。タップされた fog 地物の `featureId` を
  /// [_hexIdByFeatureId]（起動時に一度だけ組み立て済み）で `core` の [HexId] に
  /// 変換し、[HexOpeningSheet]（モーダルボトムシート・「配置」については
  /// 同ファイルのクラスdoc参照）を開く。
  ///
  /// ## シートが閉じた後にSnackBarを表示する（Issue #159・T070）
  /// [onConfirm]（[TerrainYieldPipeline.openHexWithPoints]）の結果を
  /// [_lastHexOpeningAttempt] に自前で捕まえておき、`showModalBottomSheet` の
  /// `Future` 完了後（＝シートが完全に閉じた後）に読んで、新規収集があれば
  /// [_showLandmarkCollectedSnackBar] を呼ぶ。
  ///
  /// **シート側の `Navigator.pop()` 戻り値には依存しない**（advisor指摘・
  /// 2026-09-14）: 利用者がスワイプで閉じる・モーダルの外側をタップして
  /// 閉じるといった `HexOpeningSheet` の「閉じる」ボタン以外の一般的な
  /// dismiss操作では `pop()` が引数なしで呼ばれ、戻り値が `null` になる。
  /// これに依存すると、その場合だけ収集していてもSnackBarが出ないという
  /// 抜け漏れが生まれる（`HexOpeningSheet` クラスdoc参照）。
  void _handleFogHexTapped(int featureId) {
    // 【Issue #192・T089「霧のヘクスのタップと衝突しない」】建設の選択中
    // （`widget.paths.buildSelection?.value` が非null）は、霧のタップを常に
    // 建設のタップ処理に振り替える——開放ポイントのシート（下記の通常経路）は
    // 開かない。選択が無ければ従来どおり開放ポイントのシートを開く
    // （優先順位: 建設モード中 > 開放ポイント）。
    final activeBuildingType = widget.paths.buildSelection?.value;
    if (activeBuildingType != null) {
      unawaited(_handleBuildHexTapped(featureId, activeBuildingType));
      return;
    }

    final hexId = _hexIdByFeatureId?[featureId];
    final pipeline = _pipeline;
    if (hexId == null || pipeline == null) return;

    // シート表示用のプレビュー判定（確定はシート内の onConfirm が
    // `pipeline.openHexWithPoints` を通じてトランザクション内で再確認する。
    // `HexOpeningSheet` クラスdoc「判定の二段構え」参照）。
    final evaluation = evaluateHexOpening(
      hexId: hexId,
      regionPack: pipeline.disclosureService.regionPack,
      known: pipeline.disclosureService.known,
      currentPoints: pipeline.openingPointCoordinator.points,
    );

    HexOpeningAttemptResult? lastAttempt;
    final sheetClosed = showModalBottomSheet<void>(
      context: context,
      builder: (context) => HexOpeningSheet(
        evaluation: evaluation,
        currentPoints: pipeline.openingPointCoordinator.points,
        onConfirm: () async {
          final attempt = await pipeline.openHexWithPoints(hexId);
          lastAttempt = attempt;
          return attempt;
        },
      ),
    );
    unawaited(
      sheetClosed.then((_) {
        final attempt = lastAttempt;
        if (attempt == null) return;
        _showLandmarkCollectedSnackBar(attempt.collectedLandmarks);
      }),
    );
  }

  /// [_handleFogHexTapped] から、建設の選択中（`widget.paths.buildSelection`
  /// が非null）に呼ばれる（Issue #192・T089）。タップされた `featureId` を
  /// [HexId] に変換し、[BuildConfirmSheet]（確認シート）を開く。
  ///
  /// ## タップ時点で改めて評価する（キャッシュに頼らない）
  /// ハイライト計算時点（[_computeAndApplyBuildHighlight]）の評価結果は
  /// 表示用のスナップショットでしかなく、タップした瞬間に
  /// [BuildableHexEvaluator.evaluateOne] で再評価する。ハイライトされていない
  /// マス（未開示・空き地でない等）をタップした場合もここで理由を返せる
  /// （Issue #192 本文「建てられないマスをタップしたら理由を表示する」）。
  /// 実際の確定判定はさらに [BuildingConstructionService.build] が
  /// トランザクション内で行う（[HexOpeningSheet] の「判定の二段構え」ならぬ
  /// 「判定の三段構え」——ハイライト用評価・タップ時プレビュー・確定時の3回。
  /// いずれも同じ `evaluateBuild` を呼ぶだけの軽い処理のため、重複呼び出しに
  /// よる性能上の懸念はない）。
  Future<void> _handleBuildHexTapped(int featureId, BuildingType buildingType) async {
    final hexId = _hexIdByFeatureId?[featureId];
    final evaluator = _buildableHexEvaluator;
    final constructionService = _buildingConstructionService;
    final disclosedHexRepository = _disclosedHexRepository;
    if (hexId == null ||
        evaluator == null ||
        constructionService == null ||
        disclosedHexRepository == null) {
      return;
    }

    final evaluation = await evaluator.evaluateOne(
      hexId: hexId,
      buildingType: buildingType,
    );
    final disclosedHex = await disclosedHexRepository.findById(hexId);
    if (!mounted) return;

    final buildingLabel = buildingSpecs
        .firstWhere((spec) => spec.buildingType == buildingType)
        .label;

    BuildResult? lastResult;
    final sheetClosed = showModalBottomSheet<void>(
      context: context,
      builder: (context) => BuildConfirmSheet(
        buildingLabel: buildingLabel,
        terrainType: disclosedHex?.terrainType,
        evaluation: evaluation,
        onConfirm: () async {
          final result = await constructionService.build(
            hexId: hexId,
            buildingType: buildingType,
          );
          lastResult = result;
          return result;
        },
      ),
    );
    unawaited(
      sheetClosed.then((_) {
        final result = lastResult;
        if (result == null || result.outcome != BuildOutcome.built) return;
        // 成功したら選択状態を終える（Issue #192 本文「3. 建てた後」）。
        // これにより本ウィジェットの `_onBuildSelectionChanged` リスナーが
        // ハイライトを自動的に消す。所持資材の表示（建設タブ）は
        // `InventoryScreen`/`BuildScreen` 自身の定期ポーリングが反映する。
        widget.paths.buildSelection?.clear();
        _showBuildSuccessSnackBar(buildingLabel);
      }),
    );
  }

  /// 建築成功を知らせる（Issue #192 本文「3. 建てた後」「成功を知らせる
  /// （SnackBar・`success` トークン）」）。[_showLandmarkCollectedSnackBar] と
  /// 同じ配置方針（固定位置UIを覆わない）を踏襲する。
  void _showBuildSuccessSnackBar(String buildingLabel) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$buildingLabelを建てました'),
        backgroundColor: Theme.of(context).successColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          bottom: AppSpacing.xxxl + AppSpacing.sm,
        ),
      ),
    );
  }

  /// 新規に収集された名所を地図画面に簡易表示する（Issue #159「地図画面で
  /// 収集時に名所名が表示される」）。徒歩経路
  /// （[LandmarkAwareDisclosedHexRepository.onCollected]）・ポイント開放経路
  /// （[_handleFogHexTapped] がシートを閉じた後）の両方から呼ばれる。
  ///
  /// 本格的な通知UI（T077/T078）は対象外（Issue #159「対象外」）のため、
  /// 最小限の [SnackBar] のみ。既存の製品UI（下中央の記録開始ボタン・
  /// 右下の追従ボタン）と重ならないよう、`SnackBarBehavior.floating` ＋
  /// 下マージンでボタン列より上に浮かせる（`docs/opening-points-spend-impl.md`
  /// §6「配置についての判断」と同じ、固定位置UIを覆わせない方針）。
  /// 色・サイズは DESIGN.md のトークン（[AppSpacing]）のみを使い、直書きしない。
  void _showLandmarkCollectedSnackBar(List<LandmarkCollectionRecord> records) {
    if (records.isEmpty) return;

    // 名所ピンレイヤー（Issue #160・T071）: accentハイライト表示への切り替え。
    // 徒歩経路（`LandmarkAwareDisclosedHexRepository.onCollected`）・
    // ポイント開放経路（`_handleFogHexTapped`）のどちらも本メソッドを唯一の
    // 合流点として呼ぶため、ここ1箇所での配線で両経路をカバーできる。
    // SnackBar表示（`mounted` 判定）とは独立した関心事のため、`mounted` の
    // 早期リターンより前に行う。
    unawaited(
      _landmarkController?.markCollected(
            records.map((record) => record.poiId),
          ) ??
          Future<void>.value(),
    );

    if (!mounted) return;

    final names = records.map((record) => '「${record.name}」').join();
    final methodLabel = switch (records.first.collectMethod) {
      CollectMethod.walk => '現地で発見',
      CollectMethod.point => 'ポイントで開放',
    };

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('名所$namesを図鑑に登録しました（$methodLabel）'),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(
          left: AppSpacing.md,
          right: AppSpacing.md,
          // 下中央の記録開始ボタン・右下の追従ボタン（いずれも画面下部に
          // AppSpacing.md のオフセットで配置・`AppSpacing.minTapTarget` の
          // タップ領域を持つ）より上に浮かせる。
          bottom: AppSpacing.xxxl + AppSpacing.sm,
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.paths.buildSelection?.removeListener(_onBuildSelectionChanged);
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
      // 開示済みヘクスの地形タイプ別色分け（Issue #176）。fog と同じソースに
      // 対して fog レイヤーの直下へ挿入される（location 側の
      // `TerrainTintController`・`MapView._addRegionPackLayers` 参照）ため、
      // 新規開示・起動時の復元のいずれも fog 側の feature-state 更新だけで
      // 自動的に追従する。
      terrainTintLayer: buildTerrainTintLayer(),
      // 建設タブで選んだ建物の「建てられるマス」ハイライト（Issue #192・T089）。
      // terrainTintLayer と同じく fog と同じソースの feature-state を使う。
      buildableHighlightLayer: buildBuildableHighlightLayer(),
      onBuildableHighlightLayerReady: _onBuildableHighlightLayerReady,
      // 名所ピンレイヤー（Issue #160・T071）。ラスタ画像の生成完了を
      // `MapView` 側で待ってから追加される（`landmarkAssets` クラスdoc参照）。
      landmarkAssets: _landmarkAssets,
      onLandmarkLayerReady: (controller) {
        unawaited(_onLandmarkLayerReady(controller));
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
      // ヘクスをタップしてポイントで開放する操作（Issue #151・T064）。
      onFogHexTapped: _handleFogHexTapped,
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
    //
    // 【Issue #192・T089】建設の選択中バナー（「やめる」・空状態メッセージ）は、
    // 新しい固定位置UI要素として別途 Positioned を増やさず、本 HUD と同じ
    // 画面上部の Positioned の中で HUD の**直下**（Column）に積む
    // （advisor指摘・2026-09-16。#137/#138/#141/#142/#151 で繰り返した
    // 「新設したUIが既存の固定位置ボタンを覆う」不具合の再発防止と同じ方針を、
    // 新しい Positioned を作らないことで構造的に守る）。
    final activeBuildingType = widget.paths.buildSelection?.value;
    final topOverlay = Positioned(
      left: 0,
      top: 0,
      right: kDebugMode ? AppSpacing.xxl + AppSpacing.sm : 0,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: WalkStatsHud(
                openingPointStats: pipeline.openingPointStats,
                isRecording: _isRecording,
              ),
            ),
            if (activeBuildingType != null)
              _BuildModeBanner(
                buildingLabel: buildingSpecs
                    .firstWhere((spec) => spec.buildingType == activeBuildingType)
                    .label,
                emptyMessage: _buildEmptyMessage,
                onCancel: () => widget.paths.buildSelection?.clear(),
              ),
          ],
        ),
      ),
    );

    if (!kDebugMode) {
      return Stack(
        children: [mapView, followButton, trackingControlButton, topOverlay],
      );
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
        // topOverlay（HUD＋建設モードバナー）は kDebugMode 配下の画面上部
        // デバッグパネル列（下記 `_debugPanelsVisible` 配下の Positioned）より
        // 前（背面）に置く。デバッグパネルを開いている間は詳細診断
        // （`OpeningPointDebugPanel` 等）で同等以上の情報が見えるため、意図的に
        // そちらを手前にしている（両者を重ねて表示する精緻な配置調整は
        // スコープ外・Issue #149 本文）。デバッグパネルを閉じた既定状態
        // （release ビルドと同じ見た目）では topOverlay がそのまま見える。
        topOverlay,
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
                      grantPointsForDebug: pipeline.grantOpeningPointsForDebug,
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

/// 建設の選択中バナー（Issue #192・T089）。
///
/// DESIGN.md「画面一覧と状態」建設行の4状態のうち、地図タブに移った後の
/// 「選択中」「空=建設可能地なし」を担う。常時表示の固定位置UIを新設せず、
/// 画面上部の [WalkStatsHud] の直下（`_DisclosureAwareMapViewState.build` の
/// `topOverlay` 参照）に積むだけにすることで、既存の製品ボタンを覆う不具合の
/// 再発を防ぐ（`map_screen.dart` クラスdoc「2026-09-12（Issue #142）」等、
/// 過去5件の同種不具合の教訓）。
class _BuildModeBanner extends StatelessWidget {
  const _BuildModeBanner({
    required this.buildingLabel,
    required this.emptyMessage,
    required this.onCancel,
  });

  /// 選んでいる建物の日本語ラベル（`build_screen.dart` の `BuildingSpec.label`）。
  final String buildingLabel;

  /// 建てられるマスが1つも無い場合のメッセージ（null なら非表示）。
  final String? emptyMessage;

  /// 「やめる」を押した際に呼ぶ（`BuildSelectionController.clear`）。
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.all(AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.construction,
                  color: theme.colorScheme.primary,
                  size: AppSpacing.md,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    '$buildingLabelを建てる場所を選んでください',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                TextButton(onPressed: onCancel, child: const Text('やめる')),
              ],
            ),
            if (emptyMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: AppSpacing.md,
                      color: theme.colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        emptyMessage!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
