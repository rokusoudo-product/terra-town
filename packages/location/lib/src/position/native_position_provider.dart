import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_core/terra_town_core.dart';

import '../db/location_track_connection.dart';

/// [PositionProvider] の実機実装（Issue #124・T050）。
///
/// Kotlin 側 foreground service（Issue #123・PR #128・`LocationTrackingService`）が
/// 書き込む `location_track.sqlite` を [LocationTrackConnection]（読み取り専用）で
/// 開き、新規に記録された行を [GeoPosition] に変換して [positionUpdates] から流す。
///
/// ## なぜ Pigeon（platform channel）ではなくファイル読み取りなのか
/// `pigeons/location_api.dart` のドキュメント参照。位置データそのものは
/// `docs/location-track-db.md` §2・§3 が確立した「Kotlin/Dart 双方が同じ
/// `getApplicationDocumentsDirectory()`（`app_flutter/`）を見る」経路で受け渡す。
/// Pigeon はサービスの起動・停止・状態問い合わせという制御面のみを扱う
/// （`native_location_tracking_control.dart` 参照）。
///
/// ## ポーリング方式を採る理由
/// Kotlin 側は Dart に新規行の到着を能動的に通知しない（EventChannel等は
/// 使わない。位置データを Pigeon で流さない、という決定と同じ理由——効率と
/// 64bit整数の丸め回避——により、通知経路自体を増やさない）。そのため本実装は
/// [pollInterval] ごとに `location_point` の未読の行（[sinceRowId] より大きい `id`）
/// を SELECT する。ファイルは WAL モードのため、Kotlin 側が書き込んだ直後の行も
/// 読み取り専用接続から見える（`docs/location-track-db.md` §3「WAL」参照）。
///
/// ## 履歴の扱い（[sinceRowId] の既定値は 0＝全件）
/// 実運用の典型的な流れは「adb 等でサービスを先に起動 → 歩く → その後アプリを開く」
/// でありうるため、購読開始時点の最大 `id` から始める（＝以後の新規分だけ流す）
/// 設計は、購読前に記録された分を静かに読み飛ばしてしまう。**開示判定
/// （[DisclosureService]）は同じヘクスを何度処理しても副作用が無い（冪等）ため、
/// 全件を毎回流しても安全側に倒れる**（[SpeedFilter] はまだ本番配線されていないため
/// 実害もない）。そのため既定は「記録開始（`id > 0`）から全件」とした。
/// 「前回読み終えた `id` を永続化して次回はそこから」という最適化は本 Issue の
/// スコープ外（要確認・PR本文参照）。
///
/// ## GeoPosition への変換方針
/// - [GeoPosition.timestamp]: `location_point.elapsed_realtime_nanos`
///   （単調時計・ナノ秒）を [DateTime.fromMicrosecondsSinceEpoch] でマイクロ秒に
///   丸めて変換する（isUtc: true。壁時計は使わない。理由は [GeoPosition.timestamp]
///   のドキュメント参照）。ナノ秒→マイクロ秒の切り捨てにより1マイクロ秒未満の
///   分解能は失われるが、GPS/fused location の実用上の分解能（ミリ秒オーダー）を
///   大きく下回るため実害はない。
/// - [GeoPosition.trackingSessionId]: `location_point.session_id` をそのまま渡す。
/// - [GeoPosition.spoofSuspected]: `location_point.possible_mock_location`
///   （0/1）を bool に変換するだけ。判定ロジック自体は実装しない（Issue #126）。
/// - `wall_clock_unix_millis`・`inserted_at_unix_millis` は変換しない
///   （[LocationTrackConnection.selectPointsAfter] のドキュメント参照）。
///
/// ## 64bit整数について
/// `elapsed_realtime_nanos` は実機で `2634654803000000` 程度の値になることを
/// 確認済み（`docs/location-track-db.md` §8.3）。本実装は Pigeon/JSON を経由せず
/// `package:sqlite3` が返す Dart のネイティブ `int`（VM上は64bit）をそのまま扱うため、
/// `docs/terrain.md` §4.4 が警告する 2^53 丸めは発生しない
/// （`native_position_provider_test.dart` で検証）。
class NativePositionProvider implements PositionProvider {
  NativePositionProvider({
    Future<String> Function()? databaseFilePathResolver,
    this.pollInterval = const Duration(seconds: 5),
    this.sinceRowId = 0,
  }) : _databaseFilePathResolver =
            databaseFilePathResolver ?? _defaultDatabaseFilePathResolver;

  /// `location_track.sqlite` のファイルパスを解決する関数。
  ///
  /// 既定は `getApplicationDocumentsDirectory()`（`docs/location-track-db.md` §2）。
  /// テストでは一時ディレクトリを指す関数を注入する。
  final Future<String> Function() _databaseFilePathResolver;

  /// 新規行の有無を確認する間隔。
  final Duration pollInterval;

  /// この `id` より大きい行だけを新規として流す。クラスdoc「履歴の扱い」参照。
  final int sinceRowId;

  static const String _databaseFileName = 'location_track.sqlite';

  static Future<String> _defaultDatabaseFilePathResolver() async {
    final directory = await getApplicationDocumentsDirectory();
    return p.join(directory.path, _databaseFileName);
  }

  LocationTrackConnection? _connection;
  int _lastSeenId = 0;
  Timer? _timer;
  StreamController<GeoPosition>? _controller;

  @override
  Stream<GeoPosition> get positionUpdates {
    final controller = _controller ??= StreamController<GeoPosition>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return controller.stream;
  }

  void _start() {
    _lastSeenId = sinceRowId;
    unawaited(_poll());
    _timer ??= Timer.periodic(pollInterval, (_) => _poll());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
    _connection?.close();
    _connection = null;
  }

  Future<void> _poll() async {
    final controller = _controller;
    if (controller == null || controller.isClosed) {
      return;
    }

    try {
      final connection = await _ensureConnection();
      if (connection == null) {
        // location_track.sqlite がまだ存在しない（記録が1件も無い）。正常系。
        return;
      }

      final rows = connection.selectPointsAfter(_lastSeenId);
      for (final row in rows) {
        _lastSeenId = row['id'] as int;
        controller.add(_toGeoPosition(row));
      }
    } on sqlite3.SqliteException catch (error) {
      // Kotlin 側がファイル作成直後（DDL未完了）にクエリが割り込むレース、または
      // サービス再起動でファイルが入れ替わる場合。接続を破棄し、次回ポーリングで
      // 開き直す（ストリーム自体は壊さない。呼び出し側にエラーとして伝播させない）。
      _connection?.close();
      _connection = null;
      // ignore: avoid_print
      print(
        'NativePositionProvider: location_track.sqlite の読み取りに失敗したため '
        '次回ポーリングで再試行します: $error',
      );
    }
  }

  Future<LocationTrackConnection?> _ensureConnection() async {
    final existing = _connection;
    if (existing != null) return existing;

    final path = await _databaseFilePathResolver();
    final connection = LocationTrackConnection.openIfExists(path);
    _connection = connection;
    return connection;
  }

  static GeoPosition _toGeoPosition(sqlite3.Row row) {
    final elapsedRealtimeNanos = row['elapsed_realtime_nanos'] as int;
    final accuracyMeters = row['accuracy_meters'] as double?;
    final possibleMockLocation = (row['possible_mock_location'] as int) != 0;
    return GeoPosition(
      latitude: row['latitude'] as double,
      longitude: row['longitude'] as double,
      // 単調時計（elapsedRealtime）をそのままマイクロ秒へ変換する。壁時計は使わない
      // （クラスdoc「GeoPosition への変換方針」参照）。
      timestamp: DateTime.fromMicrosecondsSinceEpoch(
        elapsedRealtimeNanos ~/ 1000,
        isUtc: true,
      ),
      accuracy: accuracyMeters == null ? null : Distance.meters(accuracyMeters),
      spoofSuspected: possibleMockLocation,
      trackingSessionId: row['session_id'] as String,
    );
  }

  /// 使用済みのリソース（ポーリングタイマー・SQLite接続・StreamController）を解放する。
  Future<void> close() async {
    _stop();
    await _controller?.close();
    _controller = null;
  }
}
