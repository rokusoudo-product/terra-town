import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [LocationPointsApi] のフェイク実装（Issue #131）。
///
/// 以前（Issue #124）は `location_track.sqlite` を模した一時ファイルを `package:sqlite3`
/// で組み立ててテストしていたが、Issue #131 で Dart 側はこのファイルを一切開かなくなった
/// （`NativePositionProvider` のクラスdoc参照）ため、Pigeon の host API 呼び出しを
/// フェイクに差し替える形にテストを書き換えた。
class _FakeLocationPointsApi implements LocationPointsApi {
  final List<LocationPointMessage> _rows = [];

  /// [getLocationPoints] が呼ばれた回数（重複防止・ページングのテストで使う）。
  int callCount = 0;

  void addRow(LocationPointMessage row) => _rows.add(row);

  @override
  Future<List<LocationPointMessage>> getLocationPoints(int afterId, int limit) async {
    callCount++;
    final matching = _rows.where((row) => row.id > afterId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return matching.take(limit).toList();
  }
}

/// [_FakeLocationPointsApi.getLocationPoints] が呼ばれるたびに `Completer` で
/// 完了を制御できるフェイク（「前回のポーリングが終わる前に次のポーリングが走らない」
/// ことを検証するために使う）。
class _BlockingFakeLocationPointsApi implements LocationPointsApi {
  final List<LocationPointMessage> _rows = [];
  int callCount = 0;
  final List<_PendingCall> _pendingCalls = [];

  void addRow(LocationPointMessage row) => _rows.add(row);

  /// 保留中の呼び出しのうち最も古いものを、呼び出された時点の `afterId`/`limit` で
  /// フィルタしてから完了させる。
  void completeOldest() {
    final pending = _pendingCalls.removeAt(0);
    final matching = _rows.where((row) => row.id > pending.afterId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    pending.completer.complete(matching.take(pending.limit).toList());
  }

  @override
  Future<List<LocationPointMessage>> getLocationPoints(int afterId, int limit) {
    callCount++;
    final completer = Completer<List<LocationPointMessage>>();
    _pendingCalls.add(_PendingCall(afterId: afterId, limit: limit, completer: completer));
    return completer.future;
  }
}

class _PendingCall {
  _PendingCall({required this.afterId, required this.limit, required this.completer});

  final int afterId;
  final int limit;
  final Completer<List<LocationPointMessage>> completer;
}

LocationPointMessage _row({
  required int id,
  required String sessionId,
  required int elapsedRealtimeNanos,
  required double latitude,
  required double longitude,
  double? accuracyMeters,
  bool possibleMockLocation = false,
  // Issue #108: LocationPointMessage.hexId は non-null になったため、既存のテストを
  // 壊さないよう既定値を用意する（値そのものに意味はない。hexId の変換を検証する
  // テストは個別に明示的な値を渡す）。
  int hexId = 1,
  // Issue #126: 既定値は null（既存テストは歩数を意識しない）。
  int? stepCount,
}) {
  return LocationPointMessage(
    id: id,
    sessionId: sessionId,
    elapsedRealtimeNanos: elapsedRealtimeNanos,
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    possibleMockLocation: possibleMockLocation,
    hexId: hexId,
    stepCount: stepCount,
  );
}

void main() {
  late _FakeLocationPointsApi fakeApi;

  setUp(() {
    fakeApi = _FakeLocationPointsApi();
  });

  NativePositionProvider makeProvider({int sinceRowId = 0, int pageSize = 500}) {
    return NativePositionProvider(
      api: fakeApi,
      pollInterval: const Duration(milliseconds: 20),
      sinceRowId: sinceRowId,
      pageSize: pageSize,
    );
  }

  test('記録が1件も無い間は何も流れない（正常系）', () async {
    final provider = makeProvider();
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(events, isEmpty);
  });

  test('購読前に記録済みの行も既定（sinceRowId=0）では全件流れる', () async {
    fakeApi.addRow(
      _row(
        id: 1,
        sessionId: 'session-a',
        elapsedRealtimeNanos: 2634654803000000,
        latitude: 35.1,
        longitude: 135.1,
        accuracyMeters: 23.94,
      ),
    );

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;

    expect(position.latitude, 35.1);
    expect(position.longitude, 135.1);
    expect(position.accuracy, const Distance.meters(23.94));
    expect(position.trackingSessionId, 'session-a');
    expect(position.spoofSuspected, isFalse);
  });

  test('hexId（Kotlin側で確定済みのH3インデックス）がそのままHexIdに写る（Issue #108）', () async {
    // research.md §8.4 の実測最大値（2^53超）。丸めが起きないことを兼ねて確認する。
    const measuredMaxHexId = 626833456793083903;
    fakeApi.addRow(
      _row(
        id: 1,
        sessionId: 'session-a',
        elapsedRealtimeNanos: 1000,
        latitude: 35.777175,
        longitude: 139.407368,
        hexId: measuredMaxHexId,
      ),
    );

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.hexId, const HexId(measuredMaxHexId));
  });

  test('possibleMockLocation=true の行は spoofSuspected=true になる', () async {
    fakeApi.addRow(
      _row(
        id: 1,
        sessionId: 'session-a',
        elapsedRealtimeNanos: 1000,
        latitude: 35.0,
        longitude: 135.0,
        possibleMockLocation: true,
      ),
    );

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.spoofSuspected, isTrue);
  });

  test('stepCount（歩数センサーの累積歩数）がそのままcumulativeStepCountに写る（Issue #126）', () async {
    fakeApi.addRow(
      _row(
        id: 1,
        sessionId: 'session-a',
        elapsedRealtimeNanos: 1000,
        latitude: 35.0,
        longitude: 135.0,
        stepCount: 1234,
      ),
    );

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.cumulativeStepCount, 1234);
  });

  test('stepCountがnullの行（歩数センサー無し・権限無し・未取得）はcumulativeStepCountもnullになる（Issue #126）',
      () async {
    fakeApi.addRow(
      _row(
        id: 1,
        sessionId: 'session-a',
        elapsedRealtimeNanos: 1000,
        latitude: 35.0,
        longitude: 135.0,
      ),
    );

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.cumulativeStepCount, isNull);
  });

  test('accuracyMeters が null の行は accuracy が null になる', () async {
    fakeApi.addRow(
      _row(
        id: 1,
        sessionId: 'session-a',
        elapsedRealtimeNanos: 1000,
        latitude: 35.0,
        longitude: 135.0,
        accuracyMeters: null,
      ),
    );

    final provider = makeProvider();
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.accuracy, isNull);
  });

  test('sinceRowId を指定すると、それ以前の行は流れない', () async {
    fakeApi
      ..addRow(_row(id: 1, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 1, longitude: 1))
      ..addRow(_row(id: 2, sessionId: 's', elapsedRealtimeNanos: 2, latitude: 2, longitude: 2));

    final provider = makeProvider(sinceRowId: 1);
    addTearDown(provider.close);

    final position = await provider.positionUpdates.first;
    expect(position.latitude, 2);
  });

  test('購読後に新しい行が記録されると、ポーリングで検知して流れる', () async {
    final provider = makeProvider();
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    // 最初のポーリングで記録0件を確認させてから、後追いで行を追加する
    // （実運用の「サービス起動後、記録がたまってからDartが購読する」流れの近似）。
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(events, isEmpty);

    fakeApi.addRow(_row(id: 1, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 10, longitude: 20));

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(events, hasLength(1));
    expect(events.single.latitude, 10);
  });

  test('ポーリングのたびに、既に流した行は再送しない（id を進める）', () async {
    fakeApi.addRow(_row(id: 1, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 1, longitude: 1));

    final provider = makeProvider();
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(1));

    fakeApi.addRow(_row(id: 2, sessionId: 's', elapsedRealtimeNanos: 2, latitude: 2, longitude: 2));

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(2));
    expect(events.map((e) => e.latitude), [1, 2]);
  });

  test('1回のポーリングでは pageSize 件ずつ取得し、件数が pageSize 未満になるまで取り切る', () async {
    for (var i = 1; i <= 5; i++) {
      fakeApi.addRow(
        _row(id: i, sessionId: 's', elapsedRealtimeNanos: i, latitude: i.toDouble(), longitude: 0),
      );
    }

    final provider = makeProvider(pageSize: 2);
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    await Future<void>.delayed(const Duration(milliseconds: 60));

    // 5件を pageSize=2 で取り切るには3回の呼び出し（2+2+1）が必要。
    expect(events, hasLength(5));
    expect(events.map((e) => e.latitude), [1, 2, 3, 4, 5]);
    expect(fakeApi.callCount, greaterThanOrEqualTo(3));
  });

  test('前回のポーリングが完了する前に次のポーリングが走っても行が二重に流れない', () async {
    final blockingApi = _BlockingFakeLocationPointsApi()
      ..addRow(_row(id: 1, sessionId: 's', elapsedRealtimeNanos: 1, latitude: 1, longitude: 1));

    final provider = NativePositionProvider(
      api: blockingApi,
      pollInterval: const Duration(milliseconds: 10),
      sinceRowId: 0,
    );
    addTearDown(provider.close);

    final events = <GeoPosition>[];
    final sub = provider.positionUpdates.listen(events.add);
    addTearDown(sub.cancel);

    // 最初のポーリングが呼ばれ、保留状態になるまで待つ。
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(blockingApi.callCount, 1);

    // pollInterval を複数回またいでも、前回が保留中なら新しい呼び出しは発生しない
    // （_isPolling ガードの検証）。
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(blockingApi.callCount, 1);

    // 最初の呼び出しを完了させると、行が1件だけ流れる。
    blockingApi.completeOldest();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(events, hasLength(1));
  });

  group('recordedPositionUpdates（行id付き・Issue #138）', () {
    test('LocationPointMessage.id がそのまま rowId として届く', () async {
      fakeApi
        ..addRow(_row(id: 1, sessionId: 's', elapsedRealtimeNanos: 1000, latitude: 1, longitude: 1))
        ..addRow(_row(id: 2, sessionId: 's', elapsedRealtimeNanos: 2000, latitude: 2, longitude: 2));

      final provider = makeProvider();
      addTearDown(provider.close);

      final records = await provider.recordedPositionUpdates.take(2).toList();

      expect(records.map((r) => r.rowId), [1, 2]);
      expect(records.map((r) => r.position.latitude), [1, 2]);
    });

    test('positionUpdates と recordedPositionUpdates は同じ内部ポーリングを共有し、'
        '購読前に記録済みの行も既定では全件流れる（既存の positionUpdates と同じ挙動）', () async {
      fakeApi.addRow(
        _row(id: 1, sessionId: 'session-a', elapsedRealtimeNanos: 1000, latitude: 35.1, longitude: 135.1),
      );

      final provider = makeProvider();
      addTearDown(provider.close);

      final record = await provider.recordedPositionUpdates.first;

      expect(record.rowId, 1);
      expect(record.position.latitude, 35.1);
      expect(record.position.trackingSessionId, 'session-a');
    });

    test('positionUpdates（GeoPositionのみ）は引き続き従来どおり動作する（後方互換）', () async {
      fakeApi.addRow(
        _row(id: 1, sessionId: 's', elapsedRealtimeNanos: 1000, latitude: 9.0, longitude: 8.0),
      );

      final provider = makeProvider();
      addTearDown(provider.close);

      final position = await provider.positionUpdates.first;

      expect(position.latitude, 9.0);
      expect(position.longitude, 8.0);
    });
  });

  group('64bit整数の受け渡し（docs/terrain.md §4.4・Issue #124/#131「⚠️ 64bit値の受け渡し」）', () {
    test('elapsedRealtimeNanos は Pigeon/JSON を経由しないため 2^53 を超えても丸められない', () async {
      // 【値の選定について】実機（Pixel 7a）で確認された値は 2634654803000000
      // （docs/location-track-db.md §8.3）だが、これ自体は 2^53（9007199254740992）
      // 未満（端末起動から約104日未満に相当）であり、丸め問題の再現には使えない。
      // ここでは 2^53 を確実に超える合成値（端末起動から約106年相当。テスト専用の
      // 非現実的な値）を用いて、長時間稼働時に実際に問題になりうる領域を検証する。
      const nanos = 3400000000000000000; // > 2^53、int64の範囲内
      expect(nanos, greaterThan(1 << 53)); // 前提条件: この値は確かにJS安全整数を超える

      fakeApi.addRow(
        _row(id: 1, sessionId: 's', elapsedRealtimeNanos: nanos, latitude: 1, longitude: 1),
      );

      final provider = makeProvider();
      addTearDown(provider.close);
      final position = await provider.positionUpdates.first;

      // 変換後の DateTime を逆算しても、マイクロ秒への切り捨て分を除いて
      // 元の値と完全に一致することを確認する（丸めではなく単純な単位変換であること）。
      final reconstructedNanos = position.timestamp.microsecondsSinceEpoch * 1000;
      expect(reconstructedNanos, nanos - (nanos % 1000));
    });

    test(
      'Pigeon のメッセージコーデックで往復させても64bit値が変わらない'
      '（elapsedRealtimeNanos: Issue #131・hexId: Issue #108）',
      () {
        // NativePositionProvider を経由せず、Pigeon が実際に使うコーデック
        // （LocationTrackingHostApi.pigeonChannelCodec・StandardMessageCodec 拡張）に
        // 直接メッセージを通し、バイナリ表現の往復でも値が変わらないことを確認する。
        // これにより「StandardMessageCodec は Kotlin の Long と Dart の int を
        // そのまま運ぶ」という pigeons/location_api.dart の説明を実装で裏付ける。
        const nanos = 3400000000000000000;
        // Issue #108 本文の実測最大値（research.md §8.4）。2^53超のフィクスチャ中でも
        // 最大級の値で、hex_id が丸められずに Dart 側へ渡ることを実測で確認する
        // （Issue #108 受け入れ基準「hex_id が丸められずに Dart 側へ渡ることが実測で
        // 確認されている」に対応する具体的なテスト）。
        const measuredMaxHexId = 626833456793083903;
        final message = LocationPointMessage(
          id: 42,
          sessionId: 'session-codec',
          elapsedRealtimeNanos: nanos,
          latitude: 35.6812,
          longitude: 139.7671,
          accuracyMeters: 12.5,
          possibleMockLocation: true,
          hexId: measuredMaxHexId,
          stepCount: 4567,
        );

        final codec = LocationTrackingHostApi.pigeonChannelCodec;
        final encoded = codec.encodeMessage(message);
        final decoded = codec.decodeMessage(encoded) as LocationPointMessage;

        expect(decoded.id, message.id);
        expect(decoded.sessionId, message.sessionId);
        expect(decoded.elapsedRealtimeNanos, nanos);
        expect(decoded.latitude, message.latitude);
        expect(decoded.longitude, message.longitude);
        expect(decoded.accuracyMeters, message.accuracyMeters);
        expect(decoded.possibleMockLocation, message.possibleMockLocation);
        expect(decoded.hexId, measuredMaxHexId);
        expect(decoded.stepCount, 4567);
      },
    );
  });
}
