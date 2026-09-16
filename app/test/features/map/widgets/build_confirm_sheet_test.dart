// BuildConfirmSheet（Issue #192・T089）のウィジェットテスト。
//
// `hex_opening_sheet_test.dart` と同じ「showModalBottomSheet 経由で開く」
// 構成に倣う。`onConfirm` の戻り値 `BuildResult` はコンストラクタが private の
// ため、`build_screen_test.dart`・`building_construction_service_test.dart` と
// 同様に実の `BuildingConstructionService`（`GameDatabase.forTesting()` +
// 最小限の `_FakeRegionPack`）を使い、フェイクの Repository は作らない。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/design/app_theme.dart';
import 'package:terra_town/features/map/widgets/build_confirm_sheet.dart';

/// [RegionPack.districtOf]・[RegionPack.neighborsOf] だけを設定できる最小限の
/// フェイク（`building_construction_service_test.dart` の `_FakeRegionPack` と
/// 同じ手法）。本テストは隣接条件のある建物（リゾート・ミュージアム）を
/// 対象にしないため、隣接ヘクスは常に空でよい。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.version});

  @override
  final PackVersion version;

  @override
  TerrainType? terrainOf(HexId hexId) => null;

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];

  @override
  Iterable<HexId> neighborsOf(HexId hexId) => const [];

  @override
  Iterable<PointOfInterest> pointsOfInterestIn(HexId hexId) => const [];
}

void main() {
  const hex = HexId(1);
  const version = PackVersion('test-pack');

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              builder: (context) => child,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  group('BuildConfirmSheet', () {
    late GameDatabase database;
    late DisclosedHexRepository disclosedHexRepository;
    late InventoryRepository inventoryRepository;
    late BuildingConstructionService service;

    setUp(() {
      database = GameDatabase.forTesting();
      disclosedHexRepository = DisclosedHexRepository(database);
      inventoryRepository = InventoryRepository(database);
      service = BuildingConstructionService(
        database,
        disclosedHexRepository: disclosedHexRepository,
        regionPack: _FakeRegionPack(version: version),
      );
    });

    tearDown(() async => database.close());

    Future<void> discloseVacantLot() => disclosedHexRepository.save(
      DisclosedHex(
        hexId: hex,
        terrainType: TerrainType.vacantLot,
        discoveredAtVersion: version,
      ),
    );

    testWidgets('建設できる場合: 確定すると「〜を建てました」を表示し、閉じるでシートが閉じる', (
      tester,
    ) async {
      await discloseVacantLot();
      await inventoryRepository.add(Resource.wood, 10); // 畑は木10のみ

      await tester.pumpWidget(
        wrap(
          BuildConfirmSheet(
            buildingLabel: '畑',
            terrainType: TerrainType.vacantLot,
            evaluation: BuildEvaluation.allowed(),
            onConfirm: () =>
                service.build(hexId: hex, buildingType: BuildingType.cropField),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('この場所に建てます。'), findsOneWidget);

      await tester.tap(find.text('建てる'));
      await tester.pumpAndSettle();

      expect(find.text('畑を建てました'), findsOneWidget);
      expect(await inventoryRepository.amountOf(Resource.wood), 0);

      await tester.tap(find.text('閉じる'));
      await tester.pumpAndSettle();
      expect(find.text('畑を建てました'), findsNothing);
    });

    testWidgets('プレビュー時点で拒否（既に建物がある）: 理由を表示し、建てるボタンは押せない', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BuildConfirmSheet(
            buildingLabel: '住宅',
            terrainType: TerrainType.vacantLot,
            evaluation: BuildEvaluation.denied(BuildDenialReason.alreadyBuilt),
            onConfirm: () async =>
                fail('拒否済みのプレビューでは onConfirm は呼ばれないはず'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('すでに建物が建っています'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('プレビュー時点で拒否（資材不足）: 不足している資材名と量を表示する', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          BuildConfirmSheet(
            buildingLabel: '住宅',
            terrainType: TerrainType.vacantLot,
            evaluation: BuildEvaluation.denied(
              BuildDenialReason.insufficientResources,
              missingResources: const {Resource.wood: 20, Resource.stone: 10},
            ),
            onConfirm: () async =>
                fail('拒否済みのプレビューでは onConfirm は呼ばれないはず'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.textContaining('資材が足りません'), findsOneWidget);
      expect(find.textContaining('木20'), findsOneWidget);
      expect(find.textContaining('石10'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'プレビューでは建設可能だが、確定直前に資材が減っていた場合（トランザクション再確認）: '
      '確定後に拒否理由を表示する',
      (tester) async {
        await discloseVacantLot();
        // プレビュー評価時点では建てられる想定（`evaluation: allowed()`）だが、
        // シートを開いてから確定するまでの間に資材が使われてしまった状況を
        // 再現する（`BuildingConstructionService.build` はここで改めて
        // `evaluateBuild` を実行するため、実際には拒否されるはず）。
        // 畑（木10）に必要な資材を一切持たせない。

        await tester.pumpWidget(
          wrap(
            BuildConfirmSheet(
              buildingLabel: '畑',
              terrainType: TerrainType.vacantLot,
              evaluation: BuildEvaluation.allowed(),
              onConfirm: () => service.build(
                hexId: hex,
                buildingType: BuildingType.cropField,
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        expect(find.text('この場所に建てます。'), findsOneWidget);

        await tester.tap(find.text('建てる'));
        await tester.pumpAndSettle();

        expect(find.textContaining('資材が足りません'), findsOneWidget);
        expect(find.text('畑を建てました'), findsNothing);
      },
    );
  });
}
