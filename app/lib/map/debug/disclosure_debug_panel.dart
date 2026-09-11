import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import 'nearest_pack_hex.dart';

/// 「地図の中心のヘクスを開示」デバッグ専用パネル（`kDebugMode` 限定・Issue #137）。
///
/// ## なぜ必要か（Issue #137 本文より）
/// 代表の端末（Pixel 7a）の現在地は地域パック（狭山湖周辺）の範囲外にあるため、
/// 実機で位置を受信しても `RegionPack.terrainOf` が null になり、実際に歩いても
/// 開示は起きない（これは正しい挙動であり不具合ではない）。実機で配線全体
/// （位置→開示判定→保存→霧の解除、および再起動後の復元）を確認するための
/// 観測点として、地図の中心に最も近いパック内ヘクスを選び、本番と全く同じ経路
/// （[recordManualPosition] → `DisclosureService.recordPosition`）に通す。
///
/// 【本番と同じ経路であることの意味】ここで開示したヘクスは `disclosed_hex`
/// テーブルに実際に保存され、アプリを再起動しても霧が晴れたまま残る
/// （`disclosure_restore.dart` の復元経路をそのまま通るため）。
///
/// ## 2026-09-11（Issue #138）: `DisclosureCoordinator` への直接依存をやめた
/// 以前は `DisclosureCoordinator.recordManualPosition` を直接呼んでいたが、
/// composition root（`map_screen.dart`）が地形産出パイプライン
/// （`TerrainYieldPipeline`）に置き換わったことに伴い、本パネルは具象クラスに
/// 依存せず [recordManualPosition] というコールバックのみを受け取るようにした。
/// **呼び出し側は `TerrainYieldPipeline.recordManualPosition` を渡すこと**
/// （こちらは新規開示時に地形カウンタ（[TerrainHexCounter]）も更新するため、
/// このボタンで開示したヘクスも「地形別件数」・地形産出の対象に正しく含まれる。
/// 単純な `DisclosureService.recordPosition` を渡すとカウンタが更新されず、
/// 代表の端末〔パック範囲外〕での実機確認時に地形産出が一切進まないように
/// 見えてしまう）。
class DisclosureDebugPanel extends StatefulWidget {
  const DisclosureDebugPanel({
    super.key,
    required this.recordManualPosition,
    required this.fogHexFeatureCollection,
    required this.cameraReader,
  });

  /// 本番と同じ経路（開示判定→保存→霧の解除、および地形カウンタの更新）を通す
  /// コールバック。クラスdoc「`DisclosureCoordinator` への直接依存をやめた」参照。
  final Future<DisclosedHex?> Function(GeoPosition position) recordManualPosition;

  /// 地図に表示中の実ヘクスの GeoJSON FeatureCollection
  /// （`buildFogHexFeatureCollectionFromRegionPack` の戻り値）。
  final Map<String, dynamic> fogHexFeatureCollection;

  /// 地図のカメラ中心を読み取るための窓口（`MapView.onMapControllerReady`）。
  final MapCameraReader cameraReader;

  @override
  State<DisclosureDebugPanel> createState() => _DisclosureDebugPanelState();
}

class _DisclosureDebugPanelState extends State<DisclosureDebugPanel> {
  bool _running = false;
  String? _result;

  Future<void> _revealMapCenterHex() async {
    setState(() {
      _running = true;
      _result = null;
    });
    try {
      final center = widget.cameraReader.center;
      if (center == null) {
        setState(() => _result = 'カメラ中心が未取得です（地図の初期化直後の可能性。少し待って再度お試しください）');
        return;
      }

      final nearest = findNearestPackHex(
        widget.fogHexFeatureCollection,
        latitude: center.latitude,
        longitude: center.longitude,
      );
      if (nearest == null) {
        setState(() => _result = '地域パックにヘクスがありません');
        return;
      }

      final position = GeoPosition(
        latitude: nearest.latitude,
        longitude: nearest.longitude,
        timestamp: DateTime.now(),
        hexId: HexId(nearest.hexId),
        spoofSuspected: false,
      );
      final disclosed = await widget.recordManualPosition(position);

      setState(() {
        _result = disclosed == null
            ? 'このヘクス（hexId=${nearest.hexId}）は既に開示済みです'
            : '開示しました: hexId=${nearest.hexId} featureId=${nearest.featureId} '
                '地形=${disclosed.terrainType.name}\n'
                '（アプリを完全終了して再起動しても霧が晴れたままか確認してください）';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = '失敗しました: $e');
    } finally {
      if (mounted) setState(() => _running = false);
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
                '開示 デバッグパネル（デバッグビルドのみ表示・Issue #137）',
                style: textTheme.labelMedium,
              ),
              Text(
                '現在地がパック範囲外でも確認できるよう、地図中心のヘクスを本番と同じ'
                '経路（保存・霧の解除まで）で開示します。',
                style: textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              FilledButton(
                onPressed: _running ? null : _revealMapCenterHex,
                child: Text(_running ? '処理中…' : '地図の中心のヘクスを開示'),
              ),
              if (_result != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(_result!, style: textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
