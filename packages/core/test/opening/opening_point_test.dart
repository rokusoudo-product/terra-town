import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// 開放ポイントを消費した未踏破ヘクスの開放可否判定
/// （[evaluateHexOpening]・Issue #151・T064・T065）のテスト。
///
/// 出典: `docs/opening_points.md` §5（開放コスト・隣接制約）・§6（開放対象範囲）・
/// Issue #151 受け入れ基準。`region_pack_test.dart` の `FakeRegionPack` と同じ
/// 手法で `RegionPack` をフェイクする（本ファイル専用に複製し、他ファイルの
/// テスト専用クラスへは依存しない）。

/// `region_pack_test.dart` の `FakeRegionPack` と同じ手法（core はフェイク実装を
/// 注入して検証できることの実証を兼ねる）。
class _FakeRegionPack implements RegionPack {
  _FakeRegionPack({
    required this.version,
    this.terrainByHex = const {},
    this.neighborsByHex = const {},
  });

  @override
  final PackVersion version;

  final Map<HexId, TerrainType> terrainByHex;
  final Map<HexId, List<HexId>> neighborsByHex;

  @override
  TerrainType? terrainOf(HexId hexId) => terrainByHex[hexId];

  @override
  DistrictId? districtOf(HexId hexId) => null;

  @override
  List<District> get districts => const [];

  @override
  List<PointOfInterest> get pointsOfInterest => const [];

  @override
  Iterable<HexId> neighborsOf(HexId hexId) => neighborsByHex[hexId] ?? const [];
}

void main() {
  const target = HexId(100);
  const neighborA = HexId(101);
  const neighborB = HexId(102);
  const farAway = HexId(9999);

  group('evaluateHexOpening（基本条件）', () {
    test('開示済みヘクスに隣接し、ポイントが足りていれば開放できる', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.forest},
        neighborsByHex: {
          target: [neighborA, neighborB],
        },
      );
      final known = DisclosedHexSet.from([neighborA]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 1,
      );

      expect(evaluation.canOpen, isTrue);
      expect(evaluation.denialReason, isNull);
      expect(evaluation.terrainType, TerrainType.forest);
    });

    test('隣接する6方向のうちどれか1つが開示済みであれば開放できる（複数のうち1件のみ既知）', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.mountain},
        neighborsByHex: {
          target: [neighborA, neighborB, const HexId(103), const HexId(104)],
        },
      );
      // neighborB だけが開示済み。
      final known = DisclosedHexSet.from([neighborB]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 5,
      );

      expect(evaluation.canOpen, isTrue);
    });

    test('飛び地（開示済みヘクスに隣接しない）は開放できない', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.forest},
        neighborsByHex: {
          target: [neighborA, neighborB],
        },
      );
      // target の隣接ヘクスはどれも known に含まれない（遠く離れた別の場所だけ既知）。
      final known = DisclosedHexSet.from([farAway]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 10,
      );

      expect(evaluation.canOpen, isFalse);
      expect(evaluation.denialReason, HexOpeningDenialReason.notAdjacentToDisclosed);
      // 拒否理由があっても地形タイプ自体はプレビュー表示のため分かる。
      expect(evaluation.terrainType, TerrainType.forest);
    });

    test('何も開示していない（known が空）状態では、あらゆるヘクスが飛び地扱いで開放できない', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.vacantLot},
        neighborsByHex: {
          target: [neighborA],
        },
      );
      final known = DisclosedHexSet();

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 50,
      );

      expect(evaluation.canOpen, isFalse);
      expect(evaluation.denialReason, HexOpeningDenialReason.notAdjacentToDisclosed);
    });

    test('ポイントが足りない場合は開放できない', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.waterside},
        neighborsByHex: {
          target: [neighborA],
        },
      );
      final known = DisclosedHexSet.from([neighborA]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 0,
      );

      expect(evaluation.canOpen, isFalse);
      expect(evaluation.denialReason, HexOpeningDenialReason.insufficientPoints);
      expect(evaluation.terrainType, TerrainType.waterside);
    });

    test('コストちょうどのポイントがあれば開放できる（1pt/メッシュ・境界値）', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.forest},
        neighborsByHex: {
          target: [neighborA],
        },
      );
      final known = DisclosedHexSet.from([neighborA]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: openingPointCostPerHex,
      );

      expect(evaluation.canOpen, isTrue);
    });

    test('既に開示済みのヘクスは開放できない（二重計上防止）', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.forest},
        neighborsByHex: {
          target: [neighborA],
        },
      );
      final known = DisclosedHexSet.from([neighborA, target]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 50,
      );

      expect(evaluation.canOpen, isFalse);
      expect(evaluation.denialReason, HexOpeningDenialReason.alreadyDisclosed);
    });

    test('地域パックに収録されていないヘクスは開放できない（地形タイプも不明）', () {
      final regionPack = _FakeRegionPack(version: const PackVersion('test'));
      final known = DisclosedHexSet.from([neighborA]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 50,
      );

      expect(evaluation.canOpen, isFalse);
      expect(evaluation.denialReason, HexOpeningDenialReason.outsidePack);
      expect(evaluation.terrainType, isNull);
    });
  });

  group('海は開放可（docs/opening_points.md §6）', () {
    test('地形タイプが海であることは開放の妨げにならない', () {
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {target: TerrainType.sea},
        neighborsByHex: {
          target: [neighborA],
        },
      );
      final known = DisclosedHexSet.from([neighborA]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 1,
      );

      expect(evaluation.canOpen, isTrue);
      expect(evaluation.terrainType, TerrainType.sea);
    });
  });

  group('⚠️ 立入禁止エリアの判定は未実装（Issue #151・2026-09-13代表決定・切り出し先#153）', () {
    test('立入禁止エリア相当のヘクスも、他の条件を満たせば現状は開放できてしまう（意図されたMVPの割り切り）', () {
      // 本テストは「立入禁止エリアを拒否する」ロジックが無いことを明示するためのもの。
      // 判定データソース（国土数値情報の指定区域データ等）が未確定なため、
      // MVPでは地形タイプに関わらず隣接・残高だけで判定する。
      // 現実の立入禁止区域に対応するヘクスをフェイクパック側で用意しても、
      // core 側には「これは立入禁止だから拒否する」という分岐が存在しない。
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        // 立入禁止エリアの地形タイプという専用の値は core に存在しない
        // （TerrainType は5種のみ。terrain_type.dart 参照）ため、通常の地形タイプで
        // 代用し、「地形タイプでは区別できない」こと自体を示す。
        terrainByHex: {target: TerrainType.vacantLot},
        neighborsByHex: {
          target: [neighborA],
        },
      );
      final known = DisclosedHexSet.from([neighborA]);

      final evaluation = evaluateHexOpening(
        hexId: target,
        regionPack: regionPack,
        known: known,
        currentPoints: 1,
      );

      expect(evaluation.canOpen, isTrue);
    });
  });

  group('歩行優位性が保たれること（spec.md §3.2・docs/opening_points.md §2.2）', () {
    test('同じ距離を「開放ポイントに換算」した場合は、実際に歩いた場合よりはるかに少ないヘクスしか開放できない', () {
      // 一直線に隣接するヘクスの列 H0-H1-...-H30（計31ヘクス）を用意する。
      // 1ヘクスの対辺 ≈ 50m（hex_geometry.dart の hexFlatToFlatMeters）を根拠に、
      // この列を端から端まで歩くと 30 * 50m = 1500m になる。
      const chainLength = 30;
      final hexes = [for (var i = 0; i <= chainLength; i++) HexId(i)];
      final neighborsByHex = <HexId, List<HexId>>{
        for (var i = 0; i <= chainLength; i++)
          hexes[i]: [
            if (i > 0) hexes[i - 1],
            if (i < chainLength) hexes[i + 1],
          ],
      };
      final regionPack = _FakeRegionPack(
        version: const PackVersion('test'),
        terrainByHex: {for (final h in hexes) h: TerrainType.vacantLot},
        neighborsByHex: neighborsByHex,
      );

      final walkedDistanceMeters = chainLength * hexFlatToFlatMeters; // 1500m

      // --- (a) 実際にこの列を歩いて開示した場合 ---
      // DisclosureService 自体の判定（1回でも訪れたヘクスは即座に開示される）は
      // disclosure_test.dart で別途検証済みのため、ここでは「歩けば地続きの
      // 31ヘクスすべてが開示される」という結果だけを直接組み立てて比較対象にする。
      final walkedHexCount = DisclosedHexSet.from(hexes).length;
      expect(walkedHexCount, chainLength + 1); // 31

      // --- (b) 同じ距離ぶんを「開放ポイントに換算」して、ポイントで開放した場合 ---
      // 換算レート 1.5km=1P（opening_point_accrual_service.dart）で、歩いたのと
      // 同じ1500mから得られる開放ポイントを計算する。
      final accrual = computeOpeningPointAccrual(
        distanceMeters: walkedDistanceMeters,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );
      expect(accrual.grantedPoints, 1); // 1500m ちょうどで1P。

      // H0 だけが既に開示済み（起点）の状態から、稼いだポイントを使って
      // 地続きに H1, H2, ... の順に開放できるだけ開放してみる。
      final openedByPoints = DisclosedHexSet.from([hexes[0]]);
      var remainingPoints = accrual.grantedPoints;
      var openedCount = 0;
      for (var i = 1; i <= chainLength && remainingPoints >= openingPointCostPerHex; i++) {
        final evaluation = evaluateHexOpening(
          hexId: hexes[i],
          regionPack: regionPack,
          known: openedByPoints,
          currentPoints: remainingPoints,
        );
        if (!evaluation.canOpen) break;
        openedByPoints.add(hexes[i]);
        remainingPoints -= openingPointCostPerHex;
        openedCount++;
      }

      // 同じ1500mでも、歩けば31ヘクスが開示されるのに対し、開放ポイント経由では
      // 1ヘクスしか開放できない。歩く方が明確に有利という spec.md §3.2 の方針、
      // および「開放ポイントは救済・補完手段であり歩行を代替するほど強くしない」
      // という docs/opening_points.md §1 の設計意図が保たれていることを示す。
      expect(openedCount, 1);
      expect(walkedHexCount, greaterThan(openedCount * 10));
    });

    test('さらに短い距離（750m）では開放ポイントが1Pにも満たず、1ヘクスも開放できない', () {
      // 750m は 1500mm換算レートの半分であり、端数として持ち越されるだけで
      // 1Pにも達しない（歩けば同じ距離で15ヘクスが地続きに開示される）。
      const chainLength = 15;
      final hexes = [for (var i = 0; i <= chainLength; i++) HexId(i)];
      final walkedDistanceMeters = chainLength * hexFlatToFlatMeters; // 750m

      final accrual = computeOpeningPointAccrual(
        distanceMeters: walkedDistanceMeters,
        rewardMultiplier: 1.0,
        currentPoints: 0,
        previousRemainderMillimeters: 0,
      );

      expect(accrual.grantedPoints, 0);
      expect(DisclosedHexSet.from(hexes).length, chainLength + 1); // 歩けば16ヘクス開示。
    });
  });
}
