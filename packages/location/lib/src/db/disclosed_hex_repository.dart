import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';

/// `core` の `Repository<DisclosedHex, HexId>`（T038）の Drift 実装
/// （tasks.md T060・Issue #96・Issue #137）。
///
/// `disclosed_hex` テーブル（[GameDatabase.disclosedHexes]・T031・T035〜T037）を
/// 読み書きする。実際の判定ロジック（`DisclosureService`）・composition root の配線
/// （アプリ起動時の復元・`NativePositionProvider` の購読）は本クラスのスコープ外
/// （`app` 側の責務）。
///
/// ## [save] が「更新」ではなく「新規追加のみ」である理由（重要・Issue #96）
/// `disclosed_hex.terrain_type`・`pack_version` は**開示した瞬間のスナップショット**
/// であり、一度確定したら変わらない不変性ルールを持つ（`DisclosedHex` のクラスdoc
/// 参照）。`Repository.save` の契約は「新規作成または更新」だが、本エンティティに
/// 限っては**同じ [HexId] に対する2回目以降の [save] は何もしない**
/// （`InsertMode.insertOrIgnore`）。`DisclosureService.recordPosition` は
/// 「[known]（[DisclosedHexSet]）に含まれないヘクスに対してのみ [save] を呼ぶ」
/// ため通常は重複呼び出しが起きないが、[known] の復元漏れ・タイミングのバグで
/// 万一同じヘクスに対して2回目の [save] が呼ばれても、`insertOnConflictUpdate`
/// のように既存行を上書きしてしまうと `discoveredAt`/`packVersion`（監査記録）が
/// 静かに書き換わり、「いつ開示したか」という履歴が壊れる。`insertOrIgnore` で
/// 既存行を保護することで、スナップショットの不変性をコード上でも守る。
class DisclosedHexRepository implements Repository<DisclosedHex, HexId> {
  DisclosedHexRepository(this._database);

  final GameDatabase _database;

  @override
  Future<DisclosedHex?> findById(HexId id) async {
    final row = await (_database.select(_database.disclosedHexes)
          ..where((t) => t.hexId.equals(id.value)))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  @override
  Future<List<DisclosedHex>> findAll() async {
    final rows = await _database.select(_database.disclosedHexes).get();
    return rows.map(_toDomain).toList(growable: false);
  }

  @override
  Future<void> save(DisclosedHex entity) async {
    await _database.into(_database.disclosedHexes).insert(
          DisclosedHexesCompanion.insert(
            hexId: Value(entity.hexId.value),
            terrainType: entity.terrainType,
            packVersion: entity.discoveredAtVersion.value,
          ),
          // クラスdoc参照: スナップショットの不変性を守るため、既存行があれば
          // 何もしない（上書きしない）。
          mode: InsertMode.insertOrIgnore,
        );
  }

  @override
  Future<void> delete(HexId id) async {
    await (_database.delete(
      _database.disclosedHexes,
    )..where((t) => t.hexId.equals(id.value))).go();
  }

  static DisclosedHex _toDomain(DisclosedHexRow row) => DisclosedHex(
        hexId: HexId(row.hexId),
        terrainType: row.terrainType,
        discoveredAtVersion: PackVersion(row.packVersion),
      );
}
