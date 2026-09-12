import 'dart:async';

import 'package:flutter/material.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/color_tokens.dart';
import 'location_permission_gateway.dart';
import 'location_permission_guidance_dialog.dart';

/// 位置記録の開始・停止を行う製品UI（Issue #142・T059）。
///
/// **release ビルドでも常に表示される**（`kDebugMode` 限定の
/// `LocationTrackingDebugPanel` とは異なる。あちらは実機確認用に残す）。
///
/// ## 状態と表示（DESIGN.md「色だけで情報を伝えない」）
/// [FloatingActionButton.extended]（Material 3 標準コンポーネント）を使い、
/// アイコン・ラベル文言・背景色の3つで状態を表す:
///   - 記録中: 停止アイコン＋「記録中」＋ `primary`
///   - 停止中（権限あり/未確認）: 再生アイコン＋「記録開始」＋ `surface`
///   - 停止中（権限拒否/永久拒否）: 権限アイコン＋「権限が必要です」＋ `warning`
///     （DESIGN.md カラートークン表の `warning` 用途「注意（電池・権限）」に対応。
///     `theme.warningColor` 経由で参照する理由は `color_tokens.dart` 参照）
///
/// ## 権限の確認タイミング（Issue #142 提案内容5）
/// 設定画面で後から権限が取り消されうるため、[initState] に加えて
/// [WidgetsBindingObserver.didChangeAppLifecycleState] で `resumed`
/// （端末の設定アプリから本アプリへ戻ってきた場合を含む）のたびに
/// 権限状態・記録状態の両方を再確認する。
///
/// ## 権限のリクエストフロー（受け入れ基準「拒否・永久拒否のそれぞれで適切な案内」）
/// 1. 記録開始をタップ → 権限状態を確認（OSダイアログは出ない）。
/// 2. 許可済みなら即座に記録を開始する。
/// 3. 未確認/拒否（永久拒否ではない）なら [LocationPermissionGateway.request] を呼び、
///    OSの許可ダイアログを表示する。許可されれば記録を開始する。
/// 4. 拒否されたまま（3の結果、または最初から永久拒否）の場合は
///    [showLocationPermissionGuidanceDialog] で「なぜ必要か」を説明し、
///    永久拒否なら設定アプリへの導線、そうでなければ再リクエストの導線を出す。
///
/// ## `ACCESS_BACKGROUND_LOCATION` を要求しない（受け入れ基準）
/// [LocationPermissionGateway]（本番実装は [PermissionHandlerLocationGateway]）が
/// `Permission.locationWhenInUse` のみを扱うため、本ウィジェットは背景位置権限に
/// 一切触れない。
///
/// ## 歩数権限（`ACTIVITY_RECOGNITION`）は要求しない（受け入れ基準）
/// 歩数センサーが無くても記録・産出は動く設計（Issue #126）のため、本ウィジェットは
/// 通知権限（[requestNotificationPermission]。ベストエフォート）以外の追加権限を
/// 記録開始時にリクエストしない。
class TrackingControlButton extends StatefulWidget {
  const TrackingControlButton({
    super.key,
    this.control,
    this.permissionGateway,
    this.requestNotificationPermission,
  });

  /// テスト用の差し替えフック（既定 null では実際の Pigeon 経路を使う）。
  final NativeLocationTrackingControl? control;

  /// テスト用の差し替えフック（既定 null では [PermissionHandlerLocationGateway]）。
  final LocationPermissionGateway? permissionGateway;

  /// テスト用の差し替えフック（既定 null では [requestNotificationPermissionBestEffort]）。
  /// 結果はUIの状態遷移に影響しない（ベストエフォート）。
  final Future<void> Function()? requestNotificationPermission;

  @override
  State<TrackingControlButton> createState() => _TrackingControlButtonState();
}

class _TrackingControlButtonState extends State<TrackingControlButton>
    with WidgetsBindingObserver {
  late final NativeLocationTrackingControl _control =
      widget.control ?? NativeLocationTrackingControl();
  late final LocationPermissionGateway _permissionGateway =
      widget.permissionGateway ?? const PermissionHandlerLocationGateway();
  late final Future<void> Function() _requestNotificationPermission =
      widget.requestNotificationPermission ??
          requestNotificationPermissionBestEffort;

  bool _isRunning = false;
  LocationPermissionState _permissionState = LocationPermissionState.denied;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 端末の設定アプリから戻ってきた場合を含め、フォアグラウンド復帰のたびに
    // 権限・記録状態を再確認する（Issue #142 提案内容5）。
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final trackingStatus = await _control.status();
    final permissionState = await _permissionGateway.status();
    if (!mounted) return;
    setState(() {
      _isRunning = trackingStatus.isRunning;
      _permissionState = permissionState;
    });
  }

  Future<void> _onPressed() async {
    if (_busy) return;
    if (_isRunning) {
      await _stop();
      return;
    }
    await _startFlow();
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    await _control.stop();
    final trackingStatus = await _control.status();
    if (!mounted) return;
    setState(() {
      _isRunning = trackingStatus.isRunning;
      _busy = false;
    });
  }

  Future<void> _startFlow() async {
    setState(() => _busy = true);
    final currentState = await _permissionGateway.status();
    if (!mounted) return;
    setState(() => _permissionState = currentState);

    switch (currentState) {
      case LocationPermissionState.granted:
        await _startTracking();
        return;
      case LocationPermissionState.permanentlyDenied:
        setState(() => _busy = false);
        await _showGuidance(currentState);
        return;
      case LocationPermissionState.denied:
        final requested = await _permissionGateway.request();
        if (!mounted) return;
        setState(() => _permissionState = requested);
        if (requested == LocationPermissionState.granted) {
          await _startTracking();
        } else {
          setState(() => _busy = false);
          await _showGuidance(requested);
        }
        return;
    }
  }

  Future<void> _startTracking() async {
    // 通知権限（POST_NOTIFICATIONS）はベストエフォート。結果を待たず・結果に関わらず
    // 記録開始を進める（`location_permission_gateway.dart` のドキュメント参照）。
    unawaited(_requestNotificationPermission());

    final result = await _control.start();
    if (!mounted) return;

    if (result.outcome == TrackingStartOutcome.permissionDenied) {
      // 直前に権限ありと判定した後、Kotlin側の再確認で拒否された防御的なケース
      // （例: 起動要求の直前に設定画面から権限が取り消された）。状態を再確認して
      // 案内を出す。クラッシュはしない（`LocationTrackingService` のドキュメント参照）。
      final refreshedPermission = await _permissionGateway.status();
      if (!mounted) return;
      setState(() {
        _permissionState = refreshedPermission;
        _busy = false;
      });
      if (refreshedPermission != LocationPermissionState.granted) {
        await _showGuidance(refreshedPermission);
      }
      return;
    }

    final trackingStatus = await _control.status();
    if (!mounted) return;
    setState(() {
      _isRunning = trackingStatus.isRunning;
      _busy = false;
    });
  }

  Future<void> _showGuidance(LocationPermissionState state) {
    return showLocationPermissionGuidanceDialog(
      context: context,
      state: state,
      onRetryRequest: () => unawaited(_startFlow()),
      onOpenSettings: () => unawaited(_permissionGateway.openAppSettings()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final needsPermissionAttention = !_isRunning &&
        _permissionState != LocationPermissionState.granted;

    final IconData icon;
    final String label;
    final String semanticsLabel;
    final Color backgroundColor;
    final Color foregroundColor;

    if (_isRunning) {
      icon = Icons.stop_circle_outlined;
      label = '記録中';
      semanticsLabel = '位置記録は稼働中です。タップして記録を停止します';
      backgroundColor = theme.colorScheme.primary;
      foregroundColor = theme.colorScheme.onPrimary;
    } else if (needsPermissionAttention) {
      icon = Icons.location_disabled;
      label = '権限が必要です';
      semanticsLabel =
          _permissionState == LocationPermissionState.permanentlyDenied
              ? '位置情報の権限が拒否されています。タップして設定への案内を確認します'
              : '位置情報の権限がありません。タップして権限をリクエストします';
      // AppSemanticColors の warning トークンを直接チェーンで書くと
      // check_design_tokens.sh が誤検出するため `warningColor` 経由にする
      // （`color_tokens.dart` のドキュメント参照）。
      backgroundColor = theme.warningColor;
      foregroundColor = theme.colorScheme.onSurface;
    } else {
      icon = Icons.play_circle_outline;
      label = '記録開始';
      semanticsLabel = '位置記録は停止中です。タップして記録を開始します';
      backgroundColor = theme.colorScheme.surface;
      foregroundColor = theme.colorScheme.onSurface;
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      child: FloatingActionButton.extended(
        heroTag: 'tracking_control_button',
        tooltip: semanticsLabel,
        onPressed: _busy ? null : _onPressed,
        backgroundColor: backgroundColor,
        foregroundColor: foregroundColor,
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}
