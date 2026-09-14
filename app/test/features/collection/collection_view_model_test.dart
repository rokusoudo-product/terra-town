// buildCollectionViewData（Issue #161・T075）のテスト。
//
// RegionPack は RegionPackConnection.forTesting（インメモリsqlite）で組み立て、
// `collection` の行は実際の CollectionRepository.save/findAll を通して得る
// （`packages/location/test/db/collection_repository_test.dart` と同じ方針。
// フェイクの CollectionRow を自前で作らない）。

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import 'package:terra_town/features/collection/collection_category.dart';
import 'package:terra_town/features/collection/collection_view_model.dart';

RegionPack _seededRegionPack(List<Map<String, Object?>> pois) {
  final connection = RegionPackConnection.forTesting(
    seed: (db) {
      db.execute('CREATE TABLE pack_meta (key TEXT PRIMARY KEY, value TEXT)');
      db.execute(
        "INSERT INTO pack_meta (key, value) VALUES ('pack_version', 'test-v1')",
      );
      db.execute(
        'CREATE TABLE hex_terrain ('
        'hex_id INTEGER PRIMARY KEY, terrain_type TEXT NOT NULL, '
        'feature_id INTEGER NOT NULL, cell_count INTEGER NOT NULL, '
        'boundary_geojson TEXT NOT NULL)',
      );
      db.execute(
        'CREATE TABLE poi (id TEXT PRIMARY KEY, lat REAL NOT NULL, '
        'lon REAL NOT NULL, kind TEXT NOT NULL, name TEXT NOT NULL)',
      );
      for (final poi in pois) {
        db.execute(
          'INSERT INTO poi (id, lat, lon, kind, name) VALUES (?, ?, ?, ?, ?)',
          [poi['id'], 35.0, 135.0, poi['kind'], poi['name']],
        );
      }
    },
  );
  return RegionPackRepository.load(connection);
}

void main() {
  group('buildCollectionViewData', () {
    late GameDatabase database;
    late CollectionRepository collectionRepository;

    setUp(() {
      database = GameDatabase.forTesting();
      collectionRepository = CollectionRepository(database);
    });

    tearDown(() async => database.close());

    test('カテゴリ集計: 総数の合計はパックのPOI総数と一致する', () async {
      final pack = _seededRegionPack([
        {'id': 'poi-1', 'kind': 'amenity=place_of_worship', 'name': '寺1'},
        {'id': 'poi-2', 'kind': 'amenity=place_of_worship', 'name': '寺2'},
        {'id': 'poi-3', 'kind': 'tourism=museum', 'name': '博物館1'},
        {'id': 'poi-4', 'kind': 'leisure=park', 'name': '公園1'},
      ]);

      final data = buildCollectionViewData(
        pack: pack,
        collected: await collectionRepository.findAll(),
      );

      final totalSum = data.categorySummaries.fold<int>(
        0,
        (sum, s) => sum + s.totalCount,
      );
      expect(totalSum, 4);
      expect(
        data.categorySummaries
            .firstWhere((s) => s.category == LandmarkCategory.shrineTemple)
            .totalCount,
        2,
      );
      // すべて未収集: 収集数は0
      expect(data.categorySummaries.every((s) => s.collectedCount == 0), isTrue);
    });

    test('未知の kind は「その他」カテゴリの総数に計上される（forward-compat）', () async {
      final pack = _seededRegionPack([
        {'id': 'poi-1', 'kind': 'shop=bakery', 'name': '謎の店'},
      ]);

      final data = buildCollectionViewData(
        pack: pack,
        collected: await collectionRepository.findAll(),
      );

      expect(data.categorySummaries, hasLength(1));
      expect(data.categorySummaries.single.category, LandmarkCategory.other);
      expect(data.categorySummaries.single.totalCount, 1);
    });

    test('収集済みは collection のスナップショット（name/kind）を優先する', () async {
      final pack = _seededRegionPack([
        {'id': 'poi-1', 'kind': 'tourism=museum', 'name': 'パック側の名称（古い）'},
      ]);
      await collectionRepository.save(
        LandmarkCollectionRecord(
          poiId: const PointOfInterestId('poi-1'),
          kind: 'tourism=museum',
          name: '収集時のスナップショット名',
          isBonus: false,
          collectedAt: DateTime(2026, 9, 14, 9, 30),
          collectMethod: CollectMethod.point,
          bonusGranted: null,
        ),
      );

      final data = buildCollectionViewData(
        pack: pack,
        collected: await collectionRepository.findAll(),
      );

      final entry = data.entries.single;
      expect(entry.isCollected, isTrue);
      expect(entry.name, '収集時のスナップショット名');
      expect(entry.category, LandmarkCategory.museum);
      expect(entry.collectMethod, CollectMethod.point);
      expect(entry.collectedAt, DateTime(2026, 9, 14, 9, 30));
      expect(entry.isOrphaned, isFalse);

      final summary = data.categorySummaries.single;
      expect(summary.collectedCount, 1);
      expect(summary.totalCount, 1);
    });

    test('未収集の名所は name が null（UI側で「？」に変換する契約）', () async {
      final pack = _seededRegionPack([
        {'id': 'poi-1', 'kind': 'tourism=viewpoint', 'name': '秘密の展望台'},
      ]);

      final data = buildCollectionViewData(
        pack: pack,
        collected: await collectionRepository.findAll(),
      );

      final entry = data.entries.single;
      expect(entry.isCollected, isFalse);
      expect(entry.name, isNull);
      expect(entry.collectedAt, isNull);
      expect(entry.collectMethod, isNull);
      expect(entry.category, LandmarkCategory.viewpoint);
    });

    test('パックから消えた名所（collectionにはあるがパックに無い）も一覧に出す（isOrphaned=true）', () async {
      final pack = _seededRegionPack([
        {'id': 'poi-1', 'kind': 'tourism=museum', 'name': '現存する博物館'},
      ]);
      await collectionRepository.save(
        LandmarkCollectionRecord(
          poiId: const PointOfInterestId('poi-removed'),
          kind: 'tourism=attraction',
          name: '消えた名所',
          isBonus: false,
          collectedAt: DateTime(2026, 9, 1),
          collectMethod: CollectMethod.walk,
          bonusGranted: null,
        ),
      );

      final data = buildCollectionViewData(
        pack: pack,
        collected: await collectionRepository.findAll(),
      );

      expect(data.entries, hasLength(2));
      final orphaned = data.entries.firstWhere((e) => e.poiId.value == 'poi-removed');
      expect(orphaned.isCollected, isTrue);
      expect(orphaned.isOrphaned, isTrue);
      expect(orphaned.name, '消えた名所');
      expect(orphaned.category, LandmarkCategory.attraction);

      // 総数（分母）は現在のパック基準（1件）のまま。
      final attractionSummary = data.categorySummaries.firstWhere(
        (s) => s.category == LandmarkCategory.attraction,
      );
      expect(attractionSummary.totalCount, 0);
      expect(attractionSummary.collectedCount, 1);
    });

    test('kind が null（v2以前の行）でもパック側のkindにフォールバックする', () {
      final pack = _seededRegionPack([
        {'id': 'poi-1', 'kind': 'leisure=park', 'name': '公園（パック側）'},
      ]);
      // v2以前の行を模した値（`CollectionRepository.save` は常に kind/name を
      // 書き込むため、このパターンは実DBからは再現できない。`buildCollectionViewData`
      // は `List<CollectionRow>` を受け取る純粋関数なので、値オブジェクトを直接
      // 組み立てて渡すのがもっとも素直な単体テスト方法）。
      final legacyRow = CollectionRow(
        poiId: 'poi-1',
        kind: null,
        name: null,
        isBonus: false,
        collectMethod: null,
        bonusGranted: null,
        discoveredAt: DateTime(2026, 1, 1),
      );

      final data = buildCollectionViewData(pack: pack, collected: [legacyRow]);

      final entry = data.entries.single;
      expect(entry.isCollected, isTrue);
      expect(entry.category, LandmarkCategory.park);
      // name も無い場合はパック側にフォールバックする。
      expect(entry.name, '公園（パック側）');
    });

    test('パックが空（poiテーブル無し等）でも落ちず、空の結果を返す', () async {
      final pack = _seededRegionPack(const []);

      final data = buildCollectionViewData(
        pack: pack,
        collected: await collectionRepository.findAll(),
      );

      expect(data.categorySummaries, isEmpty);
      expect(data.entries, isEmpty);
    });
  });
}
