import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/map/economy/opening_point_accrual_coordinator.dart';
import 'package:terra_town/map/economy/terrain_yield_accrual_coordinator.dart';
import 'package:terra_town/map/economy/terrain_yield_pipeline.dart';

/// フェイクの [RegionPack]（`disclosure_coordinator_test.dart` と同じ手法）。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.terrainByHex});

  @override
  final PackVersion version = const PackVersion('test-v1');

  final Map<HexId, TerrainType> terrainByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => terrainByHex[hexId];

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];
}

/// `Repository<DisclosedHex, HexId>` のオンメモリフェイク
/// （`disclosure_coordinator_test.dart` と同じ手法）。
class _InMemoryDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  final Map<HexId, DisclosedHex> _store = {};

  @override
  Future<DisclosedHex?> findById(HexId id) async => _store[id];

  @override
  Future<List<DisclosedHex>> findAll() async => _store.values.toList();

  @override
  Future<void> save(DisclosedHex entity) async {
    _store.putIfAbsent(entity.hexId, () => entity);
  }

  @override
  Future<void> delete(HexId id) async => _store.remove(id);
}

class _FakeLedger implements TerrainYieldLedgerStore {
  int watermarkRowId = 0;
  Map<Resource, int> remainderMicros = {};
  final List<Map<Resource, int>> grantedCalls = [];

  @override
  Future<TerrainYieldLedgerSnapshot> readSnapshot() async => TerrainYieldLedgerSnapshot(
        watermarkRowId: watermarkRowId,
        remainderMicros: Map.of(remainderMicros),
      );

  @override
  Future<void> applyAccrual({
    required Map<Resource, int> grantedAmounts,
    required Map<Resource, int> remainderMicros,
    required int watermarkRowId,
  }) async {
    grantedCalls.add(grantedAmounts);
    this.watermarkRowId = watermarkRowId;
    this.remainderMicros = Map.of(remainderMicros);
  }
}

/// 開放ポイント（Issue #143）用のオンメモリフェイク実装。本テストファイルは
/// `TerrainYieldPipeline` に統合された `OpeningPointAccrualCoordinator` の詳細な
/// 挙動までは検証しない（それは
/// `app/test/map/economy/opening_point_accrual_coordinator_test.dart` の責務）。
/// ここでは単に「新しい必須引数が増えたことでコンパイルが壊れない」
/// 「地形産出のテストに影響しない」ことを確認する目的でフェイクを用意する。
class _FakeOpeningPointLedger implements OpeningPointLedgerStore {
  int watermarkRowId = 0;
  int remainderMillimeters = 0;
  int points = 0;

  @override
  Future<OpeningPointLedgerSnapshot> readSnapshot() async => OpeningPointLedgerSnapshot(
        watermarkRowId: watermarkRowId,
        remainderMillimeters: remainderMillimeters,
        points: points,
      );

  @override
  Future<void> applyAccrual({
    required int grantedPoints,
    required int remainderMillimeters,
    required int watermarkRowId,
  }) async {
    points += grantedPoints;
    this.remainderMillimeters = remainderMillimeters;
    this.watermarkRowId = watermarkRowId;
  }
}

OpeningPointAccrualCoordinator _fakeOpeningPointCoordinator() =>
    OpeningPointAccrualCoordinator(ledger: _FakeOpeningPointLedger());

LocationPointRecord _record({
  required int rowId,
  required int hexId,
  required int micros,
  String sessionId = 's',
}) {
  return LocationPointRecord(
    rowId: rowId,
    position: GeoPosition(
      latitude: 35.0,
      longitude: 135.0,
      timestamp: DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true),
      trackingSessionId: sessionId,
      hexId: HexId(hexId),
    ),
  );
}

void main() {
  group('TerrainYieldPipeline', () {
    test(
      '区間の産出には区間開始時点の開示済みヘクスを使う'
      '（新しい点の開示より先に、直前までの開示済み集合で産出を計上する）',
      () async {
        final revealed = <int>[];
        final controller = StreamController<LocationPointRecord>();
        final known = DisclosedHexSet();
        final repository = _InMemoryDisclosedHexRepository();
        final ledger = _FakeLedger();
        final terrainHexCounter = TerrainHexCounter();

        final service = DisclosureService(
          hexLocator: const RecordedHexLocator(),
          regionPack: _FakeRegionPack(
            terrainByHex: {
              const HexId(1): TerrainType.forest,
              const HexId(2): TerrainType.mountain,
            },
          ),
          known: known,
          repository: repository,
        );

        final pipeline = TerrainYieldPipeline(
          disclosureService: service,
          reveal: (featureId) async => revealed.add(featureId),
          accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: ledger),
          openingPointCoordinator: _fakeOpeningPointCoordinator(),
          terrainHexCounter: terrainHexCounter,
          disclosedHexRepository: repository,
          recordedPositionUpdates: controller.stream,
        );

        await pipeline.start();

        // 1点目: hexId=1（森）を開示する。まだ何も開示されていないので、
        // この時点の産出計上はhexCount=0（0件）で行われるはず。
        controller.add(_record(rowId: 1, hexId: 1, micros: 0));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(ledger.grantedCalls, hasLength(1));
        expect(ledger.grantedCalls.single, isEmpty); // 開示済みヘクスがまだ0件
        expect(terrainHexCounter.counts, {TerrainType.forest: 1}); // 開示された

        // 2点目: hexId=2（山）を開示する。区間 (p1, p2] の産出は
        // 「p2を開示する前」の開示済み集合＝{森1件}を使って計算されるはず
        // （山はまだ開示されていない状態で計算される）。
        controller.add(
          _record(rowId: 2, hexId: 2, micros: terrainYieldMicrosecondsPerUnit),
        );
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(ledger.grantedCalls, hasLength(2));
        // 森1件 × 1時間 = 木1個（山はまだ未開示のためカウントに含まれない）。
        expect(ledger.grantedCalls.last, {Resource.wood: 1});
        expect(terrainHexCounter.counts, {TerrainType.forest: 1, TerrainType.mountain: 1});
        expect(revealed, hasLength(2));

        await controller.close();
        await pipeline.stop();
      },
    );

    test('recordManualPosition は地形産出の計上を行わず、開示・地形カウンタの更新・revealのみ行う', () async {
      final revealed = <int>[];
      final known = DisclosedHexSet();
      final repository = _InMemoryDisclosedHexRepository();
      final ledger = _FakeLedger();
      final terrainHexCounter = TerrainHexCounter();

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: {const HexId(9): TerrainType.sea}),
        known: known,
        repository: repository,
      );

      final pipeline = TerrainYieldPipeline(
        disclosureService: service,
        reveal: (featureId) async => revealed.add(featureId),
        accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: ledger),
        openingPointCoordinator: _fakeOpeningPointCoordinator(),
        terrainHexCounter: terrainHexCounter,
        disclosedHexRepository: repository,
        recordedPositionUpdates: const Stream<LocationPointRecord>.empty(),
      );

      final disclosed = await pipeline.recordManualPosition(
        GeoPosition(latitude: 1, longitude: 1, timestamp: DateTime.now(), hexId: const HexId(9)),
      );

      expect(disclosed, isNotNull);
      expect(disclosed!.terrainType, TerrainType.sea);
      expect(terrainHexCounter.counts, {TerrainType.sea: 1});
      expect(revealed, isNotEmpty);
      expect(ledger.grantedCalls, isEmpty); // 産出の計上は行われない
    });

    test('start()を2回呼んでも購読は1つのまま（二重購読しない）', () async {
      final controller = StreamController<LocationPointRecord>();
      final known = DisclosedHexSet();
      final repository = _InMemoryDisclosedHexRepository();
      final ledger = _FakeLedger();
      final revealed = <int>[];

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: {const HexId(1): TerrainType.forest}),
        known: known,
        repository: repository,
      );

      final pipeline = TerrainYieldPipeline(
        disclosureService: service,
        reveal: (featureId) async => revealed.add(featureId),
        accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: ledger),
        openingPointCoordinator: _fakeOpeningPointCoordinator(),
        terrainHexCounter: TerrainHexCounter(),
        disclosedHexRepository: repository,
        recordedPositionUpdates: controller.stream,
      );

      await pipeline.start();
      await pipeline.start(); // 2回目は無視される

      controller.add(_record(rowId: 1, hexId: 1, micros: 0));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(revealed, [hexIdToFeatureId(1)]); // 二重購読していれば2回revealされるはず

      await controller.close();
      await pipeline.stop();
    });

    test('位置1件の処理中にエラーが発生してもパイプラインは継続する（次の位置を処理する）', () async {
      final controller = StreamController<LocationPointRecord>();
      final known = DisclosedHexSet();
      final repository = _InMemoryDisclosedHexRepository();
      final revealed = <int>[];

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: {
          const HexId(1): TerrainType.forest,
          const HexId(2): TerrainType.forest,
        }),
        known: known,
        repository: repository,
      );

      var callCount = 0;
      final pipeline = TerrainYieldPipeline(
        disclosureService: service,
        reveal: (featureId) async {
          callCount++;
          if (callCount == 1) {
            throw StateError('意図的な失敗（テスト用・1件目のrevealで発生）');
          }
          revealed.add(featureId);
        },
        accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: _FakeLedger()),
        openingPointCoordinator: _fakeOpeningPointCoordinator(),
        terrainHexCounter: TerrainHexCounter(),
        disclosedHexRepository: repository,
        recordedPositionUpdates: controller.stream,
      );

      await pipeline.start();

      controller.add(_record(rowId: 1, hexId: 1, micros: 0));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      controller.add(_record(rowId: 2, hexId: 2, micros: terrainYieldMicrosecondsPerUnit));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // 1件目はrevealで失敗したが、2件目はパイプラインが継続して処理される。
      expect(revealed, [hexIdToFeatureId(2)]);

      await controller.close();
      await pipeline.stop();
    });

    test('位置ストリームがエラーで終了すると、以後の位置は処理されない（DisclosureCoordinatorと同じ挙動）', () async {
      final controller = StreamController<LocationPointRecord>();
      final known = DisclosedHexSet();
      final repository = _InMemoryDisclosedHexRepository();
      final revealed = <int>[];

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: {const HexId(1): TerrainType.forest}),
        known: known,
        repository: repository,
      );

      final pipeline = TerrainYieldPipeline(
        disclosureService: service,
        reveal: (featureId) async => revealed.add(featureId),
        accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: _FakeLedger()),
        openingPointCoordinator: _fakeOpeningPointCoordinator(),
        terrainHexCounter: TerrainHexCounter(),
        disclosedHexRepository: repository,
        recordedPositionUpdates: controller.stream,
      );

      await pipeline.start();
      controller.addError(StateError('配線バグ相当のエラー'));
      await Future<void>.delayed(Duration.zero);

      controller.add(_record(rowId: 1, hexId: 1, micros: 0));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      // ストリームのエラーで購読が終了しているため、その後の位置は処理されない。
      expect(revealed, isEmpty);

      await controller.close();
      await pipeline.stop();
    });

    // Issue #141（現在地表示）受け入れ基準
    // 「記録サービス稼働中に位置が届くと、地図上の現在地マーカーが更新される」
    // 「位置ストリームの購読が増えていない（TerrainYieldPipelineの1本から
    // 派生している）ことがコードとテストで分かる」に対応する。
    test('currentPositionは位置1件ごとに更新される（accrue/revealの成否に関わらず）', () async {
      final controller = StreamController<LocationPointRecord>();
      final known = DisclosedHexSet();
      final repository = _InMemoryDisclosedHexRepository();

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: {const HexId(1): TerrainType.forest}),
        known: known,
        repository: repository,
      );

      final pipeline = TerrainYieldPipeline(
        disclosureService: service,
        // reveal が常に失敗しても currentPosition の更新には影響しないことを
        // あわせて検証する（クラスdoc「なぜstatsに含めず別のValueNotifierに
        // したか」参照）。
        reveal: (featureId) async => throw StateError('意図的な失敗（テスト用）'),
        accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: _FakeLedger()),
        openingPointCoordinator: _fakeOpeningPointCoordinator(),
        terrainHexCounter: TerrainHexCounter(),
        disclosedHexRepository: repository,
        recordedPositionUpdates: controller.stream,
      );

      expect(pipeline.currentPosition.value, isNull);

      await pipeline.start();

      final record = _record(rowId: 1, hexId: 1, micros: 0);
      controller.add(record);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(pipeline.currentPosition.value, record.position);

      await controller.close();
      await pipeline.stop();
    });

    test(
      'currentPositionを購読しても位置ストリーム（recordedPositionUpdates）の購読は1つのまま増えない',
      () async {
        var listenCount = 0;
        final controller = StreamController<LocationPointRecord>.broadcast(
          onListen: () => listenCount++,
        );
        final known = DisclosedHexSet();
        final repository = _InMemoryDisclosedHexRepository();
        final revealed = <int>[];

        final service = DisclosureService(
          hexLocator: const RecordedHexLocator(),
          regionPack: _FakeRegionPack(terrainByHex: {const HexId(1): TerrainType.forest}),
          known: known,
          repository: repository,
        );

        final pipeline = TerrainYieldPipeline(
          disclosureService: service,
          reveal: (featureId) async => revealed.add(featureId),
          accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: _FakeLedger()),
          openingPointCoordinator: _fakeOpeningPointCoordinator(),
          terrainHexCounter: TerrainHexCounter(),
          disclosedHexRepository: repository,
          recordedPositionUpdates: controller.stream,
        );

        await pipeline.start();
        expect(listenCount, 1);

        // 現在地表示側は pipeline.currentPosition（ValueListenable）を
        // 購読するだけで、recordedPositionUpdates を直接購読しない
        // （MapView.currentLocation の配線と同じ）。ここでは相当する操作
        // として addListener を行い、購読数（listenCount）が増えないことを
        // 確認する。
        void noop() {}
        pipeline.currentPosition.addListener(noop);

        controller.add(_record(rowId: 1, hexId: 1, micros: 0));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(listenCount, 1); // 増えていない
        expect(pipeline.currentPosition.value, isNotNull);

        pipeline.currentPosition.removeListener(noop);
        await controller.close();
        await pipeline.stop();
      },
    );

    test('recordManualPositionはcurrentPositionを更新しない（合成的な観測のため）', () async {
      final known = DisclosedHexSet();
      final repository = _InMemoryDisclosedHexRepository();

      final service = DisclosureService(
        hexLocator: const RecordedHexLocator(),
        regionPack: _FakeRegionPack(terrainByHex: {const HexId(9): TerrainType.sea}),
        known: known,
        repository: repository,
      );

      final pipeline = TerrainYieldPipeline(
        disclosureService: service,
        reveal: (featureId) async {},
        accrualCoordinator: TerrainYieldAccrualCoordinator(ledger: _FakeLedger()),
        openingPointCoordinator: _fakeOpeningPointCoordinator(),
        terrainHexCounter: TerrainHexCounter(),
        disclosedHexRepository: repository,
        recordedPositionUpdates: const Stream<LocationPointRecord>.empty(),
      );

      await pipeline.recordManualPosition(
        GeoPosition(latitude: 1, longitude: 1, timestamp: DateTime.now(), hexId: const HexId(9)),
      );

      expect(pipeline.currentPosition.value, isNull);
    });
  });
}
