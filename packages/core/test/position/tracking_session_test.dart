import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

GeoPosition _at(DateTime at, {String? session}) => GeoPosition(
      latitude: 35.0,
      longitude: 135.0,
      timestamp: at,
      trackingSessionId: session,
    );

void main() {
  group('splitByTrackingSession', () {
    test('空リストを渡すと空リストを返す', () {
      expect(splitByTrackingSession(const []), isEmpty);
    });

    test('trackingSessionId が全て null（従来通りの後方互換）なら分割されない', () {
      final positions = [
        _at(DateTime.utc(2026, 9, 11, 0, 0, 0)),
        _at(DateTime.utc(2026, 9, 11, 0, 0, 1)),
        _at(DateTime.utc(2026, 9, 11, 0, 0, 2)),
      ];

      final groups = splitByTrackingSession(positions);

      expect(groups, hasLength(1));
      expect(groups.single, positions);
    });

    test('trackingSessionId が全て同じ非nullな値なら分割されない', () {
      final positions = [
        _at(DateTime.utc(2026, 9, 11, 0, 0, 0), session: 'session-a'),
        _at(DateTime.utc(2026, 9, 11, 0, 0, 1), session: 'session-a'),
      ];

      expect(splitByTrackingSession(positions), hasLength(1));
    });

    test('trackingSessionId が変わる境界で分割される', () {
      final a1 = _at(DateTime.utc(2026, 9, 11, 0, 0, 0), session: 'session-a');
      final a2 = _at(DateTime.utc(2026, 9, 11, 0, 0, 1), session: 'session-a');
      // 端末再起動により elapsedRealtime がリセットされたことを模す
      // （session-b の時刻は session-a より「前」に見える）。
      final b1 = _at(DateTime.utc(2026, 9, 11, 0, 0, 0), session: 'session-b');
      final b2 = _at(DateTime.utc(2026, 9, 11, 0, 0, 1), session: 'session-b');

      final groups = splitByTrackingSession([a1, a2, b1, b2]);

      expect(groups, [
        [a1, a2],
        [b1, b2],
      ]);
    });

    test('null から非nullへの切り替わりも境界として分割される', () {
      final withoutSession = _at(DateTime.utc(2026, 9, 11));
      final withSession = _at(DateTime.utc(2026, 9, 11, 0, 0, 1), session: 'session-a');

      final groups = splitByTrackingSession([withoutSession, withSession]);

      expect(groups, [
        [withoutSession],
        [withSession],
      ]);
    });

    test(
      'セッション単位に分割してから SpeedFilter.classify すれば、'
      'セッションをまたぐ時刻の巻き戻りがあっても破綻しない',
      () {
        // session-a: t=0s, t=10s（10秒で歩行相当の距離）。
        final a1 = GeoPosition(
          latitude: 35.0,
          longitude: 135.0,
          timestamp: DateTime.utc(2026, 9, 11, 0, 0, 0),
          trackingSessionId: 'session-a',
        );
        final a2 = GeoPosition(
          latitude: 35.0001,
          longitude: 135.0,
          timestamp: DateTime.utc(2026, 9, 11, 0, 0, 10),
          trackingSessionId: 'session-a',
        );
        // 端末再起動後の session-b: elapsedRealtime がリセットされ、
        // 壁時計上は a2 よりずっと後なのに、単調時計由来の timestamp は
        // a1・a2 より「前」に戻る（reboot の典型的な症状）。
        final b1 = GeoPosition(
          latitude: 35.0002,
          longitude: 135.0,
          timestamp: DateTime.utc(2026, 9, 11, 0, 0, 1),
          trackingSessionId: 'session-b',
        );
        final b2 = GeoPosition(
          latitude: 35.0003,
          longitude: 135.0,
          timestamp: DateTime.utc(2026, 9, 11, 0, 0, 11),
          trackingSessionId: 'session-b',
        );

        final naiveConcat = [a1, a2, b1, b2];

        // 分割せずにそのまま SpeedFilter へ渡すと、時刻が逆行するため
        // ArgumentError で落ちる（session-b の開始時刻が session-a の終端より前）。
        // これは「セッション境界をまたいで結合してはならない」ことの直接的な証拠。
        expect(
          () => SpeedFilter().classify(naiveConcat),
          throwsA(isA<ArgumentError>()),
        );

        // 正しくセッション単位に分割してから渡せば、各グループ内は
        // 時刻が非減少のため問題なく処理できる。
        final groups = splitByTrackingSession(naiveConcat);
        expect(groups, hasLength(2));

        for (final group in groups) {
          // 例外を投げずに判定できることを確認する（内容そのものは
          // speed_check_test.dart が別途検証しているためここでは検証しない）。
          expect(SpeedFilter().classify(group), hasLength(1));
        }
      },
    );
  });
}
