import '../geo/hex_id.dart';
import '../terrain/terrain_type.dart';
import 'pack_version.dart';

/// 開示ヘクス1件の獲得履歴（T036・Issue #84 → Issue #96 で改訂）。
///
/// 出典: `specs/001-mvp/plan.md` §3.3「一度開示したヘクスの資材分類は、パック更新後も
/// 過去分は不変とする（獲得履歴は当時の `pack_version` で確定）」。
///
/// `packages/location` の `disclosed_hex` テーブル（`DisclosedHexRow`・PR #90・
/// `packages/location/lib/src/db/game_database.dart`）の1行（`hexId` + `packVersion` +
/// `terrainType`）に対応する、core 側の読み取り専用の値表現。
///
/// ## 不変性の実現方法（2026-09-10・Issue #96・代表決定・案A）
/// 当初（Issue #84・PR #95）は「開示当時の [PackVersion] に対応する [RegionPack] を
/// 都度引いて分類を解決する」方式（`PackVersionResolver`）を採っていたが、MVP は
/// パックをアプリ同梱するため（plan.md §3.3）パック更新＝アプリ更新であり、
/// **旧バージョンのパックファイルは端末から消える**。当時のバージョンを引く方式は
/// 原理的に成立しないため、`PackVersionResolver` は Issue #96 で削除した。
///
/// 代わりに、**開示した時点の [TerrainType] を [terrainType] としてこの値オブジェクト
/// （＝ `disclosed_hex` テーブルの行）自体に保存する**。以後、このヘクスの地形分類を
/// 問い合わせる経路は常にこの [terrainType] であり、[RegionPack.terrainOf] を
/// 再度引くことはない（[RegionPack.terrainOf] は新規開示時にこのスナップショットを
/// 作るためだけに使う。`RegionPack` のドキュメント参照）。
///
/// **[terrainType] が non-null 必須のフィールドであること自体が、「獲得履歴は
/// 開示時点の分類で確定する」という不変性ルールをコード上に表現している**
/// （オプショナルにして「現行パックを都度参照」を許してしまうと、このルールが
/// 型で保証されなくなる）。「現在アクティブなパックへの黙示的フォールバックを
/// 禁止する」という当初の契約は、パックを引く経路そのものが無くなったことで
/// 構造的に（規約ではなく仕組みで）守られるようになった。
///
/// 区画（[DistrictId]）・名所POIの対応づけは**ここに含めない**。区画は行政区域の
/// 変更（市町村合併等）を反映するため常に現行パックから解決する必要があり、
/// 名所POIは「何を発見したか」を `collection` テーブルが別途担保するため、
/// ヘクスとの対応づけを凍結すると同じ情報の二重管理になる
/// （詳細な理由は Issue #96 の代表決定コメント、および `RegionPack.districtOf`・
/// `RegionPack.pointsOfInterest` のドキュメント参照）。
///
/// 本クラスは値オブジェクトであり、SQLite 等の永続化手段には一切依存しない
/// （GPS_ARCHITECTURE 準拠）。`disclosed_hex` テーブルの行からこの値を組み立てる処理
/// （読み出し）は `location/` 側の責務であり、本 Issue のスコープ外
/// （実際の開示判定ロジック・T054 も同様にスコープ外）。
class DisclosedHex {
  /// 開示されたヘクス。
  final HexId hexId;

  /// このヘクスが開示された時点の地形分類のスナップショット。
  ///
  /// 地形分類を問い合わせる際は**必ずこの値を使うこと**。パックが更新されても
  /// この値は変わらない（不変性ルール・plan.md §3.3・Issue #96）。
  final TerrainType terrainType;

  /// このヘクスが開示された**時点**の地域パックバージョン。
  ///
  /// 【用途が変わったことに注意】Issue #96 以前は地形分類を解決するために
  /// このバージョンで [RegionPack] を引き直す用途だったが、その経路は
  /// 廃止した（[terrainType] を直接参照する）。**現在は「いつのパックで
  /// 開示したか」という監査目的の記録、および将来パック形式やデータ移行が
  /// 必要になった際の判断材料としてのみ保持する。** 地形分類の解決には使わない。
  final PackVersion discoveredAtVersion;

  const DisclosedHex({
    required this.hexId,
    required this.terrainType,
    required this.discoveredAtVersion,
  });

  @override
  bool operator ==(Object other) =>
      other is DisclosedHex &&
      other.hexId == hexId &&
      other.terrainType == terrainType &&
      other.discoveredAtVersion == discoveredAtVersion;

  @override
  int get hashCode => Object.hash(hexId, terrainType, discoveredAtVersion);

  @override
  String toString() => 'DisclosedHex(hexId: $hexId, terrainType: $terrainType, '
      'discoveredAtVersion: $discoveredAtVersion)';
}
