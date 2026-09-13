import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// `location/`（`RegionPackRepository`・tasks.md T069）が SQLite から読み込んだ
/// 地域パックを、core 側では実 SQLite なしにフェイクとして注入できることの実証。
class FakeRegionPack implements RegionPack {
  FakeRegionPack({
    required this.version,
    this.terrainByHex = const {},
    this.districtByHex = const {},
    this.districts = const [],
    this.pointsOfInterest = const [],
    this.neighborsByHex = const {},
  });

  @override
  final PackVersion version;
  final Map<HexId, TerrainType> terrainByHex;
  final Map<HexId, DistrictId> districtByHex;

  @override
  final List<District> districts;

  @override
  final List<PointOfInterest> pointsOfInterest;

  /// ヘクスごとの隣接ヘクス一覧（Issue #152）。
  final Map<HexId, List<HexId>> neighborsByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => terrainByHex[hexId];

  @override
  DistrictId? districtOf(HexId hexId) => districtByHex[hexId];

  @override
  Iterable<HexId> neighborsOf(HexId hexId) => neighborsByHex[hexId] ?? const [];
}

void main() {
  group('RegionPack', () {
    test('core はフェイク実装を注入してバージョン・地形・区画・POI を読み取れる', () {
      const hex = HexId(1);
      const district = District(id: DistrictId('13101'), name: '千代田区');
      const poi = PointOfInterest(
        id: PointOfInterestId('node/1'),
        name: '六創堂神社',
        kind: 'shrine',
        latitude: 35.0,
        longitude: 135.0,
      );
      final RegionPack pack = FakeRegionPack(
        version: const PackVersion('2026-09-09-01'),
        terrainByHex: {hex: TerrainType.forest},
        districtByHex: {hex: const DistrictId('13101')},
        districts: const [district],
        pointsOfInterest: const [poi],
      );

      expect(pack.version, const PackVersion('2026-09-09-01'));
      expect(pack.terrainOf(hex), TerrainType.forest);
      expect(pack.districtOf(hex), const DistrictId('13101'));
      expect(pack.districts, [district]);
      expect(pack.pointsOfInterest, [poi]);
    });

    test('パックに収録されていないヘクスは地形・区画とも null', () {
      final RegionPack pack = FakeRegionPack(version: const PackVersion('2026-09-09-01'));

      expect(pack.terrainOf(const HexId(999)), isNull);
      expect(pack.districtOf(const HexId(999)), isNull);
    });

    test('隣接ヘクスの一覧を読み取れる（Issue #152）', () {
      const hex = HexId(1);
      const neighborA = HexId(2);
      const neighborB = HexId(3);
      final RegionPack pack = FakeRegionPack(
        version: const PackVersion('2026-09-09-01'),
        neighborsByHex: {
          hex: [neighborA, neighborB],
        },
      );

      expect(pack.neighborsOf(hex), [neighborA, neighborB]);
    });

    test('隣接関係が無いヘクス（同梱されていない・パック範囲外）は空のイテラブル', () {
      final RegionPack pack = FakeRegionPack(version: const PackVersion('2026-09-09-01'));

      expect(pack.neighborsOf(const HexId(999)), isEmpty);
    });
  });
}
