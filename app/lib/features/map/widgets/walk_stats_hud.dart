import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';

import '../../../design/spacing.dart';
import '../../../map/economy/terrain_yield_pipeline.dart';

/// マップ画面に重ねる「歩行距離・歩数・開放ポイント」の HUD（Issue #149・T062）。
///
/// `specs/001-mvp/tasks.md` T062「歩行距離・歩数の表示（HUD）」の実装本体。
/// [TrackingControlButton]（Issue #142）・[CurrentLocationFollowButton]
/// （Issue #141）と同じく **release ビルドでも常に表示する製品UI**。
///
/// ## `OpeningPointDebugPanel`（`kDebugMode` 限定）とは別物・併存させる
/// 表示内容は一部重なる（所持ポイント等）が、あちらは代表・秘書が実機検証で
/// 使う詳細診断パネル、本ウィジェットは利用者向けの簡潔な要約であり、役割が
/// 異なるため置き換えはしない。
///
/// ## 位置ストリームへの2つ目のリスナーを追加しない（Issue #149 提案内容2）
/// `NativePositionProvider.recordedPositionUpdates` を直接購読せず、
/// [TerrainYieldPipeline] が唯一の購読者として計算した結果を公開する
/// [ValueListenable]（[openingPointStats]。`stats`・`currentPosition` と同じ
/// 配線方式）を受け取るだけ。
///
/// ## 距離計算を新規に実装しない（Issue #149 提案内容3・受け入れ基準）
/// 「今回の記録での歩行距離」は
/// [OpeningPointPipelineStats.sessionDistanceMeters]
/// （`OpeningPointAccrualCoordinator` が `RewardPolicy.classify` の結果
/// 〔`RewardSegment.distanceMeters`・Issue #143 で公開済み〕をセッション単位で
/// 積算した値）をそのまま表示するだけで、本ウィジェットが独自に距離を計算する
/// ことは無い。
///
/// ## 歩数が取得できない場合は歩数欄自体を出さない（Issue #149 受け入れ基準）
/// [OpeningPointPipelineStats.sessionHasStepData] が false（今回の記録で一度も
/// [GeoPosition.cumulativeStepCount] が非null値を取れていない＝センサー無し・
/// 権限無し・未取得）の間は歩数の行そのものを表示しない。「0歩」と表示すると
/// 壊れているように見えるため、欄を消す方を選んだ（Issue #135 と同じ
/// 「罰しない」配慮）。
///
/// ## 記録停止中の表示（Issue #149 受け入れ基準）
/// [isRecording] は [TrackingControlButton.recordingNotifier] から受け取る
/// （こちらも位置ストリームとは無関係の別経路であり、「2つ目のリスナー」には
/// 当たらない）。false の間は「記録は停止中です」を表示する。
///
/// ## 直近区間が報酬対象外・報酬減額だった場合の表示（Issue #149 提案内容6）
/// DESIGN.md「偽装検出時のユーザー通知は『罰しない』トーン」に従い、
/// [RewardSegmentReason.mockSuspected]・[RewardSegmentReason.overSpeed]（倍率0）
/// の場合は「この区間は報酬対象外です」、[RewardSegmentReason.stepMismatch]
/// （倍率0<x<1）の場合は「この区間は報酬が少なめです」と表示する。どちらも
/// 利用者を非難する文言にしない。`error` トークン（`theme.colorScheme.error`）を
/// 色として使うが、文言自体は中立に保つ。
///
/// ## 配置（Issue #149 提案内容4・#137/#138/#141/#142 の再発防止）
/// 呼び出し側（`map_screen.dart`）が画面**上部**に配置する。既存の製品UI
/// （下中央=記録開始/記録中ボタン・右下=追従ボタン）とは重ならない。本ウィジェット
/// 自体は内容量に応じた幅で左寄せに描画され、画面右端までは伸びない
/// （`Card` を `Row`〔`mainAxisSize: MainAxisSize.min`〕主体で組んでいるため）。
class WalkStatsHud extends StatelessWidget {
  const WalkStatsHud({
    super.key,
    required this.openingPointStats,
    required this.isRecording,
  });

  /// [TerrainYieldPipeline.openingPointStats]（composition root が公開する
  /// 唯一の観測用 [ValueListenable]）。
  final ValueListenable<OpeningPointPipelineStats> openingPointStats;

  /// 記録中かどうか（[TrackingControlButton.recordingNotifier] が公開する状態）。
  final ValueListenable<bool> isRecording;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isRecording,
      builder: (context, recording, _) {
        return ValueListenableBuilder<OpeningPointPipelineStats>(
          valueListenable: openingPointStats,
          builder: (context, stats, _) {
            return _WalkStatsHudCard(isRecording: recording, stats: stats);
          },
        );
      },
    );
  }
}

class _WalkStatsHudCard extends StatelessWidget {
  const _WalkStatsHudCard({required this.isRecording, required this.stats});

  final bool isRecording;
  final OpeningPointPipelineStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final exclusionMessage = _exclusionMessage(stats.lastReason);

    return Semantics(
      container: true,
      label: _semanticsSummary(),
      child: Card(
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.route, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _distanceLabel(stats.sessionDistanceMeters),
                    style: textTheme.titleMedium,
                  ),
                  if (stats.sessionHasStepData) ...[
                    const SizedBox(width: AppSpacing.md),
                    Icon(
                      Icons.directions_walk,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text('${stats.sessionStepCount}歩', style: textTheme.titleMedium),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.stars, size: 16, color: theme.colorScheme.tertiary),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '開放ポイント ${stats.points}/$openingPointStockCap'
                    '（次の1Pまで${_progressPercent(stats)}%）',
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
              if (!isRecording) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '記録は停止中です',
                  style: textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (exclusionMessage != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: theme.colorScheme.error),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        exclusionMessage,
                        style: textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _semanticsSummary() {
    final buffer = StringBuffer()
      ..write('歩行距離 ${_distanceLabel(stats.sessionDistanceMeters)}');
    if (stats.sessionHasStepData) {
      buffer.write('、歩数 ${stats.sessionStepCount}歩');
    }
    buffer.write('、開放ポイント ${stats.points}/$openingPointStockCap');
    if (!isRecording) {
      buffer.write('、記録は停止中です');
    }
    final exclusionMessage = _exclusionMessage(stats.lastReason);
    if (exclusionMessage != null) {
      buffer.write('、$exclusionMessage');
    }
    return buffer.toString();
  }

  static int _progressPercent(OpeningPointPipelineStats stats) {
    return ((stats.remainderMillimeters / openingPointDistanceMillimetersPerPoint) * 100)
        .floor();
  }

  static String _distanceLabel(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(2)}km';
    }
    return '${meters.toStringAsFixed(0)}m';
  }

  /// DESIGN.md「偽装検出時のユーザー通知は『罰しない』トーン」に従った文言。
  /// クラスdoc「直近区間が報酬対象外・報酬減額だった場合の表示」参照。
  static String? _exclusionMessage(RewardSegmentReason? reason) {
    switch (reason) {
      case null:
      case RewardSegmentReason.none:
        return null;
      case RewardSegmentReason.mockSuspected:
      case RewardSegmentReason.overSpeed:
        return 'この区間は報酬対象外です';
      case RewardSegmentReason.stepMismatch:
        return 'この区間は報酬が少なめです';
    }
  }
}
