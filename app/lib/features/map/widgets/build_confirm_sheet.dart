import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../../design/spacing.dart';

/// タップしたヘクスに建物を建てるための確認シート（Issue #192・T089）。
///
/// `hex_opening_sheet.dart`（[HexOpeningSheet]）と同じ「モーダルボトムシートで
/// 一過性のUIにする」設計を踏襲する（クラスdoc「なぜモーダルボトムシートか」の
/// 理由——常時表示の固定位置UI要素を増やさないことで、既存の製品ボタンを覆う
/// 不具合の再発を防ぐ）。
///
/// ## 判定の二段構え（[HexOpeningSheet] と同じ）
/// [evaluation] はシートを開いた時点のプレビュー（`BuildableHexEvaluator` による
/// 表示用の判定）でしかない。実際の可否の最終確認・DB書き込みは [onConfirm]
/// （`BuildingConstructionService.build`）がトランザクション内で再確認する。
/// 開いてから確定するまでの間に状況が変わっていても、[onConfirm] の結果
/// （[BuildResult]）が正しい最終結果を返す。
class BuildConfirmSheet extends StatefulWidget {
  const BuildConfirmSheet({
    super.key,
    required this.buildingLabel,
    required this.terrainType,
    required this.evaluation,
    required this.onConfirm,
  });

  /// 建てようとしている建物の日本語ラベル（`build_screen.dart` の
  /// `BuildingSpec.label` をそのまま渡す）。
  final String buildingLabel;

  /// タップしたマスの地形タイプ（未開示・パック範囲外の場合は null）。
  final TerrainType? terrainType;

  /// シートを開いた時点の判定（`BuildableHexEvaluator.evaluateOne`・プレビュー表示専用）。
  final BuildEvaluation evaluation;

  /// 「建てる」を押した際に呼ぶ（`BuildingConstructionService.build`）。
  final Future<BuildResult> Function() onConfirm;

  @override
  State<BuildConfirmSheet> createState() => _BuildConfirmSheetState();
}

enum _SheetPhase { preview, confirming, done }

class _BuildConfirmSheetState extends State<BuildConfirmSheet> {
  _SheetPhase _phase = _SheetPhase.preview;
  BuildResult? _result;

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
                Icon(Icons.construction, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${widget.buildingLabel}を建てる',
                    style: textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(_terrainLabel(widget.terrainType), style: textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            _buildBody(theme, textTheme),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: _buildActionButton(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, TextTheme textTheme) {
    if (_phase == _SheetPhase.done) {
      final result = _result!;
      if (result.outcome == BuildOutcome.built) {
        return Row(
          children: [
            Icon(Icons.check_circle, color: theme.colorScheme.primary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: Text('${widget.buildingLabel}を建てました')),
          ],
        );
      }
      return _denialRow(
        theme,
        textTheme,
        result.denialReason,
        result.missingResources,
      );
    }

    if (widget.evaluation.canBuild) {
      return const Text('この場所に建てます。');
    }

    return _denialRow(
      theme,
      textTheme,
      widget.evaluation.denialReason,
      widget.evaluation.missingResources,
    );
  }

  Widget _denialRow(
    ThemeData theme,
    TextTheme textTheme,
    BuildDenialReason? reason,
    Map<Resource, int> missingResources,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            _denialMessage(reason, missingResources),
            style: textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context) {
    if (_phase == _SheetPhase.done) {
      return OutlinedButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('閉じる'),
      );
    }
    final confirming = _phase == _SheetPhase.confirming;
    return FilledButton(
      onPressed: (confirming || !widget.evaluation.canBuild)
          ? null
          : _handleConfirm,
      child: confirming
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('建てる'),
    );
  }

  /// `hex_opening_sheet.dart` の `_terrainLabel` と同じラベル方針。
  static String _terrainLabel(TerrainType? terrainType) =>
      switch (terrainType) {
        null => '未開示の場所',
        TerrainType.vacantLot => '空き地',
        TerrainType.forest => '森',
        TerrainType.mountain => '山',
        TerrainType.waterside => '水辺',
        TerrainType.sea => '海',
      };

  static String _denialMessage(
    BuildDenialReason? reason,
    Map<Resource, int> missingResources,
  ) => switch (reason) {
    null => '建てられません',
    BuildDenialReason.notDisclosed => 'このマスはまだ開示されていません',
    BuildDenialReason.notVacantLot => '空き地ではないため建てられません',
    BuildDenialReason.alreadyBuilt => 'すでに建物が建っています',
    BuildDenialReason.notAdjacentToSea => '海に隣接する空き地にのみ建てられます',
    BuildDenialReason.notAdjacentToResidential => '住宅・マンションに隣接する空き地にのみ建てられます',
    BuildDenialReason.insufficientResources =>
      '資材が足りません（不足: ${_missingResourcesLabel(missingResources)}）',
  };

  static String _missingResourcesLabel(Map<Resource, int> missing) {
    final labels = {
      Resource.wood: '木',
      Resource.stone: '石',
      Resource.iron: '鉄',
    };
    return [
      for (final resource in const [
        Resource.wood,
        Resource.stone,
        Resource.iron,
      ])
        if (missing[resource] != null)
          '${labels[resource]}${missing[resource]}',
    ].join(' / ');
  }
}
