import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【範囲】Issue #135 の受け入れ基準「設定値が settings テーブルに保存され、
  // アプリ再起動後も保持される」を検証する。既定値（オフ）・保存/読み出し・
  // 解釈不能な値の扱い（罰しない側＝false）を扱う。

  group('RewardSettingsRepository（インメモリDB）', () {
    late GameDatabase database;
    late RewardSettingsRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = RewardSettingsRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('既定（行が無い）はfalse＝歩数判定を使う', () async {
      expect(await repository.isStepCheckDisabled(), isFalse);
    });

    test('trueを保存すると読み出せる', () async {
      await repository.setStepCheckDisabled(true);

      expect(await repository.isStepCheckDisabled(), isTrue);
    });

    test('trueに保存した後falseに戻すと読み出せる（上書き）', () async {
      await repository.setStepCheckDisabled(true);
      await repository.setStepCheckDisabled(false);

      expect(await repository.isStepCheckDisabled(), isFalse);
    });

    test('保存キーはreward.step_check_disabled固定・値はJSONエンコードされる', () async {
      await repository.setStepCheckDisabled(true);

      final row = await (database.select(database.settings)
            ..where((t) => t.key.equals('reward.step_check_disabled')))
          .getSingle();

      expect(row.value, jsonEncode(true));
    });

    test('解釈不能な値（データ破損等）が入っていてもfalse＝罰しない側に倒す', () async {
      await database.into(database.settings).insertOnConflictUpdate(
            const SettingsCompanion(
              key: Value(RewardSettingsRepository.stepCheckDisabledKey),
              value: Value('not-a-json-bool'),
            ),
          );

      expect(await repository.isStepCheckDisabled(), isFalse);
    });

    group('buildRewardPolicy（T068への橋渡し）', () {
      test('オフ（既定）ならuseStepCheck:trueのRewardPolicyを返す', () async {
        final policy = await repository.buildRewardPolicy();
        expect(policy.useStepCheck, isTrue);
      });

      test('オンならuseStepCheck:falseのRewardPolicyを返す', () async {
        await repository.setStepCheckDisabled(true);

        final policy = await repository.buildRewardPolicy();
        expect(policy.useStepCheck, isFalse);
      });
    });
  });

  group('rewardPolicyFor（純粋関数）', () {
    test('stepCheckDisabled:falseならuseStepCheck:true', () {
      expect(rewardPolicyFor(stepCheckDisabled: false).useStepCheck, isTrue);
    });

    test('stepCheckDisabled:trueならuseStepCheck:false', () {
      expect(rewardPolicyFor(stepCheckDisabled: true).useStepCheck, isFalse);
    });
  });

  group('RewardSettingsRepository（アプリ再起動を模したファイルDBでの永続化）', () {
    test('保存後にDB接続を閉じ、同じファイルを開き直しても値が保持されている', () async {
      final tempDir = await Directory.systemTemp.createTemp('reward_settings_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File(p.join(tempDir.path, 'game_state.sqlite'));

      // --- 1回目の起動: オンに設定して終了（アプリ終了を模す） ---
      final firstRun = GameDatabase(NativeDatabase(file));
      final firstRepository = RewardSettingsRepository(firstRun);
      await firstRepository.setStepCheckDisabled(true);
      await firstRun.close();

      // --- 2回目の起動: 同じファイルを開き直す（アプリ再起動を模す） ---
      final secondRun = GameDatabase(NativeDatabase(file));
      addTearDown(secondRun.close);
      final secondRepository = RewardSettingsRepository(secondRun);

      expect(await secondRepository.isStepCheckDisabled(), isTrue);
    });
  });
}
