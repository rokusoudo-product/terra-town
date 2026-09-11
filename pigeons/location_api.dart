import 'package:pigeon/pigeon.dart';

// 【実行方法】本ファイルは packages/location を cwd として実行する
// （pigeon が dev_dependency として解決されているのが packages/location/pubspec.yaml
// のため）。出力パスは cwd（packages/location）からの相対パスで指定してある。
//   cd packages/location && dart run pigeon --input ../../pigeons/location_api.dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/position/location_api.g.dart',
  dartOptions: DartOptions(),
  dartPackageName: 'terra_town_location',
  kotlinOut:
      '../../app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/LocationApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'jp.rokusoudo.terra_town.location'),
))

/// 位置記録 platform channel の型定義（Issue #124・T049）。
///
/// `specs/001-mvp/plan.md` §1-C の決定 C「機微処理（背景位置・fused location・
/// モック検出・Play Integrity・歩数センサーはOS別実装が本質）」に基づき、
/// Pigeon の channel 契約ファイルを **iOS 移植の正** とする（advisor 評価：
/// 「Pigeon の channel 契約ファイルを iOS 移植の正とし、Dart 側ロジックは共通化する」）。
///
/// ## ⚠️ なぜ位置データそのものをここに含めないか（Issue #124 起票時の論点・本 Issue で決定）
/// `docs/location-track-db.md` §2・§3 は、位置記録ファイル `location_track.sqlite` を
/// Dart 側から直接読み取り専用で開く方法（`NativePositionProvider`・
/// `packages/location/lib/src/db/location_track_connection.dart`）を推奨している。
/// 本 Pigeon ファイルは**位置データ（緯度経度・時刻・精度）を1件も運ばない**。
/// 代わりに運ぶのは、位置記録 foreground service（PR #128・`LocationTrackingService`）の
/// **起動・停止・状態問い合わせという制御面**だけである。
///
/// 理由:
/// 1. **効率**: 位置データは記録が進むにつれて増え続ける。Pigeon（1呼び出し1メッセージ）で
///    1件ずつ運ぶより、まとまった単位でファイルを直接読む方が単純かつ効率的であり、
///    `docs/location-track-db.md` が既にその経路（`app_flutter/` 配下の共有ディレクトリに
///    Kotlin/Dart 双方がアクセスできる）を確立している。
/// 2. **64bit整数の丸め問題を経路自体から排除する**（`docs/terrain.md` §4.4・Issue #124
///    本文「⚠️ 64bit整数の受け渡し」）。位置記録の `elapsed_realtime_nanos`
///    （実機で `2634654803000000` 程度の値を確認済み）はJSON系の経路で2^53を超えて
///    丸められる恐れがあるが、本ファイルのメッセージ型は**64bit整数を一切含まない**
///    ため、この経路では問題が発生しようがない。SQLite 経由の64bit値は
///    Dart のネイティブ `int`（VM上は64bit）でそのまま読める
///    （`native_position_provider_test.dart`・`location_track_connection_test.dart`
///    で丸めが起きないことを確認する）。
/// 3. **スコープの厳守**: Kotlin foreground service 本体（PR #128）の実装・スキーマを
///    変更せずに済む。位置データの受け渡し方法は Issue #123 の時点で既に確定している
///    （`docs/location-track-db.md`）。
///
/// 一方で、次の3つは位置データではなく「サービスの制御・状態」であり、
/// ファイル読み取りでは表現できない（ファイルには「今まさに稼働中か」
/// 「起動要求がなぜ失敗したか」は記録されない）ため、Pigeon で渡す:
/// - サービスの起動・停止（[LocationTrackingHostApi.startTracking]・
///   [LocationTrackingHostApi.stopTracking]）。現状はデバッグ用 Intent
///   （`MainActivity.handleDebugLocationServiceIntent`）でしか起動できない。
/// - サービスの状態（稼働中か・現在の `session_id`。
///   [LocationTrackingHostApi.getTrackingStatus]）。
/// - 起動しなかった理由（[TrackingStartOutcome.permissionDenied]）。
enum TrackingStartOutcome {
  /// フォアグラウンド位置権限（`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`）が
  /// 確認でき、位置記録 foreground service の起動を要求した
  /// （`Context#startForegroundService()` を呼んだ、という意味。実際に
  /// `startForeground()` まで到達したかはこの結果からは分からない。稼働状態の
  /// 確認は [LocationTrackingHostApi.getTrackingStatus] を使うこと）。
  started,

  /// フォアグラウンド位置権限が無いため、`startForegroundService()` 自体を
  /// **呼ばずに**起動を拒否した。
  ///
  /// **なぜこの区別が安全性に直結するか**: 権限が無い場合に
  /// `Context#startForegroundService()` を呼んでしまうと、システムは一定時間内の
  /// `Service.startForeground()` 呼び出しを義務づけるため、権限チェックを
  /// サービス内部だけに任せると `ForegroundServiceDidNotStartInTimeException` で
  /// アプリのプロセスごと強制終了されうる
  /// （2026-09-11 実機検証・Pixel 7a・PR #128 のレビューコメントで確認済み）。
  ///
  /// この修正（`LocationTrackingService.Companion.start()` 側で権限を確認し、
  /// 権限が無ければ `startForegroundService()` 自体を呼ばず `Boolean` の戻り値で
  /// 呼び出し側に通知する）は **PR #130（2026-09-11 マージ）で main に反映済み**。
  /// 本 Pigeon ハンドラ（`LocationApiHandler.kt`）は `Companion.start()` の戻り値を
  /// そのままこの結果に変換するだけで、自前の権限チェックは行わない。
  permissionDenied,
}

class TrackingStartResult {
  TrackingStartResult({required this.outcome});

  final TrackingStartOutcome outcome;
}

class TrackingStatus {
  TrackingStatus({required this.isRunning, this.sessionId});

  /// 位置記録 foreground service が現在稼働中か
  /// （`startForeground()` まで到達した状態を指す。権限拒否で拒否された場合は false）。
  final bool isRunning;

  /// 稼働中の場合の記録セッションID。
  ///
  /// `location_track.sqlite` の `location_point.session_id` 列、および
  /// `GeoPosition.trackingSessionId`（`packages/core`・本 Issue で追加）と同じ値。
  /// 未稼働時は null。
  final String? sessionId;
}

@HostApi()
abstract class LocationTrackingHostApi {
  /// 位置記録 foreground service の起動を要求する。
  ///
  /// フォアグラウンド位置権限が無い場合は [TrackingStartOutcome.permissionDenied] を
  /// 返し、`startForegroundService()` 自体を呼ばない（[TrackingStartOutcome] の
  /// ドキュメント参照）。
  TrackingStartResult startTracking();

  /// 位置記録 foreground service の停止を要求する。
  void stopTracking();

  /// 現在の稼働状態を問い合わせる。
  TrackingStatus getTrackingStatus();
}
