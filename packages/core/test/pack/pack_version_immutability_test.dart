import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// `location/`（`RegionPackRepository`・tasks.md T069）が複数バージョンの地域パックを
/// ロードした状況を、core 側では実 SQLite なしにフェイクとして注入できることの実証
/// （`packages/core/test/pack/region_pack_test.dart` の `FakeRegionPack` と同じ手法）。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({
    required this.version,
    this.terrainByHex = const {},
  });

  @override
  final PackVersion version;

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

void main() {
  group('パック更新の不変性ルール（T036・plan.md §3.3）', () {
    const hex = HexId(42);
    const v1 = PackVersion('2026-09-01-region001');
    const v2 = PackVersion('2026-09-10-region001');

    test('パック更新後も、過去に開示したヘクスの資材分類（地形タイプ）は開示当時のまま変わらない', () {
      // OSM 更新のシナリオ（Issue #84 本文）: 「昨日まで森だった土地が今日は空き地」。
      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {hex: TerrainType.forest},
      );
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {hex: TerrainType.vacantLot},
      );
      final resolver = PackVersionResolver([packV1, packV2]);
      const disclosed = DisclosedHex(hexId: hex, discoveredAtVersion: v1);

      // v1 時点で「森」として開示 → v2 更新後にパック側の分類が「空き地」に変わっても、
      // 開示済みヘクスの解決結果は開示当時の「森」のまま。
      expect(resolver.resolveTerrain(disclosed), TerrainType.forest);

      // 対比: 現在アクティブな v2 パックへ直接問い合わせれば異なる結果になる。
      // これは「新規開示（まだ disclosed_hex に無いヘクス）にのみ現行パックを使ってよい」
      // ことの裏付けであり、既に開示済みのヘクスに対してこの直接問い合わせを使うことは
      // 不変性ルール違反になる、という対比を示すためのアサーション。
      expect(packV2.terrainOf(hex), TerrainType.vacantLot);
    });

    test('獲得履歴（資材産出）もパック更新の影響を受けず開示当時のまま変わらない', () {
      // 「資材分類」の実体は terrainYieldOf（T028・純粋関数）が地形タイプから導く
      // 産出資材である。resolveTerrain が返す地形タイプさえ不変であれば、
      // terrainYieldOf は純粋関数であるため獲得資材も自動的に不変になる
      // （本テストはその連鎖が実際に成立することを確認する）。
      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {hex: TerrainType.forest}, // 森 → 木
      );
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {hex: TerrainType.vacantLot}, // 空き地 → 産出なし
      );
      final resolver = PackVersionResolver([packV1, packV2]);
      const disclosed = DisclosedHex(hexId: hex, discoveredAtVersion: v1);

      final resolvedTerrain = resolver.resolveTerrain(disclosed);
      expect(resolvedTerrain, isNotNull);
      // v2 更新後も、開示当時（v1）の地形＝森に基づく獲得資材（木）のまま。
      expect(terrainYieldOf(resolvedTerrain!), {Resource.wood});
    });

    test('パック更新をまたいでも、ヘクスごとの開示当時分類がそれぞれ独立して確定する', () {
      const hexA = HexId(1); // v1 で開示済み → v2 で分類が変わるが不変性ルールで保護される
      const hexB = HexId(2); // v2 時点で新規に地形が判明する（v1 には存在しない）

      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {hexA: TerrainType.mountain},
      );
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {
          hexA: TerrainType.vacantLot,
          hexB: TerrainType.waterside,
        },
      );
      final resolver = PackVersionResolver([packV1, packV2]);

      const disclosedA = DisclosedHex(hexId: hexA, discoveredAtVersion: v1);
      const disclosedB = DisclosedHex(hexId: hexB, discoveredAtVersion: v2);

      expect(resolver.resolveTerrain(disclosedA), TerrainType.mountain);
      expect(resolver.resolveTerrain(disclosedB), TerrainType.waterside);
    });

    test('開示当時のpack_versionに対応するRegionPackが無い場合、現行パックへ黙ってフォールバックせず例外を投げる', () {
      // v1 のパックファイルが既に破棄され、現在は v2 のみ保持している状況を想定。
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {hex: TerrainType.vacantLot},
      );
      final resolver = PackVersionResolver([packV2]);
      const disclosed = DisclosedHex(hexId: hex, discoveredAtVersion: v1);

      expect(
        () => resolver.resolveTerrain(disclosed),
        throwsA(isA<PackVersionUnavailable>()),
      );
    });

    test('DisclosedHexは「獲得履歴が当時のpack_versionで確定する」ことを型として表現する', () {
      const disclosed = DisclosedHex(hexId: hex, discoveredAtVersion: v1);

      expect(disclosed.discoveredAtVersion, v1);
      // 値オブジェクトとしての等価性（HexId・PackVersion 双方が一致すれば等しい）。
      expect(disclosed, const DisclosedHex(hexId: hex, discoveredAtVersion: v1));
      expect(
        disclosed,
        isNot(const DisclosedHex(hexId: hex, discoveredAtVersion: v2)),
      );
    });

    test('パックに収録されていないヘクスは、解決結果もnull（パック不在ではなく地形未収録）', () {
      final packV1 = _FakeRegionPack(version: v1); // hex を含まない
      final resolver = PackVersionResolver([packV1]);
      const disclosed = DisclosedHex(hexId: hex, discoveredAtVersion: v1);

      expect(resolver.resolveTerrain(disclosed), isNull);
    });
  });
}
