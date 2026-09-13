import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';

import '../../../design/spacing.dart';
import '../../../map/economy/terrain_yield_pipeline.dart';

/// タップしたヘクスを開放ポイントで開放するための最小限のUI（Issue #151・T064）。
///
/// ## なぜモーダルボトムシートか（#137/#138/#141/#142 の再発防止）
/// これまで4回、新設したUI要素が既存の製品ボタン（追従・記録開始・HUD等・
/// `map_screen.dart` 各所のコメント「配置」参照）を覆う不具合を繰り返してきた。
/// 本UIはタップしたときだけ現れ、閉じれば何も残らない一過性のUI
/// （モーダルボトムシート）にすることで、**常時表示の固定位置UI要素を
/// 増やさない**——構造的にこの種の不具合を起こしえない設計にした（PR本文にも
/// 記載する）。
///
/// ## 演出は最小限（Issue #151 提案内容4「凝った演出は不要」）
/// 地形タイプ・開放可否・不可の理由（残高不足／隣接していない／開示済み／
/// パック範囲外）をテキスト＋アイコンで示すだけ。DESIGN.md「色だけで情報を
/// 伝えない」に従い、拒否理由は `error` トークンの色に加えて必ず文言でも示す。
///
/// ## 判定の二段構え（プレビューと確定は別物）
/// [evaluation] はシートを開いた時点のプレビュー（表示用）でしかない。実際の
/// 可否の最終確認・DB書き込みは [onConfirm]（`TerrainYieldPipeline.openHexWithPoints`）
/// が呼ぶ側でトランザクション内で再確認する（`HexOpeningSpendService` クラスdoc
/// 「責務の境界」参照）。そのため、開いてから確定するまでの間に他の経路
/// （歩行・別の消費操作）で状態が変わっていても、[onConfirm] の結果
/// （[HexOpeningAttemptResult]）が正しい最終結果を返す。
///
/// ## 「閉じる」で確定結果を呼び出し元へ返す（Issue #159・advisor指摘）
/// 名所の収集通知（SnackBar）は本シートが表示されている間に出しても
/// モーダルの背面に隠れて利用者に見えない（DESIGN.md の「地図画面で収集時に
/// 名所名が表示される」を実質満たせない）。そのため本シートは「閉じる」が
/// 押された時点の [HexOpeningAttemptResult] を `Navigator.pop` の戻り値として
/// 返し、呼び出し側（`map_screen.dart` の `_handleFogHexTapped`）が
/// `showModalBottomSheet` の `Future` が完了した**後**（＝シートが完全に
/// 閉じた後）にSnackBarを表示する。
class HexOpeningSheet extends StatefulWidget {
  const HexOpeningSheet({
    super.key,
    required this.evaluation,
    required this.currentPoints,
    required this.onConfirm,
  });

  /// シートを開いた時点の判定（`evaluateHexOpening`・プレビュー表示専用）。
  final HexOpeningEvaluation evaluation;

  /// シートを開いた時点の所持ポイント（プレビュー表示専用）。
  final int currentPoints;

  /// 「開放する」を押した際に呼ぶ（`TerrainYieldPipeline.openHexWithPoints`）。
  final Future<HexOpeningAttemptResult> Function() onConfirm;

  @override
  State<HexOpeningSheet> createState() => _HexOpeningSheetState();
}

enum _SheetPhase { preview, confirming, done }

class _HexOpeningSheetState extends State<HexOpeningSheet> {
  _SheetPhase _phase = _SheetPhase.preview;
  HexOpeningAttemptResult? _result;

  Future<void> _handleConfirm() async {
    setState(() => _phase = _SheetPhase.confirming);
    final result = await widget.onConfirm();
    if (!mounted) return;
    setState(() {
      _result = result;
      _phase = _SheetPhase.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.terrain, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(_terrainLabel(widget.evaluation.terrainType), style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _buildBody(theme, textTheme),
            const SizedBox(height: AppSpacing.md),
            SizedBox(width: double.infinity, child: _buildActionButton(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, TextTheme textTheme) {
    if (_phase == _SheetPhase.done) {
      final result = _result!;
      if (result.success) {
        return Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            const Expanded(child: Text('開放しました')),
          ],
        );
      }
      return _denialRow(theme, textTheme, result.denialReason);
    }

    if (widget.evaluation.canOpen) {
      return Text('所持ポイント ${widget.currentPoints}P（コスト1P）', style: textTheme.bodyMedium);
    }

    return _denialRow(theme, textTheme, widget.evaluation.denialReason);
  }

  Widget _denialRow(ThemeData theme, TextTheme textTheme, HexOpeningDenialReason? reason) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            _denialMessage(reason),
            style: textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (_phase == _SheetPhase.done) {
      return OutlinedButton(
        // クラスdoc「『閉じる』で確定結果を呼び出し元へ返す」参照。
        onPressed: () => Navigator.of(context).pop(_result),
        child: const Text('閉じる'),
      );
    }
    final confirming = _phase == _SheetPhase.confirming;
    return FilledButton(
      onPressed: (confirming || !widget.evaluation.canOpen) ? null : _handleConfirm,
      child: confirming
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('開放ポイントを1P使って開放する'),
    );
  }

  /// `terrain_yield_debug_panel.dart` の `_terrainLabel` と同じラベル方針
  /// （地形タイプごとの日本語名）。
  static String _terrainLabel(TerrainType? terrainType) => switch (terrainType) {
        null => '不明な場所（地域パック範囲外）',
        TerrainType.vacantLot => '空き地',
        TerrainType.forest => '森',
        TerrainType.mountain => '山',
        TerrainType.waterside => '水辺',
        TerrainType.sea => '海',
      };

  static String _denialMessage(HexOpeningDenialReason? reason) => switch (reason) {
        null => '開放できません',
        HexOpeningDenialReason.outsidePack => 'この場所は地域パックの範囲外です',
        HexOpeningDenialReason.alreadyDisclosed => 'このヘクスは既に開示済みです',
        HexOpeningDenialReason.notAdjacentToDisclosed =>
          '開示済みのヘクスに隣接していません（隣接する場所からのみ開放できます）',
        HexOpeningDenialReason.insufficientPoints => '開放ポイントが足りません（コスト1P）',
      };
}
