/// 資材の大分類。
///
/// 出典: `specs/001-mvp/spec.md` §6「ゲーム内経済」。
enum ResourceCategory {
  /// 建設系（木・石・鉄）。建物の建設・強化に使用する。
  construction,

  /// 生活系（塩・水・野菜・フルーツ・肉）。住民/街の効率UP・人口成長に使用する。
  living,
}

/// 資材の種別（T026）。
///
/// 出典: `specs/001-mvp/spec.md` §6・`docs/buildings.md` §6.1。
/// - 建設系（木・石・鉄）: 建物の建設・強化に使用する。
/// - 生活系（塩・水・野菜・フルーツ・肉）: 住民/街の効率UPや人口成長に使う加算的
///   ボーナスとして扱う（`docs/buildings.md` §5.2）。肉は 2026-07-23 代表回答
///   （Issue #5）により生活系に追加された。
///
/// 本 enum は資材の**種別**のみを定義する。個々の資材がどの地形・建物から
/// 産出されるかは別ファイルが担当する（地形産出は `terrain_yield.dart`・T028、
/// 建物産出は US3 の建物実装・T082〜T086）。本ファイルはどちらにも依存しない。
enum Resource {
  /// 木。森（地形・受動）から産出する（`docs/terrain.md` §2）。
  wood(category: ResourceCategory.construction),

  /// 石。山（地形・受動・薄い）と採石場（建物・能動。Issue #72）の両方から
  /// 産出されうる（`docs/buildings.md` §6.2・§6.3）。地形産出のみを本 Issue
  /// （#82）で扱い、採石場（建物産出）は T082〜T086 のスコープ。
  stone(category: ResourceCategory.construction),

  /// 鉄。石と同じく、山（地形・受動）と採石場（建物・能動）の両方から
  /// 産出されうる（`docs/buildings.md` §6.2・§6.3）。
  iron(category: ResourceCategory.construction),

  /// 塩。海（地形・受動）からのみ産出する。地形以外の供給源は新設しない方針
  /// （`docs/buildings.md` §6.3「塩の扱い: 供給源を新設しない」）。
  salt(category: ResourceCategory.living),

  /// 水。水辺（地形・受動）からのみ産出する。
  water(category: ResourceCategory.living),

  /// 野菜。畑（建物）でのみ産出する。対応する地形産出は持たない
  /// （`docs/buildings.md` §6.1・§6.2）。
  vegetable(category: ResourceCategory.living),

  /// フルーツ。畑（建物）でのみ産出する。対応する地形産出は持たない。
  fruit(category: ResourceCategory.living),

  /// 肉。農場（建物）でのみ産出する新資材（Issue #5・2026-07-23 代表回答）。
  /// 対応する地形産出は持たない（`docs/buildings.md` §6.1）。
  meat(category: ResourceCategory.living);

  const Resource({required this.category});

  /// この資材が属するカテゴリ（建設系／生活系）。
  final ResourceCategory category;
}
