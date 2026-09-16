// BuildScreen（Issue #192・T089）のウィジェットテスト。
//
// `packages/location/test/db/inventory_repository_test.dart` と同じ
// GameDatabase.forTesting()（インメモリ）+ 実 InventoryRepository を使い、
// フェイクの Repository は作らない（`inventory_screen_test.dart` と同じ方針）。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/build/build_screen.dart';

Widget _wrap(Widget child) {
  return MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child));
}

void main() {
  group('BuildScreen', () {
    late GameDatabase database;
    late InventoryRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = InventoryRepository(database);
    });

    tearDown(() async {
      await database.close();
    });

    /// 8種の建物カード＋所持資材の一覧を、既定のテストウィンドウ（800x600）では
    /// スクロールしないと全件表示できない。`find.text` はビューポート外の
    /// 要素をビルドしない（Sliver の遅延構築）ため見つからず、テストごとに
    /// スクロール操作を書くよりウィンドウを縦に大きくする方が単純と判断した。
    void useTallTestWindow(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 3600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('8種の建物カードが表示される（docs/buildings.md §2）', (tester) async {
      useTallTestWindow(tester);
      await tester.pumpWidget(
        _wrap(
          BuildScreen(
            inventoryRepository: repository,
            onSelectBuildingToPlace: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('住宅'), findsOneWidget);
      expect(find.text('マンション'), findsOneWidget);
      expect(find.text('畑'), findsOneWidget);
      expect(find.text('農場'), findsOneWidget);
      expect(find.text('工場'), findsOneWidget);
      expect(find.text('採石場'), findsOneWidget);
      expect(find.text('リゾート'), findsOneWidget);
      expect(find.text('ミュージアム'), findsOneWidget);
    });

    testWidgets('資材が全く無いと全カードに不足の表示が出て押せない', (tester) async {
      useTallTestWindow(tester);
      await tester.pumpWidget(
        _wrap(
          BuildScreen(
            inventoryRepository: repository,
            onSelectBuildingToPlace: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 畑（木10のみ）は最も安いので、不足表示に木が含まれることを確認する。
      expect(find.textContaining('不足'), findsWidgets);
      expect(find.text('必要: 木10'), findsOneWidget); // 畑
    });

    testWidgets('コストぶんの資材があれば押せて、タップすると onSelectBuildingToPlace が呼ばれる', (
      tester,
    ) async {
      useTallTestWindow(tester);
      // 畑（木10）だけ建てられる状態にする。
      await repository.add(Resource.wood, 10);

      BuildingType? selected;
      await tester.pumpWidget(
        _wrap(
          BuildScreen(
            inventoryRepository: repository,
            onSelectBuildingToPlace: (buildingType) => selected = buildingType,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 畑カードをタップする（カード内のテキストをタップしてInkWellへ伝播させる）。
      await tester.tap(find.text('畑'));
      await tester.pumpAndSettle();

      expect(selected, BuildingType.cropField);
    });

    testWidgets('資材が足りない建物のカードをタップしても onSelectBuildingToPlace は呼ばれない', (
      tester,
    ) async {
      useTallTestWindow(tester);
      bool called = false;
      await tester.pumpWidget(
        _wrap(
          BuildScreen(
            inventoryRepository: repository,
            onSelectBuildingToPlace: (_) => called = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 住宅（木20・石10）は資材0のため building できない。
      await tester.tap(find.text('住宅'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(called, isFalse);
    });

    testWidgets('既存のInventoryScreen（所持資材の一覧）も併せて表示される（Issue #150を壊さない）', (
      tester,
    ) async {
      useTallTestWindow(tester);
      await repository.add(Resource.wood, 3);

      await tester.pumpWidget(
        _wrap(
          BuildScreen(
            inventoryRepository: repository,
            onSelectBuildingToPlace: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('所持資材'), findsOneWidget);
      expect(find.text('建設系（建物の建設・強化に使用）'), findsOneWidget);
    });
  });
}
