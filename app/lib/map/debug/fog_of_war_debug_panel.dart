import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../disclosure/disclosure_restore.dart';
import '../region_pack_asset.dart';

/// fog of war の描画・トグル・復元を代表が実機で確認するためのデバッグ専用パネル
/// （Issue #100・Issue #102・Issue #137）。
///
/// 【製品UIを汚さない】`app/lib/features/map/map_screen.dart` から
/// `kDebugMode`（`package:flutter/foundation.dart`）配下でのみ組み込まれるため、
/// release ビルドには一切現れない（`flutter build apk --debug` でのみ見える）。
///
/// ## 2026-09-11（Issue #137）で「1マス開示」「すべて開示」を削除した理由
/// 地図の fog ソースが実データ（`region_pack.sqlite` の実ヘクス。Issue #137で
/// release ビルドを含む全ビルドへ配線した）に置き換わったため、旧来の合成ヘクス
/// （`fog_debug_hex_grid.dart`・feature id 0〜60 の連番）はもはや同じソース上の
/// 実在の feature id とは一致せず、これらのボタンで `setFeatureState` を呼んでも
/// 画面上に対応するポリゴンが存在しないため何も見えず、確認手段として機能しない。
/// 実ヘクスを対象にした「開示」の確認は、`disclosure_debug_panel.dart`
/// （「地図の中心のヘクスを開示」・本番と同じ経路を通る）に一本化した。
///
/// 「霧に戻す」（[FogOfWarController.resetAllForDebug]）と、新設した
/// 「DBから復元」（[restoreDisclosedHexes]）は残す・追加する。理由:
/// `FogOfWarController.resetAllForDebug`（内部で `removeFeatureState` を呼ぶ）は
/// まさに `setStyle` が霧の状態を失わせるのと同じ種類の状態喪失を模しており、
/// 「霧に戻す→DBから復元」の操作で、Issue #102 が要求する「`setStyle` 後の復元」を
/// 実機で（`setStyle` を実際に呼ばなくても）確認できる唯一の手段になる。
class FogOfWarDebugPanel extends StatefulWidget {
  const FogOfWarDebugPanel({
    super.key,
    required this.controller,
    required this.repository,
    required this.known,
    this.resolveRegionPackPath = defaultResolveRegionPackPath,
  });

  final FogOfWarController controller;

  /// 「DBから復元」ボタンが読み込む、開示済みヘクスの永続化層
  /// （`disclosed_hex` テーブル・Issue #102）。composition root
  /// （`map_screen.dart`）と同じインスタンスを渡すこと。
  final Repository<DisclosedHex, HexId> repository;

  /// composition root と共有する開示済みヘクスの高速判定用インデックス。
  /// 「DBから復元」はこれにも反映する（`restoreDisclosedHexes` 参照）。
  final DisclosedHexSet known;

  /// 「本番相当…で計測」ボタンが読み込む同梱地域パック（`region_pack.sqlite`）の
  /// ローカルファイルパスを解決する関数。テストでの差し替え用フック。
  final Future<String> Function() resolveRegionPackPath;

  @override
  State<FogOfWarDebugPanel> createState() => _FogOfWarDebugPanelState();
}

class _FogOfWarDebugPanelState extends State<FogOfWarDebugPanel> {
  bool _benchmarkRunning = false;
  String? _benchmarkResult;

  bool _restoring = false;
  String? _restoreResult;

  Future<void> _resetFog() async {
    await widget.controller.resetAllForDebug();
    if (!mounted) return;
    setState(() => _restoreResult = null);
  }

  /// 「DBから復元」（Issue #102）: `disclosed_hex` に保存済みの開示ヘクスを
  /// [restoreDisclosedHexes] で読み込み、[widget.known] へ反映しつつ地図の霧を
  /// 解除する。composition root が起動時に行う復元と全く同じ関数を呼ぶ
  /// （`disclosure_restore.dart` クラスdoc参照）。
  Future<void> _restoreFromDatabase() async {
    setState(() {
      _restoring = true;
      _restoreResult = null;
    });
    try {
      final stats = await restoreDisclosedHexes(
        repository: widget.repository,
        known: widget.known,
        reveal: widget.controller.revealHex,
      );
      if (!mounted) return;
      setState(
        () => _restoreResult = '復元しました: ${stats.hexCount}件 / ${stats.elapsedMs}ms',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _restoreResult = '復元に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  /// 受け入れ基準「本番パックのヘクス数（13,106）でのソース構築コストを計測する
  /// 手順」に対応する。同梱地域パック（`region_pack.sqlite`）を実際に読み込み、
  /// 格納済みのヘクス境界（`hex_terrain.boundary_geojson`）から実ヘクスの GeoJSON
  /// FeatureCollection を組み立てて計測する。表示中の本番fogとは独立した
  /// 一時ソースを追加・計測・削除する（表示中の霧の見た目には影響しない）。
  Future<void> _runProductionScaleBenchmark() async {
    setState(() {
      _benchmarkRunning = true;
      _benchmarkResult = null;
    });

    RegionPackConnection? connection;
    try {
      final loadStopwatch = Stopwatch()..start();
      final packPath = await widget.resolveRegionPackPath();
      connection = RegionPackConnection.open(packPath);
      final geojson = buildFogHexFeatureCollectionFromRegionPack(connection);
      loadStopwatch.stop();

      final hexCount = (geojson['features'] as List).length;

      final sourceStopwatch = Stopwatch()..start();
      await widget.controller.installBenchmarkSourceForDebug(geojson);
      sourceStopwatch.stop();

      final layerStopwatch = Stopwatch()..start();
      await widget.controller.installBenchmarkLayerForDebug();
      layerStopwatch.stop();

      final loadMs = loadStopwatch.elapsedMilliseconds;
      final sourceMs = sourceStopwatch.elapsedMilliseconds;
      final layerMs = layerStopwatch.elapsedMilliseconds;
      final totalMs = loadMs + sourceMs + layerMs;

      if (!mounted) return;
      setState(() {
        _benchmarkResult =
            '実データ ヘクス数 $hexCount 件（region_pack.sqlite から読込）: '
            '①パック読込+GeoJSON組立 ${loadMs}ms / ②addGeoJsonSource ${sourceMs}ms / '
            '③addLayer ${layerMs}ms / 合計(①〜③) ${totalMs}ms\n'
            '(plan.md §8 基準: ソース構築2秒以内。'
            'research.md §6.4の「合計」はフレーム統計④も含むため、'
            'この値はそれよりやや小さく出うる。「実機で計測した」という記録ではなく、'
            'この画面を代表が実機で操作した際に表示される値である)';
      });
    } on PackAssetMissingException catch (e) {
      if (!mounted) return;
      setState(() => _benchmarkResult = '地域パックが未取得のため計測できません: $e');
    } on RegionPackMissingHexGeometryException catch (e) {
      if (!mounted) return;
      setState(() => _benchmarkResult = '地域パックにヘクス境界がありません: $e');
    } catch (e) {
      if (!mounted) return;
      setState(() => _benchmarkResult = '計測に失敗しました: $e');
    } finally {
      // ベンチマーク用の一時ソース/レイヤーの後始末は、上のどの段階で失敗しても
      // 必ず試みる（内部で個別に例外を握りつぶす実装のため安全に呼べる。
      // FogOfWarController.removeBenchmarkSourceForDebug の docstring参照）。
      await widget.controller.removeBenchmarkSourceForDebug();
      await connection?.close();
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
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  OutlinedButton(
                    onPressed: _resetFog,
                    child: const Text('霧に戻す（setStyle相当の状態喪失を再現）'),
                  ),
                  OutlinedButton(
                    onPressed: _restoring ? null : _restoreFromDatabase,
                    child: Text(_restoring ? '復元中…' : 'DBから復元'),
                  ),
                  OutlinedButton(
                    onPressed: _benchmarkRunning
                        ? null
                        : _runProductionScaleBenchmark,
                    child: Text(_benchmarkRunning ? '計測中…' : '本番相当(実データ)で計測'),
                  ),
                ],
              ),
              if (_restoreResult != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_restoreResult!, style: textTheme.bodySmall),
              ],
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
