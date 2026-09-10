import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// `location/`（`RegionPackRepository`・tasks.md T069）が読み込んだ地域パックを、
/// core 側では実 SQLite なしにフェイクとして注入できることの実証
/// （`packages/core/test/pack/region_pack_test.dart` の `FakeRegionPack` と同じ手法）。
///
/// 「パックが更新された」状況を、同じヘクスに対して異なる [TerrainType] を返す
/// 2つの [_FakeRegionPack]（v1・v2）として表現する。
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
  group('開示時点の地形分類スナップショットによる不変性ルール（Issue #96・代表決定・案A）', () {
    const hex = HexId(42);
    const v1 = PackVersion('2026-09-01-region001');
    const v2 = PackVersion('2026-09-10-region001');

    test(
        'パック更新後も、過去に開示したヘクスの資材分類（地形タイプ）は '
        'DisclosedHex.terrainType のスナップショットのまま変わらない', () {
      // OSM 更新のシナリオ（Issue #84 本文）: 「昨日まで森だった土地が今日は空き地」。
      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {hex: TerrainType.forest},
      );
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {hex: TerrainType.vacantLot},
      );

      // 新規開示（T054 のスコープ）: 開示した瞬間に現行パック（v1）の地形分類を
      // スナップショットとして DisclosedHex に焼き込む。
      final disclosed = DisclosedHex(
        hexId: hex,
        terrainType: packV1.terrainOf(hex)!,
        discoveredAtVersion: packV1.version,
      );

      // v1 時点で「森」として開示 → v2（アプリ更新）後にパック側の分類が
      // 「空き地」に変わっても、スナップショットは開示当時の「森」のまま。
      // 【重要】v1 のパックファイルは端末から既に削除されている想定であり、
      // 本テストは v1 パックを一切参照せずにこの結果が得られることを示す
      // （旧パックを再度引く経路が無いことの実証）。
      expect(disclosed.terrainType, TerrainType.forest);

      // 対比: 現在アクティブな v2 パックへ直接問い合わせれば異なる結果になる。
      // これは「新規開示にのみ現行パックを使ってよい」ことの裏付けであり、
      // 既に開示済みのヘクスに対してこの直接問い合わせを使うことは
      // 不変性ルール違反になる、という対比を示すためのアサーション。
      expect(packV2.terrainOf(hex), TerrainType.vacantLot);
    });

    test('獲得履歴（資材産出）もパック更新の影響を受けずスナップショット当時のまま変わらない', () {
      // 「資材分類」の実体は terrainYieldOf（T028・純粋関数）が地形タイプから導く
      // 産出資材である。DisclosedHex.terrainType さえ不変であれば、terrainYieldOf は
      // 純粋関数であるため獲得資材も自動的に不変になる（本テストはその連鎖を確認する）。
      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {hex: TerrainType.forest}, // 森 → 木
      );
      final disclosed = DisclosedHex(
        hexId: hex,
        terrainType: packV1.terrainOf(hex)!,
        discoveredAtVersion: packV1.version,
      );

      // パック更新（v2 では同じヘクスが空き地＝産出なしに変わる）をシミュレート。
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {hex: TerrainType.vacantLot},
      );

      // v2 更新後も、スナップショット（v1 時点＝森）に基づく獲得資材（木）のまま。
      expect(terrainYieldOf(disclosed.terrainType), {Resource.wood});
      // 参考: v2 の現行パックを直接引けば産出0（空き地）になってしまう対比。
      expect(terrainYieldOf(packV2.terrainOf(hex)!), isEmpty);
    });

    test(
        '建築可否判定の材料（開示済みかつ空き地・docs/buildings.md §3）も '
        'パック更新をまたいで変わらない', () {
      // 【範囲の注意】ここでは「開示済みかつ空き地」の判定そのもの（T054・実際の
      // 建築可否ロジック）は実装しない。本テストが検証するのは、その判定が
      // 依拠する入力（DisclosedHex.terrainType == vacantLot かどうか）が
      // パック更新をまたいで安定していることのみ。
      const vacantHex = HexId(7);
      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {vacantHex: TerrainType.vacantLot},
      );
      final disclosedVacant = DisclosedHex(
        hexId: vacantHex,
        terrainType: packV1.terrainOf(vacantHex)!,
        discoveredAtVersion: packV1.version,
      );
      expect(disclosedVacant.terrainType, TerrainType.vacantLot);

      // アプリ更新（v2）で同じヘクスの地形分類が山に変わっても、
      // 既に空き地として開示済み＝建築済みかもしれないヘクスの判定材料は揺らがない。
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {vacantHex: TerrainType.mountain},
      );
      expect(disclosedVacant.terrainType, TerrainType.vacantLot); // 変わらない
      expect(packV2.terrainOf(vacantHex), TerrainType.mountain); // 対比: 現行パックは変化
    });

    test('採石場の山隣接ボーナス判定（Issue #72）の材料である山判定も、パック更新をまたいで変わらない', () {
      const mountainHex = HexId(9);
      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {mountainHex: TerrainType.mountain},
      );
      final disclosedMountain = DisclosedHex(
        hexId: mountainHex,
        terrainType: packV1.terrainOf(mountainHex)!,
        discoveredAtVersion: packV1.version,
      );

      // アプリ更新で山が水辺に変わっても、既に開示済みのスナップショットは山のまま。
      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {mountainHex: TerrainType.waterside},
      );
      expect(disclosedMountain.terrainType, TerrainType.mountain);
      expect(packV2.terrainOf(mountainHex), TerrainType.waterside); // 対比
    });

    test('パック更新をまたいでも、ヘクスごとの開示当時分類がそれぞれ独立して確定する', () {
      const hexA = HexId(1); // v1 で開示済み → v2 で分類が変わるが不変性ルールで保護される
      const hexB = HexId(2); // v2 時点で新規に地形が判明する（v1 には存在しない）

      final packV1 = _FakeRegionPack(
        version: v1,
        terrainByHex: {hexA: TerrainType.mountain},
      );
      final disclosedA = DisclosedHex(
        hexId: hexA,
        terrainType: packV1.terrainOf(hexA)!,
        discoveredAtVersion: packV1.version,
      );

      final packV2 = _FakeRegionPack(
        version: v2,
        terrainByHex: {
          hexA: TerrainType.vacantLot,
          hexB: TerrainType.waterside,
        },
      );
      final disclosedB = DisclosedHex(
        hexId: hexB,
        terrainType: packV2.terrainOf(hexB)!,
        discoveredAtVersion: packV2.version,
      );

      expect(disclosedA.terrainType, TerrainType.mountain);
      expect(disclosedB.terrainType, TerrainType.waterside);
    });

    test('DisclosedHexは「獲得履歴が開示時点のスナップショットで確定する」ことを型として表現する', () {
      const disclosed = DisclosedHex(
        hexId: hex,
        terrainType: TerrainType.forest,
        discoveredAtVersion: v1,
      );

      expect(disclosed.terrainType, TerrainType.forest);
      expect(disclosed.discoveredAtVersion, v1);
      // 値オブジェクトとしての等価性（HexId・TerrainType・PackVersion すべてが
      // 一致すれば等しい）。
      expect(
        disclosed,
        const DisclosedHex(
          hexId: hex,
          terrainType: TerrainType.forest,
          discoveredAtVersion: v1,
        ),
      );
      expect(
        disclosed,
        isNot(
          const DisclosedHex(
            hexId: hex,
            terrainType: TerrainType.vacantLot, // terrainType のみ異なる
            discoveredAtVersion: v1,
          ),
        ),
      );
    });
  });
}
