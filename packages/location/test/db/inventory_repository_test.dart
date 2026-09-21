import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【範囲】Issue #138 の受け入れ基準「資材が inventory テーブルに保存され、
  // 再起動後も保持される」のうち、InventoryRepository 単体の読み書きを検証する。

  group('InventoryRepository（インメモリDB）', () {
    late GameDatabase database;
    late InventoryRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = InventoryRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('既定（行が無い）は所持数0', () async {
      expect(await repository.amountOf(Resource.wood), 0);
      expect(await repository.readAll(), isEmpty);
    });

    test('addで加算した値が読み出せる', () async {
      await repository.add(Resource.wood, 3);

      expect(await repository.amountOf(Resource.wood), 3);
      expect(await repository.readAll(), {Resource.wood: 3});
    });

    test('addを複数回呼ぶと積み上がる（上書きではなく加算）', () async {
      await repository.add(Resource.stone, 2);
      await repository.add(Resource.stone, 5);

      expect(await repository.amountOf(Resource.stone), 7);
    });

    test('複数資材を独立して保持できる', () async {
      await repository.add(Resource.wood, 1);
      await repository.add(Resource.iron, 2);

      expect(await repository.readAll(), {Resource.wood: 1, Resource.iron: 2});
    });

    test('deltaが0以下なら何もしない', () async {
      await repository.add(Resource.wood, 0);
      await repository.add(Resource.wood, -5);

      expect(await repository.amountOf(Resource.wood), 0);
    });

    test('上限（cap）を適用しない（999を超えて加算できる）', () async {
      await repository.add(Resource.wood, 500);
      await repository.add(Resource.wood, 600);

      expect(await repository.amountOf(Resource.wood), 1100);
    });

    test('core の Resource enum に依存しない生の resourceKey 文字列で保存される', () async {
      await repository.add(Resource.wood, 1);

      final row = await (database.select(database.inventories)
            ..where((t) => t.resourceKey.equals('wood')))
          .getSingle();
      expect(row.amount, 1);
    });

    // 【Issue #192・T089】建設コストの支払いに使う subtract。
    group('subtract（建設コストの支払い・Issue #192）', () {
      test('所持数が足りていれば減算できる', () async {
        await repository.add(Resource.wood, 10);

        await repository.subtract(Resource.wood, 4);

        expect(await repository.amountOf(Resource.wood), 6);
      });

      test('amountが0以下なら何もしない', () async {
        await repository.add(Resource.wood, 10);

        await repository.subtract(Resource.wood, 0);
        await repository.subtract(Resource.wood, -1);

        expect(await repository.amountOf(Resource.wood), 10);
      });

      test('所持数を超える減算は StateError を投げ、値は変化しない', () async {
        await repository.add(Resource.wood, 3);

        await expectLater(
          repository.subtract(Resource.wood, 4),
          throwsA(isA<StateError>()),
        );

        expect(
          await repository.amountOf(Resource.wood),
          3,
          reason: '失敗した減算は所持数に反映されてはならない（黙ってクランプしない）',
        );
      });

      test('ちょうど所持数ぶんの減算は成功し0になる', () async {
        await repository.add(Resource.stone, 5);

        await repository.subtract(Resource.stone, 5);

        expect(await repository.amountOf(Resource.stone), 0);
      });

      test('行が無い資材（所持数0）からの減算は StateError を投げる', () async {
        await expectLater(
          repository.subtract(Resource.iron, 1),
          throwsA(isA<StateError>()),
        );
      });
    });
  });

  group('InventoryRepository（アプリ再起動を模したファイルDBでの永続化）', () {
    test('保存後にDB接続を閉じ、同じファイルを開き直しても値が保持されている', () async {
      final tempDir = await Directory.systemTemp.createTemp('inventory_repository_test');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File(p.join(tempDir.path, 'game_state.sqlite'));

      final firstRun = GameDatabase(NativeDatabase(file));
      final firstRepository = InventoryRepository(firstRun);
      await firstRepository.add(Resource.wood, 4);
      await firstRun.close();

      final secondRun = GameDatabase(NativeDatabase(file));
      addTearDown(secondRun.close);
      final secondRepository = InventoryRepository(secondRun);

      expect(await secondRepository.amountOf(Resource.wood), 4);
    });
  });
}
