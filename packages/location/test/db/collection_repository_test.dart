import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  group('CollectionRepository', () {
    late GameDatabase database;
    late CollectionRepository repository;

    setUp(() {
      database = GameDatabase.forTesting();
      repository = CollectionRepository(database);
    });

    tearDown(() async => database.close());

    test('save: 収集記録を保存し、findAll で読み出せる', () async {
      final record = LandmarkCollectionRecord(
        poiId: const PointOfInterestId('poi-1'),
        kind: 'tourism=attraction',
        name: '六創堂タワー',
        isBonus: false,
        collectedAt: DateTime(2026, 9, 14, 10),
        collectMethod: CollectMethod.walk,
        bonusGranted: null,
      );

      await repository.save(record);

      final rows = await repository.findAll();
      expect(rows, hasLength(1));
      expect(rows.single.poiId, 'poi-1');
      expect(rows.single.kind, 'tourism=attraction');
      expect(rows.single.name, '六創堂タワー');
      expect(rows.single.isBonus, isFalse);
      expect(rows.single.collectMethod, CollectMethod.walk);
      expect(rows.single.bonusGranted, isNull);
    });

    test('save: 同じ poi_id の2回目の保存は無視される（最初の記録が保持される）', () async {
      final first = LandmarkCollectionRecord(
        poiId: const PointOfInterestId('poi-1'),
        kind: 'tourism=attraction',
        name: '最初の名前',
        isBonus: false,
        collectedAt: DateTime(2026, 9, 14, 10),
        collectMethod: CollectMethod.walk,
        bonusGranted: null,
      );
      final second = LandmarkCollectionRecord(
        poiId: const PointOfInterestId('poi-1'),
        kind: 'tourism=attraction',
        name: '書き換えようとした名前',
        isBonus: false,
        collectedAt: DateTime(2026, 9, 14, 11),
        collectMethod: CollectMethod.point,
        bonusGranted: null,
      );

      await repository.save(first);
      await repository.save(second);

      final rows = await repository.findAll();
      expect(rows, hasLength(1));
      expect(rows.single.name, '最初の名前');
      expect(rows.single.collectMethod, CollectMethod.walk);
    });

    test('findCollectedIds: 保存済みのIDのみを返す', () async {
      await repository.save(
        LandmarkCollectionRecord(
          poiId: const PointOfInterestId('poi-1'),
          kind: 'tourism=attraction',
          name: 'A',
          isBonus: false,
          collectedAt: DateTime(2026, 9, 14),
          collectMethod: CollectMethod.walk,
          bonusGranted: null,
        ),
      );

      final result = await repository.findCollectedIds(const [
        PointOfInterestId('poi-1'),
        PointOfInterestId('poi-2'),
      ]);

      expect(result, {const PointOfInterestId('poi-1')});
    });

    test('findCollectedIds: 空のIDリストに対してはクエリを発行せず空集合を返す', () async {
      final result = await repository.findCollectedIds(const []);
      expect(result, isEmpty);
    });

    test('count: 保存済みの件数を返す', () async {
      expect(await repository.count(), 0);

      await repository.save(
        LandmarkCollectionRecord(
          poiId: const PointOfInterestId('poi-1'),
          kind: 'tourism=attraction',
          name: 'A',
          isBonus: false,
          collectedAt: DateTime(2026, 9, 14),
          collectMethod: CollectMethod.walk,
          bonusGranted: null,
        ),
      );

      expect(await repository.count(), 1);
    });
  });
}
