import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';

/// fog of war の描画・トグルを代表が実機で確認するためのデバッグ専用パネル
/// （Issue #100 の受け入れ基準「代表が実機で確認するための手順」に対応）。
///
/// 【製品UIを汚さない】`app/lib/features/map/map_screen.dart` から
/// `kDebugMode`（`package:flutter/foundation.dart`）配下でのみ組み込まれるため、
/// release ビルドには一切現れない（`flutter build apk --debug` でのみ見える）。
///
/// 【「1マス開示」「すべて開示」「霧に戻す」は合成データ】ここで開示するヘクスは
/// 実際の地域パックのヘクスではない（`fog_debug_hex_grid.dart` 冒頭コメント参照）。
/// あくまで「feature-state のトグルで実際に霧が晴れて見えるか」の確認が目的であり、
/// 開示判定ロジック（T054）・永続化（T060）とは無関係の使い捨て操作である
/// （このパネルの操作は `disclosed_hex` に一切書き込まない）。
///
/// 【「本番相当…で計測」は実データ（Issue #105 で変更）】この計測ボタンだけは、
/// 同梱地域パック（`region_pack.sqlite`）を実際に読み込み、
/// `buildFogHexFeatureCollectionFromRegionPack`（`terra_town_location`）で
/// 実ヘクス（本番パックなら13,106件）の GeoJSON FeatureCollection を組み立てて
/// 計測する。表示中のデモ用fog（上記の合成データ）とは独立した一時ソースを
/// 追加・計測・削除するため、デモの霧の見た目には影響しない。
class FogOfWarDebugPanel extends StatefulWidget {
  const FogOfWarDebugPanel({
    super.key,
    required this.controller,
    this.resolveRegionPackPath = defaultResolveRegionPackPath,
  });

  final FogOfWarController controller;

  /// 「本番相当…で計測」ボタンが読み込む同梱地域パック（`region_pack.sqlite`）の
  /// ローカルファイルパスを解決する関数。テストでの差し替え用フック（既定は
  /// 実アセットから解決する [defaultResolveRegionPackPath]）。
  final Future<String> Function() resolveRegionPackPath;

  /// デモ用の合成ヘクス数。[fog_debug_hex_grid.buildSyntheticFogHexFeatureCollection]
  /// の既定 `firstFeatureId=0` と対応する連番 `0..demoHexCount-1` を使う。
  static const demoHexCount = 61;

  /// `app/pubspec.yaml` の `flutter.assets`（`assets/pack/`）で宣言済みの
  /// 同梱地域パックのアセットキー（`map_screen.dart` の `mbtilesAssetKey` と対）。
  static const regionPackAssetKey = 'assets/pack/region_pack.sqlite';

  /// 実アセットから解決する既定実装。
  ///
  /// [resolveBundledMbtilesPath] は名前に反して「Flutter アセットバンドルの
  /// 読み取り専用ファイルを、書き込み可能な実ファイルパスへ一度だけコピーする」
  /// という汎用処理である（`mbtiles_asset.dart` の docstring 参照。MBTiles 専用の
  /// ロジックはその後段の `mbtiles://` URL 組み立てのほうにあり、コピー処理自体は
  /// ファイル形式に依存しない）。[RegionPackConnection.open] も `sqlite3` の
  /// 読み取り専用オープンに実ファイルシステム上のパスを要求するため
  /// （アセットバンドルは読み取り専用の仮想ファイルシステム）、`map_screen.dart` の
  /// `mbtilesAssetKey` 解決と同じ関数をそのまま再利用する。
  static Future<String> defaultResolveRegionPackPath() =>
      resolveBundledMbtilesPath(
        assetKey: regionPackAssetKey,
        fileName: 'region_pack.sqlite',
      );

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
  /// 手順」に対応する。**2026-09-10・Issue #105 で実データに変更**: 同梱地域パック
  /// （`region_pack.sqlite`）を実際に読み込み、格納済みのヘクス境界
  /// （`hex_terrain.boundary_geojson`）から実ヘクスの GeoJSON FeatureCollection を
  /// 組み立てて計測する（以前は合成グリッドで代用していた）。表示中のデモ用fogとは
  /// 独立した一時ソースを追加・計測・削除する（デモの霧の見た目には影響しない）。
  ///
  /// 【research.md §6.4「2026-09-09 追加計測」との比較について】同節の「⑤合計」は
  /// ①geometry生成 + ②addGeoJsonSource + ③addLayer + ④ソース追加後2000msの
  /// 観測窓中のmaxFrame（フレームジャンク計測）の4項目の和である。本メソッドは
  /// ①〜③のみを計測し、④（フレーム統計）は計測しない（本デバッグパネルは
  /// 簡易なStopwatch計測に留め、専用のフレーム統計ハーネスは持たないため）。
  /// そのため、ここで表示する「合計」は research.md の「合計約1.5秒」より
  /// 小さく出る可能性がある。厳密な比較をする場合はこの差を考慮すること。
  /// **①は Issue #105 で「procedural生成」から「SQLite読込+GeoJSON組立」に
  /// 変わったため、Issue #100時点の①とは計測対象が異なる**（ディスクI/Oを含む
  /// ぶん、こちらのほうが実態に近い数値になる）。
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
                    child: Text(_benchmarkRunning ? '計測中…' : '本番相当(実データ)で計測'),
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
