import 'dart:async';

import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';

/// 位置記録（Kotlin foreground service・PR #128）の起動・停止・状態と、
/// `NativePositionProvider` が実際に読み取った [GeoPosition] を代表・秘書セッションが
/// 実機で確認するためのデバッグ専用パネル（Issue #124・T049・T050）。
///
/// 【製品UIを汚さない】`fog_of_war_debug_panel.dart` と同じ方針で、
/// `app/lib/features/map/map_screen.dart` から `kDebugMode` 配下でのみ組み込まれる
/// （release ビルドには一切現れない）。
///
/// 【本パネルが確認できること（秘書セッションの実機確認手順・PR本文参照）】
/// - 「起動」ボタン: Pigeon の `startTracking()` を呼ぶ。権限が無い場合は
///   `TrackingStartOutcome.permissionDenied` が返り、アプリはクラッシュしない
///   （`LocationTrackingService.Companion.start()` が権限を確認してから
///   `startForegroundService()` を呼ぶ実装。PR #130・`LocationApiHandler.kt`
///   のドキュメント参照。既存の adb debug Intent 経由の起動も同じ `Companion.start()`
///   を経由するため同様にクラッシュしないが、**Pigeon 経由でのこの組み合わせの
///   動作は実機未確認**であり、本パネルはその確認のために存在する）。
/// - 「停止」ボタン: Pigeon の `stopTracking()` を呼ぶ。
/// - 「状態確認」ボタン: `getTrackingStatus()` を呼び、稼働中か・`session_id` を表示する。
/// - 位置ログ: `NativePositionProvider.positionUpdates` を購読し、
///   Kotlin が `location_track.sqlite` に書いた行を Dart 側が実際に読めていること
///   （緯度経度・`trackingSessionId`・`spoofSuspected`）を直接確認できる。
class LocationTrackingDebugPanel extends StatefulWidget {
  const LocationTrackingDebugPanel({
    super.key,
    this.control,
    this.positionProvider,
  });

  /// テスト用の差し替えフック（既定 null では実際の Pigeon 経路を使う）。
  final NativeLocationTrackingControl? control;

  /// テスト用の差し替えフック（既定 null では実際の `location_track.sqlite` を読む）。
  final PositionProvider? positionProvider;

  /// パネルに保持する直近の位置ログの最大件数（無限に溜め込まない）。
  static const maxLoggedPositions = 20;

  @override
  State<LocationTrackingDebugPanel> createState() => _LocationTrackingDebugPanelState();
}

class _LocationTrackingDebugPanelState extends State<LocationTrackingDebugPanel> {
  late final NativeLocationTrackingControl _control =
      widget.control ?? NativeLocationTrackingControl();
  late final PositionProvider _positionProvider =
      widget.positionProvider ?? NativePositionProvider();

  TrackingStatus? _status;
  String? _lastActionResult;
  final List<GeoPosition> _loggedPositions = [];

  @override
  void initState() {
    super.initState();
    _positionProvider.positionUpdates.listen((position) {
      if (!mounted) return;
      setState(() {
        _loggedPositions.insert(0, position);
        if (_loggedPositions.length > LocationTrackingDebugPanel.maxLoggedPositions) {
          _loggedPositions.removeLast();
        }
      });
    });
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    // NativePositionProvider を自前で生成した場合のみリソースを解放する
    // （widget.positionProvider 差し替え時はテスト側が所有権を持つため触らない）。
    final provider = _positionProvider;
    if (widget.positionProvider == null && provider is NativePositionProvider) {
      unawaited(provider.close());
    }
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final status = await _control.status();
    if (!mounted) return;
    setState(() => _status = status);
  }

  Future<void> _start() async {
    final result = await _control.start();
    if (!mounted) return;
    setState(() {
      _lastActionResult = switch (result.outcome) {
        TrackingStartOutcome.started => '起動要求を送信しました（稼働中かは状態確認で確認）',
        TrackingStartOutcome.permissionDenied => '権限が無いため起動しませんでした（想定どおり。'
            'クラッシュしていなければ問題1は解消済み）',
      };
    });
    await _refreshStatus();
  }

  Future<void> _stop() async {
    await _control.stop();
    _lastActionResult = null;
    await _refreshStatus();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final status = _status;
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
                '位置記録 デバッグパネル（デバッグビルドのみ表示・Issue #124）',
                style: textTheme.labelMedium,
              ),
              Text(
                status == null
                    ? '状態: 未確認'
                    : '状態: ${status.isRunning ? "稼働中" : "停止中"}'
                        '${status.sessionId != null ? " (session=${status.sessionId})" : ""}',
                style: textTheme.bodySmall,
              ),
              if (_lastActionResult != null)
                Text(_lastActionResult!, style: textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  FilledButton(onPressed: _start, child: const Text('起動')),
                  OutlinedButton(onPressed: _stop, child: const Text('停止')),
                  OutlinedButton(onPressed: _refreshStatus, child: const Text('状態確認')),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '受信した位置（location_track.sqlite・直近${_loggedPositions.length}件）:',
                style: textTheme.bodySmall,
              ),
              if (_loggedPositions.isEmpty)
                Text('まだありません', style: textTheme.bodySmall)
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _loggedPositions.length,
                    itemBuilder: (context, index) {
                      final position = _loggedPositions[index];
                      return Text(
                        '(${position.latitude.toStringAsFixed(6)}, '
                        '${position.longitude.toStringAsFixed(6)}) '
                        'session=${position.trackingSessionId} '
                        'spoofSuspected=${position.spoofSuspected}',
                        style: textTheme.bodySmall,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
