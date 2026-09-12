import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  // 【範囲】Issue #143（T063）の受け入れ基準:
  // 「移動距離からポイントを計算する純粋関数があり、決定論テストがある
  // （端数が失われない・分割しても合計が同じ・上限で切り捨て）」
  // 「RewardPolicy の付与倍率が適用される（モック→0・速度超過→0・歩数不一致→0.5、
  // 設定オンなら歩数判定のみ無効）ことのテスト」の後半（倍率の重み付け）を検証する。
  // 倍率そのものの判定ロジック（RewardPolicy.classify）は reward_policy_test.dart の
  // 責務であり、本ファイルは「倍率が渡されたときにポイント計算へ正しく反映される」
  // ことのみを検証する。セッションをまたがない・二重計上防止（ウォーターマーク）は
  // `app` 側（OpeningPointAccrualCoordinator）のテストで検証する。

  group('computeOpeningPointAccrual（決定論・距離×倍率の積算）', () {
    test('1.5kmちょうど・倍率1.0で1P付与され端数は残らない', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 1500.0,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 1);
      expect(result.remainderMillimeters, 0);
      expect(result.truncatedPoints, 0);
    });

    test('750m・倍率1.0では0P・端数として750,000mmが持ち越される', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 750.0,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 0);
      expect(result.remainderMillimeters, 750000);
    });

    test('750m＋750mの端数を持ち越すと合計1.5km分＝1Pが付与される', () {
      final first = computeOpeningPointAccrual(
        distanceMeters: 750.0,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );
      final second = computeOpeningPointAccrual(
        distanceMeters: 750.0,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: first.remainderMillimeters,
      );

      expect(second.grantedPoints, 1);
      expect(second.remainderMillimeters, 0);
    });

    test('3kmちょうど・倍率1.0で2Pが付与される（距離に比例する）', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 3000.0,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 2);
      expect(result.remainderMillimeters, 0);
    });

    test('距離0では倍率に関わらず何も起きない', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 0.0,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 0);
      expect(result.remainderMillimeters, 0);
      expect(result.truncatedPoints, 0);
    });
  });

  group('付与倍率の適用（RewardPolicy.classify の出力をそのまま重みに使う）', () {
    test('倍率0（モック位置疑い・速度超過）は距離をどれだけ歩いても0P・端数も増えない', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 10000.0, // 10km歩いても
        rewardMultiplier: 0.0, // モック・速度超過は倍率0
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 0);
      expect(result.remainderMillimeters, 0);
    });

    test('倍率0.5（歩数不一致）は距離を半分として積算する', () {
      // 3km × 0.5 = 実効1.5km = 1P（「距離を半分として積算する」という
      // 実装判断。opening_point_accrual_service.dart クラスdoc「倍率0.5の
      // ときの距離の扱い」参照）。
      final result = computeOpeningPointAccrual(
        distanceMeters: 3000.0,
        rewardMultiplier: 0.5,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 1);
      expect(result.remainderMillimeters, 0);
    });

    test('倍率0.5・1.5kmちょうどでは実効750mにしかならず0Pのまま端数が残る', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 1500.0,
        rewardMultiplier: 0.5,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(result.grantedPoints, 0);
      expect(result.remainderMillimeters, 750000);
    });
  });

  group('上限（cap）での切り捨て', () {
    test('上限ちょうどに達する場合は全量付与される', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 1500.0,
        rewardMultiplier: 1.0,
        currentPoints: 49,
        previousRemainderMillimeters: 0,
        cap: 50,
      );

      expect(result.grantedPoints, 1);
      expect(result.truncatedPoints, 0);
    });

    test('既に上限に達している場合は距離を歩いても付与は0（切り捨て）', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 15000.0, // 10P相当
        rewardMultiplier: 1.0,
        currentPoints: 50,
        previousRemainderMillimeters: 0,
        cap: 50,
      );

      expect(result.grantedPoints, 0);
      expect(result.truncatedPoints, 10);
    });

    test('上限到達中でも端数（remainderMillimeters）は失われず積み上がり続ける', () {
      // 上限到達後の端数の扱い（判断の記録・opening_point_accrual_service.dart
      // クラスdoc参照）: 整数ポイントのみ切り捨て、ミリメートル単位の端数は
      // 常に正確に積み上がる。
      final result = computeOpeningPointAccrual(
        distanceMeters: 800.0,
        rewardMultiplier: 1.0,
        currentPoints: 50,
        previousRemainderMillimeters: 700000, // 700m分の端数
        cap: 50,
      );

      // 700,000mm + 800,000mm = 1,500,000mm ちょうど＝本来なら1P付与だが、
      // 上限のため付与は0・端数は0（1P分を使い切ってリセットされる）。
      expect(result.grantedPoints, 0);
      expect(result.truncatedPoints, 1);
      expect(result.remainderMillimeters, 0);
    });

    test('上限に達した状態から一部の枠しか無い場合、枠の分だけ付与し残りは切り捨てる', () {
      final result = computeOpeningPointAccrual(
        distanceMeters: 4500.0, // 3P相当
        rewardMultiplier: 1.0,
        currentPoints: 48,
        previousRemainderMillimeters: 0,
        cap: 50,
      );

      expect(result.grantedPoints, 2); // 枠は2つ分しかない
      expect(result.truncatedPoints, 1);
    });
  });

  group('分割しても合計が変わらない（区間を細かく分けた場合の等価性）', () {
    test('3kmを10分割（300mずつ）しても、合計付与量は1回で3kmを渡した場合と一致する', () {
      const totalMeters = 3000.0;
      final singleCall = computeOpeningPointAccrual(
        distanceMeters: totalMeters,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      var remainder = 0;
      var totalGranted = 0;
      var points = 0;
      const step = totalMeters / 10;
      for (var i = 0; i < 10; i++) {
        final result = computeOpeningPointAccrual(
          distanceMeters: step,
          rewardMultiplier: 1.0,
          currentPoints: points,
          previousRemainderMillimeters: remainder,
        );
        totalGranted += result.grantedPoints;
        points += result.grantedPoints;
        remainder = result.remainderMillimeters;
      }

      expect(totalGranted, singleCall.grantedPoints);
      expect(remainder, singleCall.remainderMillimeters);
    });

    test('不揃いな分割（100m・250m・400m…の合成）でも合計は一致する', () {
      const totalMeters = 5000.0 + 234.0; // 5.234km
      final singleCall = computeOpeningPointAccrual(
        distanceMeters: totalMeters,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      final steps = <double>[100.0, 250.0, 400.0, 1000.0];
      final consumed = steps.fold<double>(0, (a, b) => a + b);
      steps.add(totalMeters - consumed); // 端数調整（負にならない大きさで設計済み）
      expect(steps.last, greaterThan(0));

      var remainder = 0;
      var points = 0;
      var totalGranted = 0;
      for (final distance in steps) {
        final result = computeOpeningPointAccrual(
          distanceMeters: distance,
          rewardMultiplier: 1.0,
          currentPoints: points,
          previousRemainderMillimeters: remainder,
        );
        totalGranted += result.grantedPoints;
        points += result.grantedPoints;
        remainder = result.remainderMillimeters;
      }

      expect(totalGranted, singleCall.grantedPoints);
      expect(remainder, singleCall.remainderMillimeters);
    });
  });

  group('入力検証', () {
    test('負の距離は ArgumentError', () {
      expect(
        () => computeOpeningPointAccrual(
          distanceMeters: -1.0,
          rewardMultiplier: 1.0,
          currentPoints: 0,
          previousRemainderMillimeters: 0,
        ),
        throwsArgumentError,
      );
    });

    test('0〜1の範囲外の倍率は ArgumentError', () {
      expect(
        () => computeOpeningPointAccrual(
          distanceMeters: 100.0,
          rewardMultiplier: 1.1,
          currentPoints: 0,
          previousRemainderMillimeters: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeOpeningPointAccrual(
          distanceMeters: 100.0,
          rewardMultiplier: -0.1,
          currentPoints: 0,
          previousRemainderMillimeters: 0,
        ),
        throwsArgumentError,
      );
    });

    test('負の端数・負の所持ポイントは ArgumentError', () {
      expect(
        () => computeOpeningPointAccrual(
          distanceMeters: 100.0,
          rewardMultiplier: 1.0,
          currentPoints: 0,
          previousRemainderMillimeters: -1,
        ),
        throwsArgumentError,
      );
      expect(
        () => computeOpeningPointAccrual(
          distanceMeters: 100.0,
          rewardMultiplier: 1.0,
          currentPoints: -1,
          previousRemainderMillimeters: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
