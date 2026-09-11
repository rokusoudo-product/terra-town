import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../economy/terrain_yield_pipeline.dart';

/// 地形産出（受動・時間ベース）の状態を代表・秘書セッションが実機で確認するための
/// デバッグ専用パネル（`kDebugMode` 限定・Issue #138）。
///
/// 【製品UIを汚さない】他のデバッグパネルと同じ方針で、
/// `app/lib/features/map/map_screen.dart` から `kDebugMode` 配下でのみ組み込まれる
/// （release ビルドには一切現れない。資材の本番UI・HUDはT062・T076のスコープ）。
///
/// ## なぜ端数（%）の表示が必須か（Issue #138 本文より）
/// 1個/時間という仮値のままでは、整数の増加を実機で確認するのに最大1時間かかる。
/// 端数（次の1個までの進み具合）を表示することで、産出が止まっているのか
/// 単に1個に達していないだけなのかを区別できる。
///
/// ## なぜ処理件数・最後の行の表示が必須か
/// 産出は新しい位置の行が届いたときにしか進まない（屋内では精度ゲートで
/// 長時間行が届かないことがある）。「位置が届いていない」のか「届いているのに
/// 積算されていない」のかを区別できるよう、処理件数・最後に処理した行id・
/// 単調時刻・セッションIDを表示する。
class TerrainYieldDebugPanel extends StatefulWidget {
  const TerrainYieldDebugPanel({
    super.key,
    required this.stats,
    required this.terrainHexCounter,
    required this.inventoryRepository,
  });

  /// composition root（`TerrainYieldPipeline`）が公開する観測データ。
  final ValueListenable<TerrainYieldPipelineStats> stats;

  /// composition root と共有する、開示済みヘクスの地形別件数カウンタ。
  final TerrainHexCounter terrainHexCounter;

  /// 資材の所持数を読み出すためのリポジトリ（`inventory` テーブル）。
  final InventoryRepository inventoryRepository;

  @override
  State<TerrainYieldDebugPanel> createState() => _TerrainYieldDebugPanelState();
}

class _TerrainYieldDebugPanelState extends State<TerrainYieldDebugPanel> {
  Map<Resource, int> _inventory = const {};

  @override
  void initState() {
    super.initState();
    widget.stats.addListener(_onStatsChanged);
    unawaited(_refreshInventory());
  }

  @override
  void dispose() {
    widget.stats.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    // stats が更新される（＝位置が1件処理される）たびに、フリッカーを避けるため
    // FutureBuilder を毎回作り直すのではなく、読み出した結果を State に保持する。
    unawaited(_refreshInventory());
  }

  Future<void> _refreshInventory() async {
    final inventory = await widget.inventoryRepository.readAll();
    if (!mounted) return;
    setState(() => _inventory = inventory);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ValueListenableBuilder<TerrainYieldPipelineStats>(
            valueListenable: widget.stats,
            builder: (context, stats, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '地形産出 デバッグパネル（デバッグビルドのみ表示・Issue #138）',
                    style: textTheme.labelMedium,
                  ),
                  Text(
                    '【仮値】1ヘクスあたり1時間に1個。正本は balance.csv（Issue #36・未作成）',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '処理した位置: ${stats.processedCount}件 / '
                    '最後の行id: ${stats.lastProcessedRowId ?? "-"} / '
                    'session=${stats.lastProcessedSessionId ?? "-"}',
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    '最後の位置の単調時刻: ${stats.lastProcessedTimestamp ?? "-"} / '
                    'ウォーターマーク(行id): ${stats.watermarkRowId}',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('資材（所持数・次の1個までの進み具合）:', style: textTheme.bodySmall),
                  for (final resource in Resource.values)
                    Text(
                      '  ${_resourceLabel(resource)}: ${_inventory[resource] ?? 0}'
                      '（次まで ${_progressPercent(resource, stats)}%）',
                      style: textTheme.bodySmall,
                    ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('開示済みヘクスの地形別件数:', style: textTheme.bodySmall),
                  for (final terrainType in TerrainType.values)
                    Text(
                      '  ${_terrainLabel(terrainType)}: '
                      '${widget.terrainHexCounter.counts[terrainType] ?? 0}件',
                      style: textTheme.bodySmall,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  int _progressPercent(Resource resource, TerrainYieldPipelineStats stats) {
    final remainder = stats.remainderMicros[resource] ?? 0;
    return ((remainder / terrainYieldMicrosecondsPerUnit) * 100).floor();
  }

  static String _resourceLabel(Resource resource) => switch (resource) {
        Resource.wood => '木',
        Resource.stone => '石',
        Resource.iron => '鉄',
        Resource.salt => '塩',
        Resource.water => '水',
        Resource.vegetable => '野菜',
        Resource.fruit => 'フルーツ',
        Resource.meat => '肉',
      };

  static String _terrainLabel(TerrainType terrainType) => switch (terrainType) {
        TerrainType.vacantLot => '空き地',
        TerrainType.forest => '森',
        TerrainType.mountain => '山',
        TerrainType.waterside => '水辺',
        TerrainType.sea => '海',
      };
}
