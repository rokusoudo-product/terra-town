// InventoryScreen（Issue #150・T076）のウィジェットテスト。
//
// 「新しい Repository は作らない」方針（Issue #150 提案内容3）のとおり、本テストも
// packages/location/test/db/inventory_repository_test.dart と同じ
// GameDatabase.forTesting()（インメモリ）+ 実 InventoryRepository を使い、
// フェイクのRepositoryは作らない。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/inventory/inventory_screen.dart';

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  group('InventoryScreen', () {
    late GameDatabase database;
    late InventoryRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = InventoryRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    testWidgets('資材が0件（ゲーム開始直後）は「まだ資材がありません」の空状態を表示する', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(InventoryScreen(inventoryRepository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('まだ資材がありません'), findsOneWidget);
      // 8種類が0のまま並ぶ「壁」にはならないこと。
      expect(find.text('木'), findsNothing);
      expect(find.text('野菜'), findsNothing);
    });

    testWidgets('所持資材があれば建設系/生活系に分けて一覧表示する', (tester) async {
      await repository.add(Resource.wood, 3);
      await repository.add(Resource.water, 5);

      await tester.pumpWidget(
        _wrap(InventoryScreen(inventoryRepository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('建設系（建物の建設・強化に使用）'), findsOneWidget);
      expect(find.text('生活系（住民/街の効率UP・人口成長に使用）'), findsOneWidget);
      expect(find.text('木'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('水'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      // まだ0の資材（石・鉄など）も一覧内には並ぶ（全体が空のときだけ空状態にする）。
      expect(find.text('石'), findsOneWidget);
      expect(find.text('0'), findsWidgets);
    });

    testWidgets('産出手段が未実装の資材（野菜・フルーツ・肉）は0でも錠前と注記で示す', (
      tester,
    ) async {
      // 空状態にならないよう、何か1つだけ加算しておく。
      await repository.add(Resource.wood, 1);

      await tester.pumpWidget(
        _wrap(InventoryScreen(inventoryRepository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('野菜'), findsOneWidget);
      expect(find.text('フルーツ'), findsOneWidget);
      expect(find.text('肉'), findsOneWidget);
      expect(find.text('建物の実装待ち'), findsNWidgets(3));
      expect(find.byIcon(Icons.lock_outline), findsNWidgets(3));
    });

    testWidgets('地形産出で資材が増えると、定期ポーリングで表示が更新される（受け入れ基準）', (
      tester,
    ) async {
      await repository.add(Resource.wood, 1);

      await tester.pumpWidget(
        _wrap(
          InventoryScreen(
            inventoryRepository: repository,
            refreshInterval: const Duration(milliseconds: 50),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('1'), findsOneWidget);

      // 画面はまだ開いたまま、DB側の所持数だけが増える
      // （地形産出コーディネータが `InventoryRepository.add` を呼ぶのと同じ形）。
      await repository.add(Resource.wood, 4); // 1 → 5

      await tester.pump(const Duration(milliseconds: 60)); // ポーリングが発火
      await tester.pump(); // setState 後の再描画を反映

      expect(find.text('5'), findsOneWidget);
      expect(find.text('1'), findsNothing);
    });

    testWidgets('読み込みに失敗した場合、エラー表示とやり直しボタンが出る', (tester) async {
      // 一度も開いていない（＝内部でまだ接続していない）DBを close しても
      // readAll() は静かに空を返すだけで例外にならないため、先に一度
      // クエリを通してDB接続を実際に開いてから close する（Drift の実装詳細）。
      await repository.add(Resource.wood, 1);
      await database.close(); // 以降の readAll() が「Bad state」で失敗するようにする

      await tester.pumpWidget(
        _wrap(InventoryScreen(inventoryRepository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.text('資材を読み込めませんでした'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'やり直す'), findsOneWidget);
    });
  });
}
