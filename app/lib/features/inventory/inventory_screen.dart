import 'dart:async';

import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';

/// 資材インベントリ画面（T076・Issue #150）。
///
/// 建設タブ（DESIGN.md「画面一覧と状態」建設行）に置く、所持資材の一覧表示。
/// 建設UI本体（建物を建てる操作・T089）はまだ無いため、現時点では
/// 「建設タブを開くと所持資材が見える」状態になる。T089 実装時は本ウィジェットを
/// 建設タブ内の一部（例: 上部の資材サマリー）として組み込み直すことを想定している。
///
/// ## 置き場所を建設タブにした理由（Issue #150 提案内容2）
/// 資材は建設で使うものであり、DESIGN.md の4タブ（マップ/建設/図鑑/設定）のうち
/// 建設タブに置くのが最も素直。マップタブは Issue #149（歩行距離・歩数のHUD）が
/// 別件で同時に編集中のため触らない（Issue #150 本文の並行作業注意）。
///
/// ## 読み取りは既存の [InventoryRepository] のみ（新しい Repository は作らない）
/// `packages/location/lib/src/db/inventory_repository.dart`（Issue #143）を
/// そのまま使う。本画面は「渡された [InventoryRepository] を読むだけ」の
/// 薄いUIであり、独自の永続化ロジックを持たない。
///
/// ## 更新方式（受け入れ基準「資材が増えると表示が更新される」）
/// `kDebugMode` 限定の [TerrainYieldDebugPanel]
/// （`app/lib/map/debug/terrain_yield_debug_panel.dart`）と同じ
/// 「都度 [InventoryRepository.readAll] を呼び直して State に保持する」方式を採る。
/// ただし通知の発火源が異なる: デバッグパネルは `TerrainYieldPipeline.stats`
/// （地図タブの composition root 内部の `ValueListenable`）を購読できるが、
/// それは `_DisclosureAwareMapViewState` に閉じた非公開の状態であり、
/// マップ画面を経由しない建設タブからは参照できない（かつ Issue #150 の
/// 並行作業注意により `map_screen.dart` を変更できない）。そのため本画面は
/// [refreshInterval] 間隔の [Timer.periodic] による定期ポーリングで
/// [InventoryRepository.readAll] を呼び直す。地形産出はマップ画面が
/// マウントされている間しか進まない（`map_screen.dart` 参照）ため、
/// 本画面が開かれている間だけ増分を追従できれば十分と判断した。
///
/// ## 所持数が0の資材の扱い（Issue #150 提案内容1・受け入れ基準）
/// 地形産出（Issue #138）が対応する資材は 木・石・鉄・水・塩 の5種のみで、
/// 野菜・フルーツ・肉は建物産出（T086・未実装）でしか得られない。そのため
/// 「0が並ぶだけの画面」を避けるべく、2段階の扱いに分けた:
///
/// 1. **全資材が0（[InventoryRepository.readAll] が空Map）＝ゲーム開始直後**:
///    8種類すべてを「0」で並べると初見の利用者に何もすることがないように
///    見えてしまう（新規プレイヤーが最初に必ず踏む状態）ため、資材一覧の
///    代わりに [_InventoryEmptyView]（案内文つきの空状態）を表示する。
/// 2. **一部の資材だけ0（例: 木・石は貯まったが野菜は0）＝プレイ中の通常状態**:
///    産出手段が実装済みの資材（木・石・鉄・水・塩）は「0」とそのまま表示する
///    （まだ集めていないだけであり、いずれ増える）。産出手段が未実装の資材
///    （野菜・フルーツ・肉。[_unobtainableResourcesPendingBuildingProduction]）は
///    「0」ではなく錠前アイコン＋「建物の実装待ち」の注記に置き換える。
///    「集め方が分からず0のまま」という誤解と、「産出手段自体がまだ無い」という
///    事実を区別して伝えるため。T086（建物産出）実装時は
///    [_unobtainableResourcesPendingBuildingProduction] を更新（縮小）すること。
///
/// ## 資材アイコンについて（Issue #150 提案内容5・スコープ外）
/// 資材ごとの画像アセットは新規生成していない（`IMAGE_WORKFLOW.md` の承認ゲートが
/// 必要なため）。Material Icons のうち意味が近いものを代替として使っている
/// （[_iconFor] 参照）。将来アイコン画像を用意する場合は spec-image フローで
/// 別途 Issue を起票すること。
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.inventoryRepository,
    this.refreshInterval = const Duration(seconds: 2),
  });

  /// 資材の所持数の読み取り先（本番では `InventoryRepository(gameDatabase)`）。
  final InventoryRepository inventoryRepository;

  /// 定期ポーリングの間隔（クラスdoc「更新方式」参照）。テストでは短い値に
  /// 差し替えることで、`tester.pump` による即時検証を可能にする。
  final Duration refreshInterval;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

enum _LoadState { loading, loaded, error }

class _InventoryScreenState extends State<InventoryScreen> {
  _LoadState _loadState = _LoadState.loading;
  Map<Resource, int> _inventory = const {};
  Object? _loadError;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      widget.refreshInterval,
      (_) => _refreshSilently(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadState = _LoadState.loading;
      _loadError = null;
    });
    try {
      final inventory = await widget.inventoryRepository.readAll();
      if (!mounted) return;
      setState(() {
        _inventory = inventory;
        _loadState = _LoadState.loaded;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loadState = _LoadState.error;
      });
    }
  }

  /// 定期ポーリングによる再読込。クラスdoc「更新方式」参照。
  ///
  /// 【ポーリング中の失敗を握りつぶす理由】初回 [_load] で疎通確認済みの
  /// リポジトリへの一時的な失敗（例: 書き込みと競合した一瞬）でエラー画面に
  /// 切り替えてしまうと、閲覧中の利用者を毎回突き放すことになる。直前の表示を
  /// 維持し、次回のポーリングで自然に回復させる。
  Future<void> _refreshSilently() async {
    if (!mounted || _loadState != _LoadState.loaded) return;
    try {
      final inventory = await widget.inventoryRepository.readAll();
      if (!mounted) return;
      setState(() => _inventory = inventory);
    } catch (_) {
      // 上記コメント参照。握りつぶして次回のポーリングに委ねる。
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_loadState) {
      case _LoadState.loading:
        return const _InventoryLoadingView();
      case _LoadState.error:
        return _InventoryErrorView(error: _loadError!, onRetry: _load);
      case _LoadState.loaded:
        return _InventoryLoadedView(inventory: _inventory);
    }
  }
}

class _InventoryLoadingView extends StatelessWidget {
  const _InventoryLoadingView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text('資材を読み込み中…', style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _InventoryErrorView extends StatelessWidget {
  const _InventoryErrorView({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

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
              Icons.inventory_2_outlined,
              size: AppSpacing.xxl,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('資材を読み込めませんでした', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '$error',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(onPressed: onRetry, child: const Text('やり直す')),
          ],
        ),
      ),
    );
  }
}

/// 産出手段がまだ実装されていない資材（クラスdoc「所持数が0の資材の扱い」参照）。
///
/// 【TODO】T086（建物産出）が実装され次第、産出可能になった資材をここから除くこと。
const _unobtainableResourcesPendingBuildingProduction = {
  Resource.vegetable,
  Resource.fruit,
  Resource.meat,
};

class _InventoryLoadedView extends StatelessWidget {
  const _InventoryLoadedView({required this.inventory});

  final Map<Resource, int> inventory;

  @override
  Widget build(BuildContext context) {
    // InventoryRepository.readAll は所持数が1以上の資材しか返さない
    // （`add` が delta<=0 では行を作らないため）。つまり空Map＝全資材が0。
    if (inventory.isEmpty) {
      return const _InventoryEmptyView();
    }

    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Text('所持資材', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          _CategorySection(
            title: '建設系（建物の建設・強化に使用）',
            resources: Resource.values
                .where((r) => r.category == ResourceCategory.construction)
                .toList(growable: false),
            inventory: inventory,
          ),
          const SizedBox(height: AppSpacing.lg),
          _CategorySection(
            title: '生活系（住民/街の効率UP・人口成長に使用）',
            resources: Resource.values
                .where((r) => r.category == ResourceCategory.living)
                .toList(growable: false),
            inventory: inventory,
          ),
        ],
      ),
    );
  }
}

class _InventoryEmptyView extends StatelessWidget {
  const _InventoryEmptyView();

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
              Icons.inventory_2_outlined,
              size: AppSpacing.xxl,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('まだ資材がありません', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'マップを歩いて森・山・水辺・海のヘクスを開示すると、\n'
              '木・石・鉄・水・塩が少しずつ貯まります。',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.resources,
    required this.inventory,
  });

  final String title;
  final List<Resource> resources;
  final Map<Resource, int> inventory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            for (final resource in resources)
              _ResourceRow(
                resource: resource,
                amount: inventory[resource] ?? 0,
                isUnobtainable: _unobtainableResourcesPendingBuildingProduction
                    .contains(resource),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResourceRow extends StatelessWidget {
  const _ResourceRow({
    required this.resource,
    required this.amount,
    required this.isUnobtainable,
  });

  final Resource resource;
  final int amount;
  final bool isUnobtainable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    final iconColor = isUnobtainable ? mutedColor : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(_iconFor(resource), color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _labelFor(resource),
              style: isUnobtainable
                  ? theme.textTheme.bodyMedium?.copyWith(color: mutedColor)
                  : theme.textTheme.bodyMedium,
            ),
          ),
          if (isUnobtainable)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: AppSpacing.md, color: mutedColor),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  '建物の実装待ち',
                  style: theme.textTheme.bodySmall?.copyWith(color: mutedColor),
                ),
              ],
            )
          else
            Text('$amount', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }
}

/// 資材の日本語ラベル。`TerrainYieldDebugPanel._resourceLabel` と同じ対応表だが、
/// デバッグパネルは `kDebugMode` 限定の非公開クラスであり共有できないため、
/// 本ファイルに個別に持つ（Issue #150 は新しい Repository を作らない方針だが、
/// 表示用ラベルはUI側の関心事であり Repository ではない）。
String _labelFor(Resource resource) => switch (resource) {
  Resource.wood => '木',
  Resource.stone => '石',
  Resource.iron => '鉄',
  Resource.salt => '塩',
  Resource.water => '水',
  Resource.vegetable => '野菜',
  Resource.fruit => 'フルーツ',
  Resource.meat => '肉',
};

/// 資材ごとの代替アイコン（Material Icons。クラスdoc「資材アイコンについて」参照）。
IconData _iconFor(Resource resource) => switch (resource) {
  Resource.wood => Icons.forest,
  Resource.stone => Icons.terrain,
  Resource.iron => Icons.hardware,
  Resource.salt => Icons.grain,
  Resource.water => Icons.water_drop,
  Resource.vegetable => Icons.agriculture,
  // 【注意】Icons.apple は果物ではなく Apple Inc. のロゴ（Icons.facebook 等と同じ
  // ブランドアイコン群）のため使わないこと。花を表す local_florist を代替に使う。
  Resource.fruit => Icons.local_florist,
  Resource.meat => Icons.kebab_dining,
};
