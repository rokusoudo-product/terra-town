import '../economy/resource.dart';
import 'terrain_type.dart';

/// 地形→資材の一次産出マッピング（T028）。
///
/// 出典: `docs/terrain.md` §2「地形タイプ一覧」の産出資材列と過不足なく一致
/// させること（Issue #82 受け入れ基準）。
///
/// | 地形タイプ | 産出資材 |
/// |-----------|---------|
/// | 空き地     | なし     |
/// | 森         | 木       |
/// | 山         | 石・鉄   |
/// | 水辺       | 水       |
/// | 海         | 塩       |
///
/// 本関数が表すのは **地形産出（受動・薄く常時。`docs/buildings.md` §6.2）のみ**
/// である。建物産出（畑→野菜/フルーツ、農場→肉、採石場→石・鉄。同 §6.2・§6.3・
/// US3 建物実装 T082〜T086）はスコープ外であり、本ファイルには一切現れない。
///
/// ⚠️ **採石場（石・鉄を産出する建物。Issue #72・2026-09-09 代表決定）を
/// ここに含めてはならない。** 山（地形）と採石場（建物）はどちらも石・鉄を
/// 産出しうるが、これは「地形産出と建物産出は対象資材が重複しない」という
/// 旧ルール（Issue #70 時点。`docs/buildings.md` §6.2 の書き直し前の記述）が
/// Issue #72 で「受動（地形）／能動（建物）」という役割分担へ書き直されたことに
/// よる**意図的な重複**である（同 §6.2）。本関数は受動側（地形産出）のみを
/// 担当し、能動側（採石場を含む建物産出）はここでは実装しない。
///
/// 野菜・フルーツ・肉は建物産出専用であり、対応する地形産出を持たないため
/// 本関数の戻り値には現れない（`docs/buildings.md` §6.1）。
Set<Resource> terrainYieldOf(TerrainType terrainType) {
  switch (terrainType) {
    case TerrainType.vacantLot:
      // 空き地は産出資材を持たない（産出0。terrain.md §2）。
      return const {};
    case TerrainType.forest:
      return const {Resource.wood};
    case TerrainType.mountain:
      return const {Resource.stone, Resource.iron};
    case TerrainType.waterside:
      return const {Resource.water};
    case TerrainType.sea:
      return const {Resource.salt};
  }
}
