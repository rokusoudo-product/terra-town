import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// `LocationTrackDatabase.kt`（`docs/location-track-db.md` §4）と同じスキーマの
/// `location_track.sqlite` を組み立てる（`location_track_connection_test.dart` と
/// 同じ方針）。
sqlite3.Database _createSchema(String path) {
  final db = sqlite3.sqlite3.open(path);
  db.execute('''
    CREATE TABLE location_track_meta (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )
  ''');
  db.execute("INSERT INTO location_track_meta (key, value) VALUES ('schema_version', '1')");
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

void _insertPoint(
  sqlite3.Database db, {
  required String sessionId,
  required int elapsedRealtimeNanos,
  required double latitude,
  required double longitude,
  double? accuracyMeters,
  bool possibleMockLocation = false,
}) {
  db.execute(
    'INSERT INTO location_point '
    '(session_id, elapsed_realtime_nanos, wall_clock_unix_millis, latitude, longitude, '
    'accuracy_meters, possible_mock_location, inserted_at_unix_millis) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    [
      sessionId,
      elapsedRealtimeNanos,
      1757000000000,
      latitude,
      longitude,
      accuracyMeters,
      possibleMockLocation ? 1 : 0,
      1757000000000,
    ],
  );
}

void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('native_position_provider_test');
    dbPath = p.join(tempDir.path, 'location_track.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  NativePositionProvider makeProvider({int sinceRowId = 0}) {
    return NativePositionProvider(
      databaseFilePathResolver: () async => dbPath,
      pollInterval: const Duration(milliseconds: 20),
      sinceRowId: sinceRowId,
    );
  }

  test('ファイルがまだ存在しない間は何も流れない（正常系）', () async {
    final provider = makeProvider();
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(events, isEmpty);
  });

  test('購読前に記録済みの行も既定（sinceRowId=0）では全件流れる', () async {
    final db = _createSchema(dbPath);
    _insertPoint(
      db,
      sessionId: 'session-a',
      elapsedRealtimeNanos: 2634654803000000,
      latitude: 35.1,
      longitude: 135.1,
      accuracyMeters: 23.94,
    );
    db.close();

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;

    expect(position.latitude, 35.1);
    expect(position.longitude, 135.1);
    expect(position.accuracy, const Distance.meters(23.94));
    expect(position.trackingSessionId, 'session-a');
    expect(position.spoofSuspected, isFalse);
  });

  test('possible_mock_location=1 の行は spoofSuspected=true になる', () async {
    final db = _createSchema(dbPath);
    _insertPoint(
      db,
      sessionId: 'session-a',
      elapsedRealtimeNanos: 1000,
      latitude: 35.0,
      longitude: 135.0,
      possibleMockLocation: true,
    );
    db.close();

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.spoofSuspected, isTrue);
  });

  test('accuracy_meters が NULL の行は accuracy が null になる', () async {
    final db = _createSchema(dbPath);
    _insertPoint(
      db,
      sessionId: 'session-a',
      elapsedRealtimeNanos: 1000,
      latitude: 35.0,
      longitude: 135.0,
      accuracyMeters: null,
    );
    db.close();

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.accuracy, isNull);
  });

  test('sinceRowId を指定すると、それ以前の行は流れない', () async {
    final db = _createSchema(dbPath);
    _insertPoint(db, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 1, longitude: 1);
    _insertPoint(db, sessionId: 's', elapsedRealtimeNanos: 2, latitude: 2, longitude: 2);
    db.close();

    final provider = makeProvider(sinceRowId: 1);
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.latitude, 2);
  });

  test('購読後にファイルが作成され行が追加されると、ポーリングで検知して流れる', () async {
    final provider = makeProvider();
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    // 最初のポーリングでファイル未作成を確認させてから、後追いで作成する
    // （実運用の「サービス起動後、記録がたまってからDartが購読する」流れの近似）。
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, isEmpty);

    final db = _createSchema(dbPath);
    _insertPoint(db, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 10, longitude: 20);
    db.close();

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events, hasLength(1));
    expect(events.single.latitude, 10);
  });

  test('ポーリングのたびに、既に流した行は再送しない（id を進める）', () async {
    final db = _createSchema(dbPath);
    _insertPoint(db, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 1, longitude: 1);

    final provider = makeProvider();
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(1));

    _insertPoint(db, sessionId: 's', elapsedRealtimeNanos: 2, latitude: 2, longitude: 2);
    db.close();

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(2));
    expect(events.map((e) => e.latitude), [1, 2]);
  });

  group('64bit整数の受け渡し（docs/terrain.md §4.4・Issue #124「⚠️ 64bit値の受け渡し」）', () {
    test('elapsed_realtime_nanos は Pigeon/JSON を経由しないため 2^53 を超えても丸められない', () async {
      // 【値の選定について】実機（Pixel 7a）で確認された値は 2634654803000000
      // （docs/location-track-db.md §8.3）だが、これ自体は 2^53（9007199254740992）
      // 未満（端末起動から約104日未満に相当）であり、丸め問題の再現には使えない。
      // ここでは 2^53 を確実に超える合成値（端末起動から約106年相当。テスト専用の
      // 非現実的な値）を用いて、長時間稼働時に実際に問題になりうる領域を検証する。
      const nanos = 3400000000000000000; // > 2^53、int64の範囲内
      expect(nanos, greaterThan(1 << 53)); // 前提条件: この値は確かにJS安全整数を超える

      final db = _createSchema(dbPath);
      _insertPoint(
        db,
        sessionId: 's',
        elapsedRealtimeNanos: nanos,
        latitude: 1,
        longitude: 1,
      );
      db.close();

      final provider = makeProvider();
      addTearDown(provider.close);
      final position = await provider.positionUpdates.first;

      // 変換後の DateTime を逆算しても、マイクロ秒への切り捨て分を除いて
      // 元の値と完全に一致することを確認する（丸めではなく単純な単位変換であること）。
      final reconstructedNanos = position.timestamp.microsecondsSinceEpoch * 1000;
      expect(reconstructedNanos, nanos - (nanos % 1000));
    });

    test('LocationTrackConnection の生読み取りでも64bit値がそのまま得られる', () {
      const nanos = 2634654803000000;
      final db = _createSchema(dbPath);
      _insertPoint(db, sessionId: 's', elapsedRealtimeNanos: nanos, latitude: 1, longitude: 1);
      db.close();

      final connection = LocationTrackConnection.openIfExists(dbPath)!;
      addTearDown(connection.close);

      final row = connection.selectPointsAfter(0).single;
      expect(row['elapsed_realtime_nanos'], nanos);
    });
  });
}
