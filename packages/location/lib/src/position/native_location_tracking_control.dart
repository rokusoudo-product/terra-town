import 'location_api.g.dart';

/// Pigeon で生成された [LocationTrackingHostApi]（`pigeons/location_api.dart`・
/// Issue #124・T049）への薄いラッパー。
///
/// `NativePositionProvider`（位置データの読み取り）とは別クラスにしている理由:
/// [PositionProvider] 抽象は「位置更新の購読」だけを表し、サービスの起動・停止・
/// 状態問い合わせという制御操作を含まない。両者を1クラスに混ぜると
/// `PositionProvider` の責務（`core` から見たインターフェース）を超えてしまうため、
/// 制御操作は本クラスに分離した。呼び出し側（composition root・`app/`）が両方を
/// 組み合わせて使う。
class NativeLocationTrackingControl {
  NativeLocationTrackingControl({LocationTrackingHostApi? api})
      : _api = api ?? LocationTrackingHostApi();

  final LocationTrackingHostApi _api;

  /// 位置記録 foreground service の起動を要求する。
  ///
  /// フォアグラウンド位置権限が無い場合は `startForegroundService()` 自体を呼ばず
  /// [TrackingStartOutcome.permissionDenied] を返す（`LocationApiHandler.kt`・
  /// クラッシュ回避の詳細は `pigeons/location_api.dart` 参照）。
  Future<TrackingStartResult> start() => _api.startTracking();

  /// 位置記録 foreground service の停止を要求する。
  Future<void> stop() => _api.stopTracking();

  /// 現在の稼働状態（稼働中か・現在の `session_id`）を問い合わせる。
  Future<TrackingStatus> status() => _api.getTrackingStatus();
}
