import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import 'collection_category.dart';
import 'collection_view_model.dart';
import 'region_pack_loader.dart';

/// 名所図鑑画面（T075・Issue #161）。
///
/// DESIGN.md「画面一覧と状態」の図鑑タブ（「集めた名所を見る」）に対応する。
/// 下部ナビ本体（4タブの骨組み）は既に `main.dart`（Issue #25）にあり、本画面は
/// 図鑑タブの中身のみを実装する（Issue #150・インベントリ画面と同じ置き場所の
/// 考え方。`main.dart` の `RootScaffold._selectedIndex == 2` に接続する）。
///
/// ## データソースが2つある理由
/// - カテゴリ集計の「総数」（分母）は**現在の地域パック**の名所件数
///   （[RegionPack.pointsOfInterest]。現行パックは51件）が正（Issue #161本文）。
/// - 収集済みの名称・収集日時・収集手段は**`collection` テーブルのスナップショット**
///   （[CollectionRepository]）が正（`docs/landmark-collection-impl.md` §4）。
///
/// 集計・一覧の組み立て自体は [buildCollectionViewData]（`collection_view_model.dart`）
/// に切り出してあり、本ウィジェットは「2つの非同期読み込みをまとめて実行し、
/// 結果を組み立て関数に渡して表示するだけ」の薄いUIである。
///
/// ## 更新方式（受け入れ基準「地図画面で新しく収集したとき、図鑑画面を開き直せば
/// 反映されること」）
/// `main.dart` の `RootScaffold` はタブ切替のたびに body を作り直す
/// （`switch (_selectedIndex)` が毎回新しい Widget を返す）ため、本画面は
/// [State.initState] で一度読み込むだけでよい（Issue #150・インベントリ画面が
/// 採用した「定期ポーリングで開いている間も更新する」方式までは要求されていない
/// ——Issue #161 本文「リアルタイム購読までは不要。インベントリ画面の方式に合わせる」
/// ＝新しい Repository を作らず都度読み直す、という方式面の言及であり、開いている
/// 間の自動更新までは求めていないと解釈した。念のため、開いている間に反映したい
/// 場合のための手動更新（引っ張って更新）は用意する）。
///
/// ## 未収集の名所の見せ方（2026-09-13代表決定・Issue #161本文）
/// シルエット画像は作らない（画像生成は承認ゲート対象のため本Issueでは行わない）。
/// 代わりに Material アイコン（[Icons.help_outline]）＋「？」で伏せる。
/// DESIGN.md「画面一覧と状態」の図鑑行に残る「シルエット」という語はこの実装と
/// 食い違うため、DESIGN.md 側の文言修正案を本PRの説明に記載した
/// （DESIGN.md 自体は本PRで変更していない——代表承認が要る仕様文言のため）。
class CollectionScreen extends StatefulWidget {
  const CollectionScreen({
    super.key,
    required this.collectionRepository,
    this.loadRegionPack = defaultLoadRegionPack,
  });

  /// 収集記録の読み取り先（本番では `CollectionRepository(gameDatabase)`。
  /// `game_state.sqlite` 側。Issue #159 で追加済みの既存クラスをそのまま使う）。
  final CollectionRepository collectionRepository;

  /// 地域パックの読み込み関数（既定は実アセットから読む [defaultLoadRegionPack]）。
  /// widget テストではフェイクに差し替える（`region_pack_loader.dart` 参照）。
  final LoadRegionPack loadRegionPack;

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

enum _LoadState { loading, loaded, error }

class _CollectionScreenState extends State<CollectionScreen> {
  _LoadState _loadState = _LoadState.loading;
  CollectionViewData _data = const CollectionViewData(
    categorySummaries: [],
    entries: [],
  );
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadState = _LoadState.loading;
      _loadError = null;
    });
    try {
      // 2つの非同期読み込み（地域パック・収集記録）を並行して開始する
      // （`Future.wait` は要素の型が揃っていないと使えないため、個別に
      // Future を先に起動してから await する形にしている）。
      final packFuture = widget.loadRegionPack();
      final collectedFuture = widget.collectionRepository.findAll();
      final pack = await packFuture;
      final collected = await collectedFuture;
      if (!mounted) return;
      setState(() {
        _data = buildCollectionViewData(pack: pack, collected: collected);
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

  @override
  Widget build(BuildContext context) {
    switch (_loadState) {
      case _LoadState.loading:
        return const _CollectionLoadingView();
      case _LoadState.error:
        return _CollectionErrorView(error: _loadError!, onRetry: _load);
      case _LoadState.loaded:
        return _CollectionLoadedView(data: _data, onRefresh: _load);
    }
  }
}

class _CollectionLoadingView extends StatelessWidget {
  const _CollectionLoadingView();

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: AppSpacing.md),
          Text('名所図鑑を読み込み中…', style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _CollectionErrorView extends StatelessWidget {
  const _CollectionErrorView({required this.error, required this.onRetry});

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
              Icons.collections_bookmark_outlined,
              size: AppSpacing.xxl,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('名所図鑑を読み込めませんでした', style: theme.textTheme.titleMedium),
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

class _CollectionLoadedView extends StatelessWidget {
  const _CollectionLoadedView({required this.data, required this.onRefresh});

  final CollectionViewData data;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // カテゴリ自体が0件（`poi` テーブルを持たない旧パック等）＝本当に何も
    // 表示するものが無い状態。DESIGN.md「図鑑」行の空状態はこちらではなく
    // 「未収集の見せ方（？表示）」の方を指す（クラスdoc参照）ため、通常は
    // ここに来ない（現行パックは51件）。
    if (data.entries.isEmpty) {
      return const _CollectionEmptyView();
    }

    final totalCollected = data.categorySummaries.fold<int>(
      0,
      (sum, s) => sum + s.collectedCount,
    );
    final totalCount = data.categorySummaries.fold<int>(
      0,
      (sum, s) => sum + s.totalCount,
    );

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Text('名所図鑑', style: theme.textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '収集済み $totalCollected / $totalCount',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CategorySummaryCard(summaries: data.categorySummaries),
            const SizedBox(height: AppSpacing.lg),
            Text('名所一覧', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            for (final entry in data.entries) _CollectionEntryTile(entry: entry),
          ],
        ),
      ),
    );
  }
}

class _CollectionEmptyView extends StatelessWidget {
  const _CollectionEmptyView();

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
              Icons.collections_bookmark_outlined,
              size: AppSpacing.xxl,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.md),
            Text('名所データがありません', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '同梱の地域パックに名所データが含まれていません。',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySummaryCard extends StatelessWidget {
  const _CategorySummaryCard({required this.summaries});

  final List<CategorySummary> summaries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('カテゴリ別の収集状況', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            for (final summary in summaries) _CategorySummaryRow(summary: summary),
          ],
        ),
      ),
    );
  }
}

class _CategorySummaryRow extends StatelessWidget {
  const _CategorySummaryRow({required this.summary});

  final CategorySummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // accent（DESIGN.md「アクセント（獲得・名所ハイライト、10%）」）を
    // 名所の収集数バッジに使う。Material3 マッピングでは tertiary スロット
    // （`design/color_tokens.dart` 参照）。
    final accent = theme.colorScheme.tertiary;
    final isComplete = summary.totalCount > 0 && summary.collectedCount >= summary.totalCount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Icon(
            _iconForCategory(summary.category),
            color: isComplete ? accent : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(summary.category.label, style: theme.textTheme.bodyMedium),
          ),
          Text(
            '${summary.collectedCount} / ${summary.totalCount}',
            style: theme.textTheme.titleMedium?.copyWith(
              color: isComplete ? accent : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionEntryTile extends StatelessWidget {
  const _CollectionEntryTile({required this.entry});

  final CollectionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.colorScheme.onSurfaceVariant;

    if (!entry.isCollected) {
      // 未収集: 名称を伏せる（クラスdoc「未収集の名所の見せ方」参照）。
      return ListTile(
        leading: Icon(Icons.help_outline, color: mutedColor),
        title: Text('？', style: theme.textTheme.bodyLarge?.copyWith(color: mutedColor)),
        subtitle: Text(entry.category.label, style: theme.textTheme.bodySmall?.copyWith(color: mutedColor)),
      );
    }

    final subtitleParts = <String>[
      entry.category.label,
      if (entry.collectedAt != null) _formatDateTime(entry.collectedAt!),
      if (entry.collectMethod != null) _labelForCollectMethod(entry.collectMethod!),
      if (entry.isOrphaned) '現在のパックには存在しません',
    ];

    return ListTile(
      leading: Icon(_iconForCategory(entry.category), color: theme.colorScheme.primary),
      title: Text(entry.name ?? '（名称不明）', style: theme.textTheme.bodyLarge),
      subtitle: Text(subtitleParts.join(' ・ '), style: theme.textTheme.bodySmall),
    );
  }
}

/// 収集手段のラベル（Issue #161本文「`collect_method` が `walk` なら『現地で発見』、
/// `point` なら『ポイントで開放』」）。
String _labelForCollectMethod(CollectMethod method) => switch (method) {
  CollectMethod.walk => '現地で発見',
  CollectMethod.point => 'ポイントで開放',
};

/// カテゴリごとの代替アイコン（Material Icons。`InventoryScreen._iconFor` と
/// 同じ「画像アセットは新規生成しない」方針。Issue #161本文「Materialアイコンを
/// 使い、シルエット画像は作らない」）。
IconData _iconForCategory(LandmarkCategory category) => switch (category) {
  LandmarkCategory.shrineTemple => Icons.temple_buddhist,
  LandmarkCategory.historicMemorial => Icons.account_balance,
  LandmarkCategory.museum => Icons.museum,
  LandmarkCategory.viewpoint => Icons.landscape,
  LandmarkCategory.park => Icons.park,
  LandmarkCategory.artwork => Icons.palette,
  LandmarkCategory.informationCenter => Icons.info_outline,
  LandmarkCategory.attraction => Icons.attractions,
  LandmarkCategory.other => Icons.place,
};

/// 収集日時の表示用フォーマット（`intl` パッケージを新規依存に追加せず、
/// `app/pubspec.yaml` の既存方針「UI文言はコード内に日本語で直書き」に合わせて
/// 手組みする）。ローカルタイムで `yyyy/MM/dd HH:mm` 形式にする。
String _formatDateTime(DateTime dateTime) {
  final local = dateTime.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
