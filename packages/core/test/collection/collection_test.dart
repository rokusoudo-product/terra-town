import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// 名所の収集判定（[evaluateLandmarkCollection]・T070・Issue #159）のテスト。
///
/// 出典: `docs/landmark_objects.md` §3.2・§5、Issue #159 受け入れ基準。
/// `opening_point_test.dart`・`region_pack_test.dart` の `FakeRegionPack` と
/// 同じ手法（本ファイル専用に複製し、他ファイルのテスト専用クラスへは
/// 依存しない）で `RegionPack` をフェイクする。
///
/// 【スコープ外（本ファイルでは検証しない）】
/// ボーナスオブジェクトの判定・現地訪問の差分ボーナスは `future` Issue #162 の
/// スコープであり、`evaluateLandmarkCollection` 自体がこれらを一切計算しない
/// （常に `isBonus: false`・`bonusGranted: null`）ことのみを検証する。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({
    required this.version,
    this.pointsOfInterestByHex = const {},
  });

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
  const hex = HexId(1);
  const otherHex = HexId(2);
  const version = PackVersion('test-pack');
  final disclosedHex = DisclosedHex(
    hexId: hex,
    terrainType: TerrainType.forest,
    discoveredAtVersion: version,
  );
  final collectedAt = DateTime(2026, 9, 14, 12, 0);

  const poiA = PointOfInterest(
    id: PointOfInterestId('node/1'),
    name: '六創堂神社',
    kind: 'amenity=place_of_worship',
    latitude: 35.0,
    longitude: 135.0,
    hexId: hex,
  );
  const poiB = PointOfInterest(
    id: PointOfInterestId('node/2'),
    name: '六創堂公園',
    kind: 'leisure=park',
    latitude: 35.01,
    longitude: 135.01,
    hexId: hex,
  );

  group('evaluateLandmarkCollection（基本動作）', () {
    test('徒歩で開示すると collect_method = walk で記録される', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poiA],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.walk,
        collectedAt: collectedAt,
      );

      expect(records, hasLength(1));
      final record = records.single;
      expect(record.poiId, poiA.id);
      expect(record.kind, poiA.kind);
      expect(record.name, poiA.name);
      expect(record.collectMethod, CollectMethod.walk);
      expect(record.collectedAt, collectedAt);
    });

    test('ポイント開放で開くと collect_method = point で記録される', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poiA],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.point,
        collectedAt: collectedAt,
      );

      expect(records, hasLength(1));
      expect(records.single.collectMethod, CollectMethod.point);
    });

    test('名所の無いヘクスでは何も起きない（空リスト）', () {
      final regionPack = _FakeRegionPack(version: version);

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.walk,
        collectedAt: collectedAt,
      );

      expect(records, isEmpty);
    });

    test('このヘクスに属さない他ヘクスのPOIは含めない', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          otherHex: [poiA],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.walk,
        collectedAt: collectedAt,
      );

      expect(records, isEmpty);
    });
  });

  group('evaluateLandmarkCollection（冪等性）', () {
    test('収集済みの名所は再収集しない（alreadyCollectedで除外される）', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poiA, poiB],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.walk,
        collectedAt: collectedAt,
        alreadyCollected: {poiA.id},
      );

      expect(records, hasLength(1));
      expect(records.single.poiId, poiB.id);
    });

    test('ヘクス内の全POIが収集済みなら空リストになる', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poiA],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.point,
        collectedAt: collectedAt,
        alreadyCollected: {poiA.id},
      );

      expect(records, isEmpty);
    });
  });

  group('evaluateLandmarkCollection（1ヘクスに複数の名所がある場合）', () {
    test('未収集の名所すべてについて記録が作られる', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poiA, poiB],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.walk,
        collectedAt: collectedAt,
      );

      expect(records, hasLength(2));
      expect(records.map((r) => r.poiId), containsAll(<PointOfInterestId>[poiA.id, poiB.id]));
    });
  });

  group('全件 is_bonus = false・bonus_granted = null（2026-09-13代表決定・Issue #159）', () {
    test('ボーナス関連フィールドは常に既定値のまま', () {
      final regionPack = _FakeRegionPack(
        version: version,
        pointsOfInterestByHex: {
          hex: [poiA, poiB],
        },
      );

      final records = evaluateLandmarkCollection(
        disclosedHex: disclosedHex,
        regionPack: regionPack,
        collectMethod: CollectMethod.point,
        collectedAt: collectedAt,
      );

      expect(records, isNotEmpty);
      for (final record in records) {
        expect(record.isBonus, isFalse);
        expect(record.bonusGranted, isNull);
      }
    });
  });
}
