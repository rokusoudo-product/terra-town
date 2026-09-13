import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// `_ThrowingDisclosedHexRepository`（`hex_opening_spend_service_test.dart`）と
/// 同じ手法で [save] を意図的に失敗させ、トランザクションの原子性を検証する。
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

class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({required this.version, this.pointsOfInterestByHex = const {}});

  @override
  final PackVersion version;
  final Map<HexId, List<PointOfInterest>> pointsOfInterestByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => TerrainType.forest;

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
  const poi = PointOfInterest(
    id: PointOfInterestId('node/1'),
    name: '六創堂神社',
    kind: 'amenity=place_of_worship',
    latitude: 35.0,
    longitude: 135.0,
    hexId: hex,
  );

  group('LandmarkAwareDisclosedHexRepository（基本動作）', () {
    late GameDatabase database;

    setUp(() => database = GameDatabase.forTesting());
    tearDown(() async => database.close());

    test('名所のあるヘクスを保存すると disclosed_hex と collection（collect_method=walk）'
        'の両方が保存される', () async {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poi],
        },
      );
      List<LandmarkCollectionRecord>? notified;
      final repository = LandmarkAwareDisclosedHexRepository(
        database,
        regionPack: regionPack,
        onCollected: (records) => notified = records,
      );

      await repository.save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );

      final disclosed = await DisclosedHexRepository(database).findById(hex);
      expect(disclosed, isNotNull);

      final collected = await CollectionRepository(database).findAll();
      expect(collected, hasLength(1));
      expect(collected.single.poiId, 'node/1');
      expect(collected.single.collectMethod, CollectMethod.walk);
      expect(collected.single.name, '六創堂神社');

      expect(notified, isNotNull);
      expect(notified!.single.poiId, poi.id);
    });

    test('名所の無いヘクスを保存すると disclosed_hex のみ保存され、collection は空のまま', () async {
      final regionPack = _FakeRegionPack(version: version);
      var notifiedCount = 0;
      final repository = LandmarkAwareDisclosedHexRepository(
        database,
        regionPack: regionPack,
        onCollected: (_) => notifiedCount++,
      );

      await repository.save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );

      final disclosed = await DisclosedHexRepository(database).findById(hex);
      expect(disclosed, isNotNull);

      final collected = await CollectionRepository(database).findAll();
      expect(collected, isEmpty);
      expect(notifiedCount, 0);
    });

    test('既に開示済みのヘクスへの save は何もしない（遡及収集をしない・冪等）', () async {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poi],
        },
      );
      // 本Issue以前から開示済みだったヘクスを模す（このヘクスの名所はまだ
      // collectionに記録されていない）。
      await DisclosedHexRepository(database).save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );

      var notifiedCount = 0;
      final repository = LandmarkAwareDisclosedHexRepository(
        database,
        regionPack: regionPack,
        onCollected: (_) => notifiedCount++,
      );

      // known の復元漏れ等で万一同じヘクスに対し再度 save が呼ばれても、
      // 「既存開示済みヘクスへの遡及収集はしない」（Issue #159「対象外」）。
      await repository.save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );

      final collected = await CollectionRepository(database).findAll();
      expect(collected, isEmpty, reason: '既存開示済みヘクスの名所を遡及収集してはならない');
      expect(notifiedCount, 0);
    });

    test('収集済みの名所は再収集しない（別経路で先に収集済みの場合）', () async {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poi],
        },
      );
      // ポイント開放等、別経路で既にこのPOIが収集済みだったとする。
      await CollectionRepository(database).save(
        LandmarkCollectionRecord(
          poiId: poi.id,
          kind: poi.kind,
          name: poi.name,
          isBonus: false,
          collectedAt: DateTime(2026, 9, 1),
          collectMethod: CollectMethod.point,
          bonusGranted: null,
        ),
      );

      var notifiedCount = 0;
      final repository = LandmarkAwareDisclosedHexRepository(
        database,
        regionPack: regionPack,
        onCollected: (_) => notifiedCount++,
      );

      await repository.save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );

      final collected = await CollectionRepository(database).findAll();
      expect(collected, hasLength(1));
      expect(collected.single.collectMethod, CollectMethod.point, reason: '最初の記録が保持される');
      expect(notifiedCount, 0, reason: '新規収集は無かったので通知されない');
    });
  });

  group('LandmarkAwareDisclosedHexRepository（トランザクションの原子性）', () {
    test('収集記録の保存に失敗したら、disclosed_hex への保存もロールバックされる', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poi],
        },
      );
      final throwingCollectionRepository =
          _ThrowingCollectionRepository(CollectionRepository(database))
            ..throwOnNextSave = true;
      final repository = LandmarkAwareDisclosedHexRepository(
        database,
        regionPack: regionPack,
        collectionRepository: throwingCollectionRepository,
      );

      await expectLater(
        repository.save(
          const DisclosedHex(
            hexId: hex,
            terrainType: TerrainType.forest,
            discoveredAtVersion: version,
          ),
        ),
        throwsA(isA<StateError>()),
      );

      final disclosed = await DisclosedHexRepository(database).findById(hex);
      expect(disclosed, isNull, reason: '収集記録が失敗した以上、開示も残っていてはならない');

      final collected = await CollectionRepository(database).findAll();
      expect(collected, isEmpty);

      // 通常のリポジトリ（失敗しない）でやり直せば成功することを確認し、
      // 上記の失敗がロールバック起因であって恒久的な破損ではないことを示す。
      final normalRepository = LandmarkAwareDisclosedHexRepository(
        database,
        regionPack: regionPack,
      );
      await normalRepository.save(
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: version,
        ),
      );

      final disclosedAfterRetry = await DisclosedHexRepository(database).findById(hex);
      expect(disclosedAfterRetry, isNotNull);
      final collectedAfterRetry = await CollectionRepository(database).findAll();
      expect(collectedAfterRetry, hasLength(1));
    });
  });
}
