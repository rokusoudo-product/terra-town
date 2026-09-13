import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/map/widgets/walk_stats_hud.dart';
import 'package:terra_town/map/economy/terrain_yield_pipeline.dart';

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  // Issue #149・T062 受け入れ基準:
  //   - 記録中、歩くと HUD の距離・歩数・開放ポイントが更新される
  //   - 歩数が取得できない場合でも HUD が壊れず、歩数欄だけが出ない
  //   - 記録停止中であることが利用者に分かる
  //   - 位置ストリームへの2つ目のリスナーを追加していない（本ウィジェットは
  //     ValueListenable を受け取るだけで Stream を一切購読しない。型シグネチャ
  //     自体がその制約を表している）
  group('WalkStatsHud', () {
    testWidgets('距離・歩数・開放ポイントを表示する', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        const OpeningPointPipelineStats(
          points: 12,
          remainderMillimeters: 750000,
          watermarkRowId: 5,
          sessionDistanceMeters: 1234,
          sessionStepCount: 1800,
          sessionHasStepData: true,
        ),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.text('1.23km'), findsOneWidget);
      expect(find.text('1800歩'), findsOneWidget);
      expect(find.textContaining('開放ポイント 12/'), findsOneWidget);
      expect(find.text('記録は停止中です'), findsNothing);
    });

    testWidgets('1000m未満はメートル表示になる', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        const OpeningPointPipelineStats(
          points: 0,
          remainderMillimeters: 0,
          watermarkRowId: 1,
          sessionDistanceMeters: 42,
        ),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.text('42m'), findsOneWidget);
    });

    testWidgets('歩数が取得できない場合、歩数欄自体を表示しない（壊れて見せない）', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        const OpeningPointPipelineStats(
          points: 0,
          remainderMillimeters: 0,
          watermarkRowId: 1,
          sessionDistanceMeters: 100,
          sessionHasStepData: false,
        ),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.textContaining('歩'), findsNothing);
    });

    testWidgets('記録停止中は「記録は停止中です」を表示する', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        OpeningPointPipelineStats.initial(),
      );
      final isRecording = ValueNotifier<bool>(false);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.text('記録は停止中です'), findsOneWidget);
    });

    testWidgets('倍率0（モック位置・速度超過）の区間は「この区間は報酬対象外です」を非難しない文言で表示する',
        (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        const OpeningPointPipelineStats(
          points: 0,
          remainderMillimeters: 0,
          watermarkRowId: 2,
          sessionDistanceMeters: 100,
          lastSegmentDistanceMeters: 100,
          lastAppliedMultiplier: 0.0,
          lastReason: RewardSegmentReason.overSpeed,
        ),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.text('この区間は報酬対象外です'), findsOneWidget);
    });

    testWidgets('倍率低下（歩数不一致）の区間は「この区間は報酬が少なめです」を表示する', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        const OpeningPointPipelineStats(
          points: 0,
          remainderMillimeters: 0,
          watermarkRowId: 2,
          sessionDistanceMeters: 100,
          lastSegmentDistanceMeters: 100,
          lastAppliedMultiplier: 0.5,
          lastReason: RewardSegmentReason.stepMismatch,
        ),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.text('この区間は報酬が少なめです'), findsOneWidget);
    });

    testWidgets('直近区間の理由がnone/nullの場合、報酬に関する通知は出さない', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        const OpeningPointPipelineStats(
          points: 0,
          remainderMillimeters: 0,
          watermarkRowId: 2,
          sessionDistanceMeters: 100,
          lastSegmentDistanceMeters: 100,
          lastAppliedMultiplier: 1.0,
          lastReason: RewardSegmentReason.none,
        ),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );

      expect(find.text('この区間は報酬対象外です'), findsNothing);
      expect(find.text('この区間は報酬が少なめです'), findsNothing);
    });

    testWidgets('ValueListenableの更新に追従して再描画する', (tester) async {
      final stats = ValueNotifier<OpeningPointPipelineStats>(
        OpeningPointPipelineStats.initial(),
      );
      final isRecording = ValueNotifier<bool>(true);
      addTearDown(stats.dispose);
      addTearDown(isRecording.dispose);

      await tester.pumpWidget(
        _wrap(WalkStatsHud(openingPointStats: stats, isRecording: isRecording)),
      );
      expect(find.text('0m'), findsOneWidget);

      stats.value = const OpeningPointPipelineStats(
        points: 1,
        remainderMillimeters: 0,
        watermarkRowId: 1,
        sessionDistanceMeters: 500,
      );
      await tester.pump();

      expect(find.text('500m'), findsOneWidget);
    });
  });
}
