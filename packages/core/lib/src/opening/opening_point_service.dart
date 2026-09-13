import '../geo/hex_id.dart';
import '../pack/disclosed_hex_set.dart';
import '../pack/region_pack.dart';
import '../terrain/terrain_type.dart';

/// 開放ポイントで未踏破ヘクスを1件開放するのに必要なコスト（メッシュ単位・固定）。
///
/// 出典: `docs/opening_points.md` §5.1「地形タイプに関わらず一律 1pt/メッシュ
/// （固定）」（2026-07-22 代表回答）。距離に応じた逓増は§5.2の隣接制約により
/// 不要と確定している（同節参照）。
const int openingPointCostPerHex = 1;

/// [evaluateHexOpening] がヘクスの開放を拒否した理由（Issue #151・T064）。
enum HexOpeningDenialReason {
  /// このヘクスは地域パックに収録されていない（[RegionPack.terrainOf] が null）。
  outsidePack,

  /// 既に開示済み（[DisclosedHexSet.contains]）。
  alreadyDisclosed,

  /// 開示済みヘクスに隣接していない（飛び地。`docs/opening_points.md` §5.2）。
  notAdjacentToDisclosed,

  /// 所持ポイントがコスト（[openingPointCostPerHex]）に満たない。
  insufficientPoints,
}

/// [evaluateHexOpening] の戻り値。
///
/// 「開放できるか」だけでなく、UI がその場で理由を示せるよう拒否理由
/// （[denialReason]）と、パック内のヘクスであれば分かる地形タイプ
/// （[terrainType]。UIのプレビュー表示用。[outsidePack] の場合のみ null）を
/// 保持する。
class HexOpeningEvaluation {
  const HexOpeningEvaluation._({
    required this.canOpen,
    this.denialReason,
    this.terrainType,
  }) : assert(
          (canOpen && denialReason == null) || (!canOpen && denialReason != null),
          'canOpen と denialReason は排他的であること',
        );

  /// このヘクスをいま開放できるか。
  final bool canOpen;

  /// 開放できない場合の理由（[canOpen] が true の場合は null）。
  final HexOpeningDenialReason? denialReason;

  /// このヘクスの地形タイプ（パック範囲外の場合のみ null）。
  ///
  /// [canOpen] が true の場合、呼び出し側（`location/`）はこの値を
  /// `DisclosedHex.terrainType` のスナップショットとして使うこと
  /// （[RegionPack.terrainOf] を呼んでよいのは新規開示の瞬間だけ、という
  /// `region_pack.dart` の制約を守るため、本関数の呼び出し１回に集約する）。
  final TerrainType? terrainType;

  factory HexOpeningEvaluation.allowed(TerrainType terrainType) =>
      HexOpeningEvaluation._(canOpen: true, terrainType: terrainType);

  factory HexOpeningEvaluation.denied(
    HexOpeningDenialReason reason, {
    TerrainType? terrainType,
  }) =>
      HexOpeningEvaluation._(
        canOpen: false,
        denialReason: reason,
        terrainType: terrainType,
      );

  @override
  String toString() =>
      'HexOpeningEvaluation(canOpen: $canOpen, denialReason: $denialReason, '
      'terrainType: $terrainType)';
}

/// 開放ポイントを消費して [hexId] を開放できるかを判定する決定論的な純粋関数
/// （Issue #151・T064）。
///
/// 出典: `docs/opening_points.md` §5「開放コスト（1pt/メッシュ）と隣接制約」・
/// §6「開放対象範囲（海と実在の立入禁止エリアの区別）」。
///
/// ## 判定順序（複数の理由が同時に成り立つ場合、最初に検出したものを返す）
/// 1. [outsidePack]: [regionPack] にこのヘクスの地形分類が無い
///    （[RegionPack.terrainOf] が null）。隣接・残高より前に確認する
///    （地形タイプが決まらないと [HexOpeningEvaluation.terrainType] を
///    組み立てられないため）。
/// 2. [alreadyDisclosed]: [known] に含まれる（既に開示済み）。
/// 3. [notAdjacentToDisclosed]: [RegionPack.neighborsOf] のいずれも [known]
///    に含まれない（飛び地）。**[known] が空（まだ何も開示していない）の
///    場合も、あらゆるヘクスがこの理由で拒否される** —— 最初の1マスは
///    必ず歩行で開示する必要があり、これは「遠隔地へのワープ的な開放を
///    防ぐ」という §5.2 の意図どおりの挙動である。
/// 4. [insufficientPoints]: [currentPoints] が [cost] 未満。
///
/// この判定順序は「隣接している」ことを「ポイントが足りている」ことより
/// 優先して伝える——ポイントを貯めても地続きでなければ開放できないという
/// 制約の方が本質的だと判断したため（順序自体はUI表示のためだけの決め事で
/// あり、拒否理由が単一である限り結果に影響しない）。
///
/// ## 海は開放可（`docs/opening_points.md` §6）
/// [TerrainType.sea] であることを理由に拒否する分岐は無い
/// （地形タイプによらず上記4条件だけで判定する）。
///
/// ## ⚠️ 実在の立入禁止エリアの判定は未実装（重要・Issue #151・代表決定）
/// `docs/opening_points.md` §6 が定める「実在の立入禁止エリア（軍事施設・
/// 私有地・危険区域等）は開放不可・産出なし・黒塗り表示」は、**本関数を含め
/// MVP のどこにも実装されていない**。2026-09-13 代表決定（Issue #151 コメント）:
/// 判定データソースが未確定（同§6「plan 工程で確定」のまま）であり、調査と
/// ライセンス確認（Issue #37）まで含めると本Issueの規模が倍以上になるため、
/// MVP では隣接制約・コスト・上限・海の開放可のみを実装し、立入禁止エリアの
/// 判定は別Issue（#153・`future`）に切り出す。**後続の実装者はこれを実装漏れと
/// 誤認しないこと。** 現状は立入禁止エリアも含め、パックに収録された全ヘクスが
/// 通常メッシュと同じ条件（隣接・残高）だけで開放可能になっている。
HexOpeningEvaluation evaluateHexOpening({
  required HexId hexId,
  required RegionPack regionPack,
  required DisclosedHexSet known,
  required int currentPoints,
  int cost = openingPointCostPerHex,
}) {
  final terrainType = regionPack.terrainOf(hexId);
  if (terrainType == null) {
    return HexOpeningEvaluation.denied(HexOpeningDenialReason.outsidePack);
  }

  if (known.contains(hexId)) {
    return HexOpeningEvaluation.denied(
      HexOpeningDenialReason.alreadyDisclosed,
      terrainType: terrainType,
    );
  }

  final isAdjacentToDisclosed = regionPack.neighborsOf(hexId).any(known.contains);
  if (!isAdjacentToDisclosed) {
    return HexOpeningEvaluation.denied(
      HexOpeningDenialReason.notAdjacentToDisclosed,
      terrainType: terrainType,
    );
  }

  if (currentPoints < cost) {
    return HexOpeningEvaluation.denied(
      HexOpeningDenialReason.insufficientPoints,
      terrainType: terrainType,
    );
  }

  return HexOpeningEvaluation.allowed(terrainType);
}
