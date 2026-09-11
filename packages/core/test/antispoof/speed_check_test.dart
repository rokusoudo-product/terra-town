import 'dart:math' as math;

import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// 速度判定（[SpeedFilter]）のテスト（T096・Issue #125）。
///
/// Issue #125 本文・`speed_filter.dart` のクラスdoc「窓幅の根拠」に記載した想定を
/// そのままテストデータとして合成する:
/// - 都市部マルチパスのスパイク: 単発の悪い測位で真の位置から**約50mずれ、
///   次の測位で元の経路へ戻る**（持続的にドリフトしない）。
/// - スパイクの発生間隔: **平滑化窓（120秒）ごとに高々1回**を最悪ケースとして仮定する
///   （窓内に複数のスパイクが同時に入ると平滑化後速度も比例して上がるため、
///   「窓ごとに1回まで」が本実装が誤検出を防げると主張する範囲の境界である。
///   より高頻度のマルチパスは本実装の想定外であり、実機計測〔tasks.md T017・R5〕の
///   結果次第で窓幅・閾値の見直しが必要になりうる）。
/// - 徒歩の基準速度: 時速4〜5km。
///
/// **期待値はリテラル値で書く**（[SpeedFilter.defaultThresholdKmh] 等の定数を
/// 参照しない）。定数を参照すると、閾値やパラメータを壊したときに期待値も
/// 一緒にずれてテストが通ってしまう（Issue #50 で実際に踏んだ盲点）。
///
/// 【重要】本ファイルの多くのテストは `SpeedFilter()`（デフォルト値）を
/// 使う。これは「[SpeedFilter.defaultThresholdKmh]・[SpeedFilter.defaultSmoothingWindow]
/// を意図的に壊すとテストが落ちる」という受け入れ基準を満たすための意図的な選択で、
/// カスタム値を渡すテスト（設定可能性の検証）とは目的が異なる。

/// [_haversineMeters]（本ファイル専用の複製）が使う地球半径。
///
/// `speed_filter.dart` の `_haversineMeters` が使う値と**意図的に一致させている**
/// （private のため import できず、テスト側で複製している）。この値がテスト対象と
/// 一致していることが、本ファイルの合成ルート生成（「距離Xメートルになるよう
/// 緯度を調整する」）の正しさの前提であるため、値を変更する場合は両ファイルを
/// 同時に見直すこと。
const double _earthRadiusMeters = 6371000.0;

/// 南北方向に [meters] 移動するために必要な緯度の変化量〔度〕。
///
/// 経度を固定して緯度だけを変える区間の球面上の距離は、球の半径 × 中心角
/// （= 緯度差をラジアンに変換した値）に**厳密に一致する**（Haversine公式で
/// 経度差=0 とした場合の恒等式）。したがってこの変換は近似ではなく、
/// `speed_filter.dart` の実装と同じ地球半径を使う限り、生成した2点間の
/// 実際の距離は狙った [meters] と（浮動小数点誤差を除き）一致する。
double _latDeltaForMeters(double meters) => meters / (_earthRadiusMeters * math.pi / 180.0);

final DateTime _baseTime = DateTime.utc(2026, 9, 11, 9, 0, 0);

/// 一定速度 [speedKmh] で経度固定・南北方向に直進する合成ルートを [count] 点作る。
/// 各点は [interval] 間隔（例: 2秒）で記録されたことにする。
List<GeoPosition> _walkingRoute({
  required int count,
  required double speedKmh,
  Duration interval = const Duration(seconds: 2),
  double startLat = 35.0,
  double longitude = 135.0,
}) {
  final intervalSeconds = interval.inMicroseconds / Duration.microsecondsPerSecond;
  final metersPerStep = speedKmh / 3.6 * intervalSeconds;
  final latDeltaPerStep = _latDeltaForMeters(metersPerStep);
  return List.generate(
    count,
    (i) => GeoPosition(
      latitude: startLat + latDeltaPerStep * i,
      longitude: longitude,
      timestamp: _baseTime.add(interval * i),
    ),
  );
}

/// [route] の [index] 番目の点だけを、南北方向に [offsetMeters] ずらして
/// 「その一点だけ悪い測位が入り、次の点では元の経路（[route] の他の点は
/// 一切変更しない＝ずれた点を踏まえずに直進を続ける）へ戻る」多重パス的な
/// スパイクを注入する。戻り値は新しいリスト（[route] 自体は変更しない）。
List<GeoPosition> _withSpikeAt(List<GeoPosition> route, int index, double offsetMeters) {
  final spiked = List<GeoPosition>.of(route);
  final original = spiked[index];
  spiked[index] = GeoPosition(
    latitude: original.latitude + _latDeltaForMeters(offsetMeters),
    longitude: original.longitude,
    timestamp: original.timestamp,
  );
  return spiked;
}

/// 複数区間を持つ合成ルート（例: 徒歩→電車相当→徒歩）を1本の連続した経路として作る。
/// 各区間は直前の区間の終点から続けて直進する（区間の切り替わりでテレポートしない）。
class _Phase {
  const _Phase({required this.speedKmh, required this.steps});

  final double speedKmh;
  final int steps;
}

List<GeoPosition> _multiPhaseRoute({
  required List<_Phase> phases,
  Duration interval = const Duration(seconds: 2),
  double startLat = 35.0,
  double longitude = 135.0,
}) {
  final intervalSeconds = interval.inMicroseconds / Duration.microsecondsPerSecond;
  final positions = <GeoPosition>[
    GeoPosition(latitude: startLat, longitude: longitude, timestamp: _baseTime),
  ];
  var lat = startLat;
  var stepIndex = 0;
  for (final phase in phases) {
    final latDeltaPerStep = _latDeltaForMeters(phase.speedKmh / 3.6 * intervalSeconds);
    for (var s = 0; s < phase.steps; s++) {
      stepIndex++;
      lat += latDeltaPerStep;
      positions.add(GeoPosition(
        latitude: lat,
        longitude: longitude,
        timestamp: _baseTime.add(interval * stepIndex),
      ));
    }
  }
  return positions;
}

void main() {
  group('SpeedFilter — 平滑化後の速度による判定', () {
    test('1. 普通の歩行（時速5km）は全区間が報酬対象のまま', () {
      final route = _walkingRoute(count: 60, speedKmh: 5.0);
      final filter = SpeedFilter();

      final results = filter.classify(route);

      expect(results, hasLength(59));
      for (final segment in results) {
        expect(segment.rewardEligible, isTrue);
        expect(segment.smoothedSpeedKmh, closeTo(5.0, 0.1));
      }
    });

    test(
      '2. 都市部マルチパスのスパイク（単発50m・平滑化窓ごとに高々1回）を含む普通の歩行は、'
      'すべての区間が報酬対象のまま（誤検出しない）',
      () {
        // 460秒（231点・2秒間隔）の徒歩ルートに、140秒間隔（120秒の平滑化窓より広い）で
        // 3回スパイクを注入する。「窓（120秒）ごとに高々1回」という想定どおりの配置。
        // 最初のスパイク（t=140s）は窓（120秒=60区間）が徒歩履歴だけで満杯になった
        // 後に置く（窓がまだ温まっていない区間にスパイクを置くと、実際より薄まりが
        // 弱くなり本来より大きく見えてしまうため）。
        final baseline = _walkingRoute(count: 231, speedKmh: 5.0);
        final spikeIndexes = [70, 140, 210]; // t=140s, 280s, 420s
        var route = baseline;
        for (final index in spikeIndexes) {
          route = _withSpikeAt(route, index, 50.0);
        }
        final filter = SpeedFilter();

        final results = filter.classify(route);

        // まずスパイクが実際に生の区間速度を閾値10km/hより大幅に超えさせていることを
        // 確認する（そうでなければ「誤検出しない」ことの検証にならない）。
        final rawSpikes = results.where((s) => s.rawSpeedKmh > 50.0).toList();
        expect(rawSpikes, isNotEmpty, reason: 'スパイクが生速度に反映されていない（テストデータ不備）');

        // その上で、平滑化後の判定はすべての区間で報酬対象のまま。
        for (final segment in results) {
          expect(
            segment.rewardEligible,
            isTrue,
            reason: '${segment.from.timestamp} → ${segment.to.timestamp} '
                '(raw ${segment.rawSpeedKmh}km/h, smoothed ${segment.smoothedSpeedKmh}km/h) '
                'で誤検出した',
          );
        }
      },
    );

    test('2b. 平滑化なし（生の区間速度）で判定すると、同じスパイクが誤検出を引き起こす', () {
      final baseline = _walkingRoute(count: 231, speedKmh: 5.0);
      final route = _withSpikeAt(_withSpikeAt(_withSpikeAt(baseline, 70, 50.0), 140, 50.0), 210, 50.0);
      final filter = SpeedFilter();

      final results = filter.classify(route);

      // rawSpeedKmh は判定に使われない診断値だが、これを「生の速度でそのまま判定する」
      // 素朴な実装に見立てて閾値10km/hと比較すると、誤検出（本来は罰しないはずの
      // 普通の歩行が「移動中」と誤判定される）が起きることを示す。
      final wouldFalsePositiveIfUnsmoothed = results.where((s) => s.rawSpeedKmh > 10.0).toList();
      expect(
        wouldFalsePositiveIfUnsmoothed,
        isNotEmpty,
        reason: '平滑化なしなら誤検出するはずのスパイクが再現できていない（テストデータ不備）',
      );
      // かつ、それらの区間はいずれも平滑化後は報酬対象のまま（= 平滑化が効いている証拠）。
      for (final segment in wouldFalsePositiveIfUnsmoothed) {
        expect(segment.rewardEligible, isTrue);
        expect(segment.smoothedSpeedKmh, lessThanOrEqualTo(10.0));
      }
    });

    test('3. 静止中に同じスパイクが出ても、全区間が報酬対象のまま（速度0が基準のため、歩行時よりさらに安全側）', () {
      final baseline = _walkingRoute(count: 231, speedKmh: 0.0);
      var route = baseline;
      for (final index in [70, 140, 210]) {
        route = _withSpikeAt(route, index, 50.0);
      }
      final filter = SpeedFilter();

      final results = filter.classify(route);

      final rawSpikes = results.where((s) => s.rawSpeedKmh > 50.0).toList();
      expect(rawSpikes, isNotEmpty, reason: 'スパイクが生速度に反映されていない（テストデータ不備）');

      for (final segment in results) {
        expect(segment.rewardEligible, isTrue);
      }
    });

    test('4. 電車・車相当の持続的な移動（時速40km・200秒間）は、その区間だけ報酬なし。前後の徒歩区間は報酬あり', () {
      // 徒歩(5km/h,200秒) → 電車相当(40km/h,200秒) → 徒歩(5km/h,200秒)。
      // 区間の切り替わりでテレポートしない連続ルート（_multiPhaseRoute 参照）。
      final route = _multiPhaseRoute(phases: const [
        _Phase(speedKmh: 5.0, steps: 100),
        _Phase(speedKmh: 40.0, steps: 100),
        _Phase(speedKmh: 5.0, steps: 100),
      ]);
      final filter = SpeedFilter();

      final results = filter.classify(route);
      expect(results, hasLength(300));

      // 区間 0..99: 徒歩フェーズ。深い位置（index 80 = フェーズ開始から160秒後、
      // 窓120秒がすべて徒歩速度で埋まっている）では確実に報酬対象。
      expect(results[80].rewardEligible, isTrue);
      expect(results[80].smoothedSpeedKmh, closeTo(5.0, 0.5));

      // 区間 100..199: 電車相当フェーズ。切り替わり直後は窓に徒歩分の履歴が残るため
      // 判定が追いつくまでラグがある（クラスdoc「窓幅の根拠」の試算: 約17秒後には
      // 平滑化後速度が10km/hを超え始める）。ここでは切り替わりから100秒後
      // （index 150）という十分に深い位置で確認する。
      expect(results[150].rewardEligible, isFalse);
      expect(results[150].smoothedSpeedKmh, greaterThan(10.0));
      // フェーズ終端付近でも同様（罰則ではなく区間ごとの判定であることの確認）。
      expect(results[190].rewardEligible, isFalse);

      // 区間 200..299: 徒歩フェーズへ復帰。電車相当フェーズの履歴が窓（120秒=60区間）
      // から完全に抜けるのは復帰から120秒（60区間）以上経過した後
      // （index 200+60=260 以降）。ここでは復帰から180秒後（index 290）という
      // 十分に深い位置で、報酬対象に戻っていることを確認する。
      expect(results[290].rewardEligible, isTrue);
      expect(results[290].smoothedSpeedKmh, closeTo(5.0, 0.5));
    });

    test('5. 境界（時速10km前後）付近の扱いが決定論的である', () {
      // window=1区間だけになるよう2点だけのルートを使う（平滑化は「窓内の総距離÷
      // 窓の経過時間」だが、区間が1つしかない場合は平滑化後速度=その区間の生速度に
      // 一致する）。dt=10秒に対し、時速9.99km・10.01kmちょうどになる距離を作る。
      GeoPosition endAtSpeedKmh(double speedKmh) {
        final distanceMeters = speedKmh / 3.6 * 10.0; // dt = 10秒
        return GeoPosition(
          latitude: 35.0 + _latDeltaForMeters(distanceMeters),
          longitude: 135.0,
          timestamp: _baseTime.add(const Duration(seconds: 10)),
        );
      }

      final start = GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: _baseTime);
      final filter = SpeedFilter();

      final belowThreshold = filter.classify([start, endAtSpeedKmh(9.99)]);
      final aboveThreshold = filter.classify([start, endAtSpeedKmh(10.01)]);

      expect(belowThreshold.single.rewardEligible, isTrue);
      expect(aboveThreshold.single.rewardEligible, isFalse);

      // 決定論: 同じ入力を2回判定しても常に同じ結果になる。
      final aboveThresholdAgain = filter.classify([start, endAtSpeedKmh(10.01)]);
      expect(aboveThresholdAgain, aboveThreshold);
    });

    test('6. 同じ入力からは常に同じ判定が出る（決定論）', () {
      final baseline = _walkingRoute(count: 60, speedKmh: 5.0);
      final route = _withSpikeAt(baseline, 30, 50.0);
      final filter = SpeedFilter();

      final firstRun = filter.classify(route);
      final secondRun = filter.classify(route);

      expect(secondRun, firstRun);
      expect(firstRun, isNotEmpty);
    });

    test('7. 閾値は設定値として変更可能（正本は balance.csv ではなく本実装のコンストラクタ引数）', () {
      // 既定の10km/hでは報酬対象外になる時速15kmの持続的な移動が、
      // 閾値を20km/hに引き上げると報酬対象になることを確認する。
      final route = _walkingRoute(count: 120, speedKmh: 15.0);

      final defaultFilter = SpeedFilter();
      final raisedThresholdFilter = SpeedFilter(thresholdKmh: 20.0);

      final withDefault = defaultFilter.classify(route);
      final withRaisedThreshold = raisedThresholdFilter.classify(route);

      expect(withDefault.last.rewardEligible, isFalse);
      expect(withRaisedThreshold.last.rewardEligible, isTrue);
    });

    test('入力が2点未満なら区間を作れないため、空リストを返す', () {
      final filter = SpeedFilter();

      expect(filter.classify(const []), isEmpty);
      expect(
        filter.classify([GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: DateTime.utc(2026, 9, 11))]),
        isEmpty,
      );
    });

    test('timestamp が逆行する入力は ArgumentError を送出する（単調時計の前提違反）', () {
      final filter = SpeedFilter();
      final route = [
        GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: DateTime.utc(2026, 9, 11, 9, 0, 10)),
        GeoPosition(latitude: 35.0, longitude: 135.0, timestamp: DateTime.utc(2026, 9, 11, 9, 0, 0)),
      ];

      expect(() => filter.classify(route), throwsArgumentError);
    });
  });
}
