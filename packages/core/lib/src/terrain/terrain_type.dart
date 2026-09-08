/// マスの地形タイプ（地形タイプ軸）。
///
/// 出典: `docs/terrain.md` §2「地形タイプ一覧（7種）」。
/// この7種と過不足なく一致させること（Issue #33 受け入れ基準）。
/// 建築状態軸（未建築/建築後）とは独立した軸であり、本 enum は建築状態を表さない
/// （terrain.md §1）。
enum TerrainType {
  /// 空き地。産出資材なし（産出0）。唯一、建物を建てられる地形（terrain.md §2）。
  vacantLot,

  /// 森。産出資材: 木（terrain.md §2）。
  forest,

  /// 山。産出資材: 石・鉄（terrain.md §2）。
  mountain,

  /// 水辺（川・湖）。産出資材: 水（terrain.md §2）。
  waterside,

  /// 海。産出資材: 塩。建築不可だが開放対象（terrain.md §2・§7）。
  sea,

  /// 農地。産出資材: 野菜・フルーツ（terrain.md §2）。
  farmland,

  /// 市街。直接の産出はなく、人口ボーナスに寄与する（terrain.md §2・§8）。
  urban,
}
