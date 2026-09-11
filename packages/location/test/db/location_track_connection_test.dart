import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_location/terra_town_location.dart';

/// `location_track.sqlite` を模したファイルを、Kotlin 側
/// （`LocationTrackDatabase.kt`・`docs/location-track-db.md` §4）と
/// 同じスキーマで書き込み可能な状態に組み立てるテストヘルパー。
sqlite3.Database _seedDatabase(String path, {int schemaVersion = 1}) {
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE location_track_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )
  ''');
  db.execute(
    "INSERT INTO location_track_meta (key, value) VALUES ('schema_version', '$schemaVersion')",
  );
  db.execute('''
    CREATE TABLE location_point (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        elapsed_realtime_nanos INTEGER NOT NULL,
        wall_clock_unix_millis INTEGER NOT NULL,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy_meters REAL,
        possible_mock_location INTEGER NOT NULL DEFAULT 0,
        inserted_at_unix_millis INTEGER NOT NULL
    )
  ''');
  return db;
}

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('location_track_connection_test');
    dbPath = p.join(tempDir.path, 'location_track.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('ファイルが存在しない場合は null を返す（記録がまだ1件も無い正常系）', () {
    final missingPath = p.join(tempDir.path, 'does_not_exist.sqlite');

    expect(LocationTrackConnection.openIfExists(missingPath), isNull);
  });

  test('読み取り専用で開いた接続から既存データを読み取れる', () {
    final seed = _seedDatabase(dbPath);
    seed.execute(
      'INSERT INTO location_point '
      '(session_id, elapsed_realtime_nanos, wall_clock_unix_millis, latitude, longitude, '
      'accuracy_meters, possible_mock_location, inserted_at_unix_millis) VALUES '
      "('session-a', 2634654803000000, 1757000000000, 35.1, 135.1, 23.94, 0, 1757000000123)",
    );
    seed.close();

    final connection = LocationTrackConnection.openIfExists(dbPath);
    addTearDown(() => connection?.close());
    expect(connection, isNotNull);

    final rows = connection!.selectPointsAfter(0);
    expect(rows, hasLength(1));
    expect(rows.single['session_id'], 'session-a');
    expect(rows.single['latitude'], 35.1);
    expect(rows.single['longitude'], 135.1);
    // 64bit整数がそのまま（丸めなく）読めることを確認する（docs/terrain.md §4.4）。
    expect(rows.single['elapsed_realtime_nanos'], 2634654803000000);
  });

  test('selectPointsAfter は afterId より大きい id の行だけを id 昇順で返す', () {
    final seed = _seedDatabase(dbPath);
    for (var i = 0; i < 3; i++) {
      seed.execute(
        'INSERT INTO location_point '
        '(session_id, elapsed_realtime_nanos, wall_clock_unix_millis, latitude, longitude, '
        'accuracy_meters, possible_mock_location, inserted_at_unix_millis) VALUES '
        "('session-a', ${1000 + i}, 1757000000000, 35.$i, 135.$i, NULL, 0, 1757000000000)",
      );
    }
    seed.close();

    final connection = LocationTrackConnection.openIfExists(dbPath)!;
    addTearDown(connection.close);

    final rows = connection.selectPointsAfter(1);
    expect(rows.map((row) => row['id']), [2, 3]);
  });

  test('読み取り専用で開いた接続への書き込みは SQLite 自身が拒否する', () {
    final seed = _seedDatabase(dbPath);
    seed.close();

    final connection = LocationTrackConnection.openIfExists(dbPath)!;
    addTearDown(connection.close);

    // region_pack_connection_test.dart と同じ検証方針:
    // アプリ側の規約ではなく SQLite の OpenMode.readOnly により
    // SQLITE_READONLY で拒否されることを確認する（構造的な書き込み防止）。
    expect(
      () => connection.rawExecuteForTesting(
        'INSERT INTO location_point '
        '(session_id, elapsed_realtime_nanos, wall_clock_unix_millis, latitude, longitude, '
        'possible_mock_location, inserted_at_unix_millis) VALUES '
        "('x', 1, 1, 0, 0, 0, 1)",
      ),
      throwsA(isA<sqlite3.SqliteException>()),
    );
  });

  test('schema_version が前提と異なる場合は StateError を送出する', () {
    final seed = _seedDatabase(dbPath, schemaVersion: 999);
    seed.close();

    expect(
      () => LocationTrackConnection.openIfExists(dbPath),
      throwsA(isA<StateError>()),
    );
  });

  test('location_track_meta に schema_version が無い場合も StateError を送出する', () {
    final seed = sqlite3.sqlite3.open(dbPath);
    seed.execute('CREATE TABLE location_track_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
    seed.execute('''
      CREATE TABLE location_point (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id TEXT NOT NULL,
          elapsed_realtime_nanos INTEGER NOT NULL,
          wall_clock_unix_millis INTEGER NOT NULL,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          accuracy_meters REAL,
          possible_mock_location INTEGER NOT NULL DEFAULT 0,
          inserted_at_unix_millis INTEGER NOT NULL
      )
    ''');
    seed.close();

    expect(
      () => LocationTrackConnection.openIfExists(dbPath),
      throwsA(isA<StateError>()),
    );
  });
}
