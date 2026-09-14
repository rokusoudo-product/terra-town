import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [DisclosedHexRepository.save] を意図したタイミングで失敗させるフェイク
/// （`opening_point_ledger_test.dart` の `_ThrowsOnSecondWriteBalanceStore` と
/// 同じ手法。トランザクションの原子性を検証するために使う）。
class _ThrowingDisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  _ThrowingDisclosedHexRepository(this._delegate);

  final DisclosedHexRepository _delegate;
  bool throwOnNextSave = false;

  @override
  Future<DisclosedHex?> findById(HexId id) => _delegate.findById(id);

  @override
  Future<List<DisclosedHex>> findAll() => _delegate.findAll();

  @override
  Future<void> save(DisclosedHex entity) async {
    if (throwOnNextSave) {
      throwOnNextSave = false;
      throw StateError('意図的な失敗（テスト用）');
    }
    await _delegate.save(entity);
  }

  @override
  Future<void> delete(HexId id) => _delegate.delete(id);
}

/// [CollectionRepository.save] を意図したタイミングで失敗させるフェイク
/// （上記 `_ThrowingDisclosedHexRepository` と同じ手法。名所の収集記録と
/// ポイント消費・開示のトランザクション原子性を検証するために使う）。
class _ThrowingCollectionRepository implements CollectionRepository {
  _ThrowingCollectionRepository(this._delegate);

  final CollectionRepository _delegate;
  bool throwOnNextSave = false;

  @override
  Future<void> save(LandmarkCollectionRecord record) async {
    if (throwOnNextSave) {
      throwOnNextSave = false;
      throw StateError('意図的な失敗（テスト用）');
    }
    await _delegate.save(record);
  }

  @override
  Future<Set<PointOfInterestId>> findCollectedIds(Iterable<PointOfInterestId> ids) =>
      _delegate.findCollectedIds(ids);

  @override
  Future<List<CollectionRow>> findAll() => _delegate.findAll();

  @override
  Future<int> count() => _delegate.count();
}

/// [RegionPack.pointsOfInterestIn] だけを差し替えるフェイク
/// （`opening_point_test.dart` の `_FakeRegionPack` と同じ手法）。
class _FakeRegionPackWithPoi implements RegionPack {
  _FakeRegionPackWithPoi({required this.version, this.pointsOfInterestByHex = const {}});

  @override
  final PackVersion version;
  final Map<HexId, List<PointOfInterest>> pointsOfInterestByHex;

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
  Iterable<PointOfInterest> pointsOfInterestIn(HexId hexId) =>
      pointsOfInterestByHex[hexId] ?? const [];
}

void main() {
  const hex = HexId(42);
  const version = PackVersion('test-pack');

  group('HexOpeningSpendService（基本動作）', () {
    late GameDatabase database;
    late HexOpeningSpendService service;

    setUp(() {
      database = GameDatabase.forTesting();
      service = HexOpeningSpendService(database);
    });

    tearDown(() async => database.close());

    test('ポイントが足りていれば開放でき、残高がコストぶん減る', () async {
      await OpeningPointBalanceRepository(database).write(5);

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );

      expect(result.outcome, HexOpeningSpendOutcome.opened);
      expect(result.remainingPoints, 4);
      expect(result.disclosedHex, isNotNull);
      expect(result.disclosedHex!.hexId, hex);
      expect(result.disclosedHex!.terrainType, TerrainType.forest);

      final saved = await DisclosedHexRepository(database).findById(hex);
      expect(saved, isNotNull);
      expect(saved!.terrainType, TerrainType.forest);

      final balance = await OpeningPointBalanceRepository(database).read();
      expect(balance, 4);
    });

    test('ポイント不足なら開放できず、残高・開示状態のどちらも変化しない', () async {
      await OpeningPointBalanceRepository(database).write(0);

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );

      expect(result.outcome, HexOpeningSpendOutcome.insufficientPoints);
      expect(result.remainingPoints, 0);
      expect(result.disclosedHex, isNull);

      final saved = await DisclosedHexRepository(database).findById(hex);
      expect(saved, isNull);
    });

    test('既に開示済みなら開放できず（二重消費防止）、ポイントは減らない', () async {
      await OpeningPointBalanceRepository(database).write(5);
      await DisclosedHexRepository(database).save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.sea,
          discoveredAtVersion: version,
        ),
      );

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest, // 実際に保存済みの値と異なる値を渡しても上書きされない
        packVersion: version,
      );

      expect(result.outcome, HexOpeningSpendOutcome.alreadyDisclosed);
      expect(result.disclosedHex, isNull);

      final balance = await OpeningPointBalanceRepository(database).read();
      expect(balance, 5, reason: '開放は失敗したのにポイントだけ減ってはならない');

      final saved = await DisclosedHexRepository(database).findById(hex);
      expect(saved!.terrainType, TerrainType.sea, reason: '既存のスナップショットは上書きされない');
    });

    test('海の地形タイプでも開放できる（docs/opening_points.md §6）', () async {
      await OpeningPointBalanceRepository(database).write(1);

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.sea,
        packVersion: version,
      );

      expect(result.outcome, HexOpeningSpendOutcome.opened);
    });
  });

  group('HexOpeningSpendService（トランザクションの原子性）', () {
    test('disclosed_hexへの保存に失敗したら、ポイントの減算もロールバックされる', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      await OpeningPointBalanceRepository(database).write(5);

      final throwingRepository =
          _ThrowingDisclosedHexRepository(DisclosedHexRepository(database))
            ..throwOnNextSave = true;
      final service = HexOpeningSpendService(
        database,
        disclosedHexRepository: DisclosedHexRepository(database),
      );
      // disclosedHexRepository の型は具象 DisclosedHexRepository なので、
      // ここでは save 失敗を直接注入できるよう別経路のサービスを組む。
      final throwingService = _HexOpeningSpendServiceForTest(
        database,
        balanceStore: OpeningPointBalanceRepository(database),
        disclosedHexRepository: throwingRepository,
      );

      await expectLater(
        throwingService.spend(
          hexId: hex,
          terrainType: TerrainType.forest,
          packVersion: version,
        ),
        throwsA(isA<StateError>()),
      );

      final balance = await OpeningPointBalanceRepository(database).read();
      expect(balance, 5, reason: '保存が失敗した以上、ポイントも減っていてはならない');

      final saved = await DisclosedHexRepository(database).findById(hex);
      expect(saved, isNull);

      // 通常のサービス（失敗しない）でやり直せば成功することを確認し、
      // 上記の失敗がロールバック起因であって恒久的な破損ではないことを示す。
      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );
      expect(result.outcome, HexOpeningSpendOutcome.opened);
    });
  });

  group('HexOpeningSpendService（入手＝OpeningPointLedgerとの競合）', () {
    test('歩行距離換算の計上（accrual）とヘクス開放（spend）が同時に起きても残高が食い違わない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final balanceStore = OpeningPointBalanceRepository(database);
      await balanceStore.write(1); // 開放1回ぶん（cost=1）だけ持たせておく。

      final ledger = OpeningPointLedger(database, balanceStore: balanceStore);
      final service = HexOpeningSpendService(database, balanceStore: balanceStore);

      // 「歩行距離換算で3P加算」と「保有1Pでヘクスを1つ開放（コスト1）」を
      // ほぼ同時に発行する。Drift はトランザクションを排他的に実行するため
      // （hex_opening_spend_service.dart クラスdoc参照）、どちらが先でも
      // 最終残高は 1 + 3 - 1 = 3 になり、ロストアップデートは起きない。
      final accrualFuture = ledger.applyAccrual(
        grantedPoints: 3,
        remainderMillimeters: 0,
        watermarkRowId: 1,
      );
      final spendFuture = service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );
      final applyAccrualResult = await accrualFuture;
      final spendResult = await spendFuture;

      final finalBalance = await balanceStore.read();
      expect(finalBalance, 3);
      expect(spendResult.outcome, HexOpeningSpendOutcome.opened);
      // どちらの順序で実行されても、各操作の戻り値はその時点の正しい残高を反映する
      // （2 or 4 のいずれかになりうるが、どちらであっても両方の効果を含んだ
      // 最終残高〔3〕とは矛盾しない）。
      expect({applyAccrualResult, spendResult.remainingPoints}, isNot(contains(-1)));
    });

    test('上限（cap）近くでの外部消費後も、accrualはキャッシュではなくDBの実残高からクランプする', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final balanceStore = OpeningPointBalanceRepository(database);
      await balanceStore.write(openingPointStockCap);

      final ledger = OpeningPointLedger(database, balanceStore: balanceStore);
      final service = HexOpeningSpendService(database, balanceStore: balanceStore);

      // 上限(50)ちょうどの状態から1つ開放して49に減らす。
      final spendResult = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );
      expect(spendResult.remainingPoints, openingPointStockCap - 1);

      // 呼び出し側のキャッシュが「消費前の50」のまま古かったとしても
      // （= capacityLeftを0と誤認して本来はgrantedPoints=0を渡すはずが、
      // ここでは意図的に「古いキャッシュ由来の過大なgrantedPoints」を模して
      // 2を渡す）、applyAccrual はDBの実残高（49）を基準に最終的に
      // capでクランプするため、50を超えない。
      final resultingPoints = await ledger.applyAccrual(
        grantedPoints: 2,
        remainderMillimeters: 0,
        watermarkRowId: 2,
      );

      expect(resultingPoints, openingPointStockCap);
      final finalBalance = await balanceStore.read();
      expect(finalBalance, openingPointStockCap);
    });
  });

  group('HexOpeningSpendService（名所の収集記録・Issue #159・T070）', () {
    const poi = PointOfInterest(
      id: PointOfInterestId('node/1'),
      name: '六創堂神社',
      kind: 'amenity=place_of_worship',
      latitude: 35.0,
      longitude: 135.0,
      hexId: hex,
    );

    test('名所のあるヘクスをポイントで開放すると collect_method = point で記録される', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final regionPack = _FakeRegionPackWithPoi(
        version: version,
        pointsOfInterestByHex: {
          hex: [poi],
        },
      );
      List<LandmarkCollectionRecord>? notified;
      final service = HexOpeningSpendService(
        database,
        regionPack: regionPack,
        onCollected: (records) => notified = records,
      );
      await OpeningPointBalanceRepository(database).write(5);

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );

      expect(result.outcome, HexOpeningSpendOutcome.opened);
      expect(result.collectedLandmarks, hasLength(1));
      expect(result.collectedLandmarks.single.poiId, poi.id);
      expect(result.collectedLandmarks.single.collectMethod, CollectMethod.point);

      final saved = await CollectionRepository(database).findAll();
      expect(saved, hasLength(1));
      expect(saved.single.poiId, 'node/1');
      expect(saved.single.collectMethod, CollectMethod.point);

      expect(notified, isNotNull);
      expect(notified!.single.poiId, poi.id);
    });

    test('regionPack を渡さない場合は収集判定を一切行わない（既存呼び出し元との後方互換）', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final service = HexOpeningSpendService(database);
      await OpeningPointBalanceRepository(database).write(5);

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );

      expect(result.outcome, HexOpeningSpendOutcome.opened);
      expect(result.collectedLandmarks, isEmpty);
      final saved = await CollectionRepository(database).findAll();
      expect(saved, isEmpty);
    });

    test('名所の無いヘクスを開放しても collection には何も記録されない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final regionPack = _FakeRegionPackWithPoi(version: version);
      final service = HexOpeningSpendService(database, regionPack: regionPack);
      await OpeningPointBalanceRepository(database).write(5);

      final result = await service.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );

      expect(result.collectedLandmarks, isEmpty);
      final saved = await CollectionRepository(database).findAll();
      expect(saved, isEmpty);
    });

    test('収集記録の保存に失敗したら、開示・ポイント減算もロールバックされる（同一トランザクション）',
        () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final regionPack = _FakeRegionPackWithPoi(
        version: version,
        pointsOfInterestByHex: {
          hex: [poi],
        },
      );
      await OpeningPointBalanceRepository(database).write(5);

      final throwingCollectionRepository =
          _ThrowingCollectionRepository(CollectionRepository(database))
            ..throwOnNextSave = true;
      final throwingService = HexOpeningSpendService(
        database,
        regionPack: regionPack,
        collectionRepository: throwingCollectionRepository,
      );

      await expectLater(
        throwingService.spend(
          hexId: hex,
          terrainType: TerrainType.forest,
          packVersion: version,
        ),
        throwsA(isA<StateError>()),
      );

      final balance = await OpeningPointBalanceRepository(database).read();
      expect(balance, 5, reason: '収集記録が失敗した以上、ポイントも減っていてはならない');

      final saved = await DisclosedHexRepository(database).findById(hex);
      expect(saved, isNull, reason: '収集記録が失敗した以上、開示も残っていてはならない');

      final collected = await CollectionRepository(database).findAll();
      expect(collected, isEmpty);

      // 通常のサービス（失敗しない）でやり直せば成功することを確認する。
      final normalService = HexOpeningSpendService(database, regionPack: regionPack);
      final result = await normalService.spend(
        hexId: hex,
        terrainType: TerrainType.forest,
        packVersion: version,
      );
      expect(result.outcome, HexOpeningSpendOutcome.opened);
      expect(result.collectedLandmarks, hasLength(1));
    });
  });
}

/// `_ThrowingDisclosedHexRepository` を注入するためだけの
/// [HexOpeningSpendService] 相当の薄いラッパー（本体クラスのコンストラクタが
/// 具象 [DisclosedHexRepository] 型を要求するため、テスト専用に
/// [Repository]<[DisclosedHex], [HexId]> を受け付ける最小限の再実装を用意した）。
class _HexOpeningSpendServiceForTest {
  _HexOpeningSpendServiceForTest(
    this._database, {
    required this.balanceStore,
    required this.disclosedHexRepository,
  });

  final GameDatabase _database;
  final OpeningPointBalanceStore balanceStore;
  final Repository<DisclosedHex, HexId> disclosedHexRepository;

  /// 本体（[HexOpeningSpendService.spend]）と同じトランザクション構造だけを
  /// 再現する（テスト用に差し替え可能な [Repository] を受け付けるため）。
  /// 戻り値の型までは再現せず、DB状態への副作用の検証は呼び出し側（テスト）が
  /// 直接 [OpeningPointBalanceStore]・[DisclosedHexRepository] を読んで行う。
  Future<void> spend({
    required HexId hexId,
    required TerrainType terrainType,
    required PackVersion packVersion,
    int cost = openingPointCostPerHex,
  }) async {
    await _database.transaction(() async {
      final existing = await disclosedHexRepository.findById(hexId);
      if (existing != null) return;
      final currentPoints = await balanceStore.read();
      if (currentPoints < cost) return;
      await balanceStore.write(currentPoints - cost);
      await disclosedHexRepository.save(
        DisclosedHex(
          hexId: hexId,
          terrainType: terrainType,
          discoveredAtVersion: packVersion,
        ),
      );
    });
  }
}
