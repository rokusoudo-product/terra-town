import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import 'fog_debug_hex_grid.dart';

/// fog of war の描画・トグルを代表が実機で確認するためのデバッグ専用パネル
/// （Issue #100 の受け入れ基準「代表が実機で確認するための手順」に対応）。
///
/// 【製品UIを汚さない】`app/lib/features/map/map_screen.dart` から
/// `kDebugMode`（`package:flutter/foundation.dart`）配下でのみ組み込まれるため、
/// release ビルドには一切現れない（`flutter build apk --debug` でのみ見える）。
///
/// 【表示するヘクスは合成データ】ここで開示するヘクスは実際の地域パックの
/// ヘクスではない（`fog_debug_hex_grid.dart` 冒頭コメント参照）。あくまで
/// 「feature-state のトグルで実際に霧が晴れて見えるか」の確認が目的であり、
/// 開示判定ロジック（T054）・永続化（T060）とは無関係の使い捨て操作である
/// （このパネルの操作は `disclosed_hex` に一切書き込まない）。
class FogOfWarDebugPanel extends StatefulWidget {
  const FogOfWarDebugPanel({super.key, required this.controller});

  final FogOfWarController controller;

  /// デモ用の合成ヘクス数。[fog_debug_hex_grid.buildSyntheticFogHexFeatureCollection]
  /// の既定 `firstFeatureId=0` と対応する連番 `0..demoHexCount-1` を使う。
  static const demoHexCount = 61;

  /// 本番パックの実測ヘクス数（tasks.md T044・2026-09-10 実測）。
  static const productionHexCount = 13106;

  /// 計測用グリッドの feature id は、デモ用グリッド（0〜60）と重複しない範囲を使う。
  static const _benchmarkFirstFeatureId = 1000000;

  @override
  State<FogOfWarDebugPanel> createState() => _FogOfWarDebugPanelState();
}

class _FogOfWarDebugPanelState extends State<FogOfWarDebugPanel> {
  int _nextToReveal = 0;
  bool _benchmarkRunning = false;
  String? _benchmarkResult;

  bool get _allRevealed => _nextToReveal >= FogOfWarDebugPanel.demoHexCount;

  Future<void> _revealNext() async {
    if (_allRevealed) return;
    await widget.controller.revealHex(_nextToReveal);
    if (!mounted) return;
    setState(() => _nextToReveal++);
  }

  Future<void> _revealAll() async {
    for (var id = _nextToReveal; id < FogOfWarDebugPanel.demoHexCount; id++) {
      await widget.controller.revealHex(id);
    }
    if (!mounted) return;
    setState(() => _nextToReveal = FogOfWarDebugPanel.demoHexCount);
  }

  Future<void> _resetFog() async {
    await widget.controller.resetAllForDebug();
    if (!mounted) return;
    setState(() => _nextToReveal = 0);
  }

  /// 受け入れ基準「本番パックのヘクス数（13,106）でのソース構築コストを計測する
  /// 手順」に対応する。表示中のデモ用fogとは独立した一時ソースを追加・計測・
  /// 削除する（デモの霧の見た目には影響しない）。
  ///
  /// 【research.md §6.4「2026-09-09 追加計測」との比較について】同節の「⑤合計」は
  /// ①geometry生成 + ②addGeoJsonSource + ③addLayer + ④ソース追加後2000msの
  /// 観測窓中のmaxFrame（フレームジャンク計測）の4項目の和である。本メソッドは
  /// ①〜③のみを計測し、④（フレーム統計）は計測しない（本デバッグパネルは
  /// 簡易なStopwatch計測に留め、専用のフレーム統計ハーネスは持たないため）。
  /// そのため、ここで表示する「合計」は research.md の「合計約1.5秒」より
  /// 小さく出る可能性がある。厳密な比較をする場合はこの差を考慮すること。
  Future<void> _runProductionScaleBenchmark() async {
    setState(() {
      _benchmarkRunning = true;
      _benchmarkResult = null;
    });
    try {
      final geometryStopwatch = Stopwatch()..start();
      final geojson = buildSyntheticFogHexFeatureCollection(
        centerLat: 35.79000,
        centerLon: 139.38000,
        count: FogOfWarDebugPanel.productionHexCount,
        firstFeatureId: FogOfWarDebugPanel._benchmarkFirstFeatureId,
      );
      geometryStopwatch.stop();

      final sourceStopwatch = Stopwatch()..start();
      await widget.controller.installBenchmarkSourceForDebug(geojson);
      sourceStopwatch.stop();

      final layerStopwatch = Stopwatch()..start();
      await widget.controller.installBenchmarkLayerForDebug();
      layerStopwatch.stop();

      final geometryMs = geometryStopwatch.elapsedMilliseconds;
      final sourceMs = sourceStopwatch.elapsedMilliseconds;
      final layerMs = layerStopwatch.elapsedMilliseconds;
      final totalMs = geometryMs + sourceMs + layerMs;

      await widget.controller.removeBenchmarkSourceForDebug();

      if (!mounted) return;
      setState(() {
        _benchmarkResult =
            'ヘクス数 ${FogOfWarDebugPanel.productionHexCount} 件: '
            'geometry ${geometryMs}ms / addGeoJsonSource ${sourceMs}ms / '
            'addLayer ${layerMs}ms / 合計(①〜③) ${totalMs}ms\n'
            '(plan.md §8 基準: ソース構築2秒以内。'
            'research.md §6.4の「合計」はフレーム統計④も含むため、'
            'この値はそれよりやや小さく出うる)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _benchmarkResult = '計測に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _benchmarkRunning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: Card(
        margin: const EdgeInsets.all(AppSpacing.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'フォグ デバッグパネル（デバッグビルドのみ表示）',
                style: textTheme.labelMedium,
              ),
              Text(
                '開示済み: $_nextToReveal / ${FogOfWarDebugPanel.demoHexCount}'
                '（合成データ。実際のヘクスではありません）',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton(
                    onPressed: _allRevealed ? null : _revealNext,
                    child: const Text('1マス開示'),
                  ),
                  OutlinedButton(
                    onPressed: _allRevealed ? null : _revealAll,
                    child: const Text('すべて開示'),
                  ),
                  OutlinedButton(
                    onPressed: _resetFog,
                    child: const Text('霧に戻す'),
                  ),
                  OutlinedButton(
                    onPressed: _benchmarkRunning
                        ? null
                        : _runProductionScaleBenchmark,
                    child: Text(
                      _benchmarkRunning
                          ? '計測中…'
                          : '本番相当(${FogOfWarDebugPanel.productionHexCount}件)'
                                'で計測',
                    ),
                  ),
                ],
              ),
              if (_benchmarkResult != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_benchmarkResult!, style: textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
