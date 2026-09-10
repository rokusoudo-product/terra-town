import '../geo/hex_id.dart';
import 'pack_version.dart';

/// 開示ヘクス1件の獲得履歴（T036・Issue #84）。
///
/// 出典: `specs/001-mvp/plan.md` §3.3「一度開示したヘクスの資材分類は、パック更新後も
/// 過去分は不変とする（獲得履歴は当時の `pack_version` で確定）」。
///
/// `packages/location` の `disclosed_hex` テーブル（`DisclosedHexRow`・PR #90・
/// `packages/location/lib/src/db/game_database.dart`）の1行（`hexId` + `packVersion`）に
/// 対応する、core 側の読み取り専用の値表現。**[discoveredAtVersion] が non-null 必須の
/// フィールドであること自体が、「獲得履歴は当時の pack_version で確定する」という
/// 不変性ルールをコード上に表現している**（オプショナルにして「現行パックを都度参照」を
/// 許してしまうと、このルールが型で保証されなくなる）。
///
/// 本クラスは値オブジェクトであり、SQLite 等の永続化手段には一切依存しない
/// （GPS_ARCHITECTURE 準拠）。`disclosed_hex` テーブルの行からこの値を組み立てる処理
/// （読み出し）は `location/` 側の責務であり、本 Issue のスコープ外
/// （実際の開示判定ロジック・T054 も同様にスコープ外）。
class DisclosedHex {
  /// 開示されたヘクス。
  final HexId hexId;

  /// このヘクスが開示された**時点**の地域パックバージョン。
  ///
  /// 現在アクティブなパックのバージョンとは異なりうる（OSM 更新でパックが
  /// 更新された後も、この値は開示当時のまま変わらない）。資材分類を問い合わせる際は
  /// 必ずこの値を使うこと（[PackVersionResolver] 参照）。
  final PackVersion discoveredAtVersion;

  const DisclosedHex({required this.hexId, required this.discoveredAtVersion});

  @override
  bool operator ==(Object other) =>
      other is DisclosedHex &&
      other.hexId == hexId &&
      other.discoveredAtVersion == discoveredAtVersion;

  @override
  int get hashCode => Object.hash(hexId, discoveredAtVersion);

  @override
  String toString() =>
      'DisclosedHex(hexId: $hexId, discoveredAtVersion: $discoveredAtVersion)';
}
