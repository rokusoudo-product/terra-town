import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';

import '../../design/spacing.dart';
import '../economy/terrain_yield_pipeline.dart';

/// 開放ポイント（歩行距離換算）の状態を代表・秘書セッションが実機で確認するための
/// デバッグ専用パネル（`kDebugMode` 限定・Issue #143）。
///
/// 【製品UIを汚さない】他のデバッグパネルと同じ方針で、
/// `app/lib/features/map/map_screen.dart` から `kDebugMode` 配下でのみ組み込まれる
/// （release ビルドには一切現れない。ポイント消費によるヘクス開放UIはT064、
/// 歩行距離・歩数のHUDはT062のスコープ）。
///
/// ## なぜ端数（%）の表示が必須か
/// 換算レート 1.5km=1P のままでは、整数の増加を実機で確認するのに1.5km
/// 歩く必要がある（`TerrainYieldDebugPanel` の「1時間に1個」と同じ理由）。
/// 端数（次の1Pまでの進み具合）を表示することで、短い距離を歩いただけでも
/// 「計上が進んでいる」ことを確認できる（屋内では精度ゲート〔30m〕で位置が
/// 長時間届かないことがあるため、「位置が届いていない」のか「届いているのに
/// 積算されていない」のかを区別できるようにする狙いも同じ）。
///
/// ## なぜ直近区間の距離・倍率・理由の表示が必須か
/// 偽装対策（`RewardPolicy`）が実際に効く最初の実装（Issue #143 本文）である
/// ため、「モック位置・速度超過で倍率0になり増えない」「歩数不一致で倍率0.5に
/// 減る」ことを代表・秘書が実機で確認できるよう、直近区間に適用された
/// 倍率・理由（[RewardSegmentReason]）を表示する。
class OpeningPointDebugPanel extends StatelessWidget {
  const OpeningPointDebugPanel({super.key, required this.stats});

  /// composition root（`TerrainYieldPipeline`）が公開する観測データ。
  final ValueListenable<OpeningPointPipelineStats> stats;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: ValueListenableBuilder<OpeningPointPipelineStats>(
            valueListenable: stats,
            builder: (context, value, _) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '開放ポイント デバッグパネル（デバッグビルドのみ表示・Issue #143）',
                    style: textTheme.labelMedium,
                  ),
                  Text(
                    '換算レート 1.5km=1P（2026-09-12代表決定）。仮値ではなく確定値だが、'
                    '正本は balance.csv（Issue #36・未作成）。自然回復（1P/日）は'
                    'MVPでは未実装（壁時計を使わない方針のため。docs/opening_points.md §2.1）',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '所持ポイント: ${value.points} / $openingPointStockCap'
                    '（次の1Pまで ${_progressPercent(value)}%）',
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    'ウォーターマーク(行id): ${value.watermarkRowId}',
                    style: textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '直近区間: 距離 ${_distanceLabel(value.lastSegmentDistanceMeters)} / '
                    '倍率 ${_multiplierLabel(value.lastAppliedMultiplier)} / '
                    '理由 ${_reasonLabel(value.lastReason)}',
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

  int _progressPercent(OpeningPointPipelineStats value) {
    return ((value.remainderMillimeters / openingPointDistanceMillimetersPerPoint) * 100)
        .floor();
  }

  static String _distanceLabel(double? distanceMeters) =>
      distanceMeters == null ? '-' : '${distanceMeters.toStringAsFixed(1)}m';

  static String _multiplierLabel(double? multiplier) =>
      multiplier == null ? '-' : multiplier.toStringAsFixed(2);

  static String _reasonLabel(RewardSegmentReason? reason) => switch (reason) {
        null => '-',
        RewardSegmentReason.none => '不一致なし（満額）',
        RewardSegmentReason.mockSuspected => 'モック位置の疑い（倍率0）',
        RewardSegmentReason.overSpeed => '速度超過（倍率0）',
        RewardSegmentReason.stepMismatch => '歩数不一致（倍率低下）',
      };
}
