import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  // 【範囲】Issue #138（T066・T068）の受け入れ基準:
  // 「地形産出の純粋関数があり、決定論テストがある: 地形ごとの産出・空き地は0・
  // 端数が失われない・分割しても合計が同じ」を検証する。
  // サービス稼働中の単調時刻でのみ積算されること・セッションをまたがないこと・
  // 二重計上防止（ウォーターマーク）は呼び出し側（location/app）の責務であり、
  // `packages/location`・`app` 側のテストで検証する（本ファイルは純粋関数のみ）。

  group('computeTerrainYieldAccrual（決定論・地形ごとの産出）', () {
    test('森1ヘクス・1時間ちょうどで木1個が付与され端数は残らない', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit,
      );

      expect(result.granted, {Resource.wood: 1});
      expect(result.remainderMicros, isEmpty);
    });

    test('山1ヘクス・1時間ちょうどで石・鉄がそれぞれ1個ずつ付与される（合算されない）', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.mountain: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit,
      );

      expect(result.granted, {Resource.stone: 1, Resource.iron: 1});
    });

    test('水辺1ヘクス・1時間ちょうどで水1個が付与される', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.waterside: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit,
      );

      expect(result.granted, {Resource.water: 1});
    });

    test('海1ヘクス・1時間ちょうどで塩1個が付与される', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.sea: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit,
      );

      expect(result.granted, {Resource.salt: 1});
    });

    test('空き地は何時間経っても産出0（terrainYieldOfが空集合を返すため）', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.vacantLot: 100},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit * 100,
      );

      expect(result.granted, isEmpty);
      expect(result.remainderMicros, isEmpty);
    });

    test('開示済みヘクスが1つも無ければ経過時間が長くても何も起きない', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: const {},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit * 1000,
      );

      expect(result, same(TerrainYieldAccrual.empty));
    });

    test('森3ヘクスなら1時間で木3個（ヘクス数に比例する）', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 3},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit,
      );

      expect(result.granted, {Resource.wood: 3});
    });
  });

  group('端数（1時間未満）が失われない', () {
    test('30分経過では0個・端数として半分の時間が持ち越される', () {
      final result = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit ~/ 2,
      );

      expect(result.granted, isEmpty);
      expect(result.remainderMicros, {Resource.wood: terrainYieldMicrosecondsPerUnit ~/ 2});
    });

    test('30分＋30分の端数を持ち越すと合計1時間分＝木1個が付与される', () {
      final first = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit ~/ 2,
      );
      final second = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit ~/ 2,
        previousRemainderMicros: first.remainderMicros,
      );

      expect(second.granted, {Resource.wood: 1});
      expect(second.remainderMicros, isEmpty);
    });

    test('端数だけが持ち越され、次の呼び出しで経過時間0でも端数自体は消えない', () {
      final first = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 1},
        elapsedMicroseconds: terrainYieldMicrosecondsPerUnit ~/ 3,
      );
      final second = computeTerrainYieldAccrual(
        hexCountByTerrain: const {},
        elapsedMicroseconds: 0,
        previousRemainderMicros: first.remainderMicros,
      );

      expect(second.granted, isEmpty);
      expect(second.remainderMicros, first.remainderMicros);
    });
  });

  group('分割しても合計が変わらない（区間を細かく分けた場合の等価性）', () {
    test('1時間を60分割（1分ずつ）しても、合計付与量は1回で1時間を渡した場合と一致する', () {
      const oneHour = terrainYieldMicrosecondsPerUnit;
      final singleCall = computeTerrainYieldAccrual(
        hexCountByTerrain: {TerrainType.forest: 1},
        elapsedMicroseconds: oneHour,
      );

      var remainder = <Resource, int>{};
      var totalGranted = 0;
      final oneMinute = oneHour ~/ 60;
      for (var i = 0; i < 60; i++) {
        final step = computeTerrainYieldAccrual(
          hexCountByTerrain: {TerrainType.forest: 1},
          elapsedMicroseconds: oneMinute,
          previousRemainderMicros: remainder,
        );
        totalGranted += step.granted[Resource.wood] ?? 0;
        remainder = step.remainderMicros;
      }

      expect(totalGranted, singleCall.granted[Resource.wood]);
      expect(remainder, singleCall.remainderMicros);
    });

    test('不揃いな分割（7分・13分・40分…の合成）でも合計は一致する（複数資材・山で確認）', () {
      const totalElapsed = terrainYieldMicrosecondsPerUnit * 5 + 1234567; // 5時間+端数
      final hexCounts = {TerrainType.mountain: 4, TerrainType.forest: 2};

      final singleCall = computeTerrainYieldAccrual(
        hexCountByTerrain: hexCounts,
        elapsedMicroseconds: totalElapsed,
      );

      // 不揃いなステップ幅の合成で totalElapsed を再現する。
      final steps = <int>[
        7 * 60 * 1000000,
        13 * 60 * 1000000,
        40 * 60 * 1000000,
      ];
      var consumed = steps.fold<int>(0, (a, b) => a + b);
      steps.add(totalElapsed - consumed); // 端数調整（負にならない大きさで設計済み）
      expect(steps.last, greaterThan(0));

      var remainder = <Resource, int>{};
      final totalGranted = <Resource, int>{};
      for (final step in steps) {
        final result = computeTerrainYieldAccrual(
          hexCountByTerrain: hexCounts,
          elapsedMicroseconds: step,
          previousRemainderMicros: remainder,
        );
        result.granted.forEach((resource, amount) {
          totalGranted.update(resource, (v) => v + amount, ifAbsent: () => amount);
        });
        remainder = result.remainderMicros;
      }

      expect(totalGranted, singleCall.granted);
      expect(remainder, singleCall.remainderMicros);
    });
  });

  group('入力検証', () {
    test('負の経過時間は ArgumentError', () {
      expect(
        () => computeTerrainYieldAccrual(
          hexCountByTerrain: {TerrainType.forest: 1},
          elapsedMicroseconds: -1,
        ),
        throwsArgumentError,
      );
    });
  });

  group('TerrainHexCounter', () {
    test('initializeFromで地形ごとの件数を組み立てる', () {
      final counter = TerrainHexCounter();
      counter.initializeFrom([
        TerrainType.forest,
        TerrainType.forest,
        TerrainType.mountain,
      ]);

      expect(counter.counts, {TerrainType.forest: 2, TerrainType.mountain: 1});
    });

    test('incrementで1件ずつ加算できる', () {
      final counter = TerrainHexCounter();
      counter.increment(TerrainType.sea);
      counter.increment(TerrainType.sea);

      expect(counter.counts, {TerrainType.sea: 2});
    });

    test('countsは呼び出し側から変更できないコピーを返す', () {
      final counter = TerrainHexCounter();
      counter.increment(TerrainType.forest);

      expect(() => counter.counts[TerrainType.forest] = 99, throwsUnsupportedError);
    });

    test('initializeFromを再度呼ぶと既存の件数は破棄される', () {
      final counter = TerrainHexCounter();
      counter.increment(TerrainType.forest);
      counter.initializeFrom([TerrainType.sea]);

      expect(counter.counts, {TerrainType.sea: 1});
    });
  });
}
