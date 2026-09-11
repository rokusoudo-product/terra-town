import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Kotlin 側 foreground service（Issue #123・PR #128・`LocationTrackDatabase.kt`）が
/// 書き込む `location_track.sqlite` への読み取り専用接続（Issue #124・T050）。
///
/// `region_pack_connection.dart`（Issue #83・T030）と**全く同じ設計**
/// （`OpenMode.readOnly` による構造的な書き込み防止）を踏襲する。
/// `docs/location-track-db.md` §3 がこの設計を Dart 側向けの推奨として明記している。
///
/// 【書き込みを構造的に防ぐ方法】`region_pack_connection.dart` と同じく、対象ファイルを
/// SQLite の **`OpenMode.readOnly`** で開く。アプリ側の自己規律ではなく、
/// **SQLite 自身が** `INSERT`/`UPDATE`/`DELETE` 等の書き込み系SQL文をエラー
/// （`SQLITE_READONLY`）にする（`location_track_connection_test.dart` で検証）。
///
/// ## 地域パックDBとの違い
/// 地域パックDBは配布物（ビルド時に確定・不変）だが、`location_track.sqlite` は
/// 実行時に Kotlin 側の foreground service が非同期に書き込み続ける。そのため
/// 本クラスは「ファイルがまだ存在しない」（記録が1件も行われていない）を
/// **正常系**として扱う（[openIfExists] が `null` を返す。呼び出し側
/// （`NativePositionProvider`）はポーリングを続ける想定）。
///
/// ## スキーマバージョンの確認（Kotlin 側コメントの受け皿）
/// `LocationTrackDatabase.kt`（`LocationTrackSchema`）のコメントは
/// 「Dart 側（Issue #124）が、マイグレーション未対応の古い前提で読んでいないかを
/// 確認できるように」`location_track_meta.schema_version` を書き込むとしている。
/// [openIfExists] はこの値を読み、[expectedSchemaVersion] と食い違えば
/// [StateError] を送出する。**これは正常系のリトライ対象にはしない**
/// （ファイル未作成とは異なり、スキーマの不一致は実装のバグであり、
/// 気づかず読み違えるより早期に落ちた方が安全なため）。
class LocationTrackConnection {
  LocationTrackConnection._(this._rawDatabase);

  final sqlite3.Database _rawDatabase;

  /// このクラスが前提とする `location_track_meta.schema_version`。
  /// `docs/location-track-db.md` §4 の現在値（1）と一致させること。
  static const int expectedSchemaVersion = 1;

  /// [filePath] のファイルが存在すれば読み取り専用で開く。
  ///
  /// 存在しない場合は `null` を返す（記録がまだ1件も行われていない正常系）。
  /// `OpenMode.readOnly` は既定の `readWriteCreate` と異なりファイルを新規作成
  /// しないため、事前に存在確認をしても TOCTOU で空のDBが作られる心配はない。
  ///
  /// スキーマバージョンが [expectedSchemaVersion] と一致しない場合は [StateError] を
  /// 送出する（クラスdoc参照）。ファイルは存在するがスキーマ未初期化（`location_point`
  /// テーブルが無い等。Kotlin 側の `SQLiteOpenHelper` がファイル作成と DDL 適用を
  /// アトミックに行わないための短いレース）の場合は [sqlite3.SqliteException] が
  /// そのまま伝播する。呼び出し側（`NativePositionProvider`）はこれを
  /// リトライ対象として扱う。
  static LocationTrackConnection? openIfExists(String filePath) {
    if (!File(filePath).existsSync()) {
      return null;
    }

    final rawDatabase = sqlite3.sqlite3.open(
      filePath,
      mode: sqlite3.OpenMode.readOnly,
    );
    try {
      _checkSchemaVersion(rawDatabase);
    } catch (_) {
      rawDatabase.close();
      rethrow;
    }
    return LocationTrackConnection._(rawDatabase);
  }

  static void _checkSchemaVersion(sqlite3.Database rawDatabase) {
    final rows = rawDatabase.select(
      "SELECT value FROM location_track_meta WHERE key = 'schema_version'",
    );
    if (rows.isEmpty) {
      throw StateError(
        'location_track.sqlite に location_track_meta.schema_version が'
        '見つかりません。docs/location-track-db.md §4 のスキーマと一致しているか'
        '確認してください。',
      );
    }
    final version = int.parse(rows.first['value'] as String);
    if (version != expectedSchemaVersion) {
      throw StateError(
        'location_track.sqlite の schema_version ($version) が '
        'LocationTrackConnection の前提（$expectedSchemaVersion）と一致しません。'
        'docs/location-track-db.md §4 を確認し、読み取りロジックを更新してください。',
      );
    }
  }

  /// `location_point` から `id` が [afterId] より大きい行を `id` 昇順で取得する。
  ///
  /// 列は `docs/location-track-db.md` §4 のスキーマそのまま
  /// （`wall_clock_unix_millis`・`inserted_at_unix_millis` は Issue #124 のスコープでは
  /// 使わないため選択しない。改竄可能な参考情報・デバッグ用途のみの列であり、
  /// [NativePositionProvider] が組み立てる [GeoPosition] には反映しない）。
  sqlite3.ResultSet selectPointsAfter(int afterId) {
    return _rawDatabase.select(
      'SELECT id, session_id, elapsed_realtime_nanos, latitude, longitude, '
      'accuracy_meters, possible_mock_location '
      'FROM location_point WHERE id > ? ORDER BY id ASC',
      [afterId],
    );
  }

  /// テスト専用: 書き込み系SQL文が実際に `SQLITE_READONLY` で拒否されることを
  /// 検証するための実行口（`region_pack_connection.dart` の
  /// `rawExecuteForTesting` と同じ設計）。通常の呼び出し側はこのメソッドを
  /// 使わないこと（読み取り専用という設計意図に反する）。
  @visibleForTesting
  void rawExecuteForTesting(String sql) => _rawDatabase.execute(sql);

  void close() => _rawDatabase.close();
}
