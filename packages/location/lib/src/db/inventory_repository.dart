import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';
import 'resource_key_codec.dart';

/// `inventory` テーブル（T032・`GameDatabase.inventories`）の読み書き（Issue #138）。
///
/// 資材インベントリ画面（T076・未実装）や、地形産出（T068）以外の将来の資材消費
/// （建築コスト・T084等）からも共通して使うことを想定した薄いリポジトリ。
///
/// ## 上限（cap）を一切適用しない
/// `core` の `Inventory` クラスは `defaultCap`（仮値999）による上限クランプを持つが、
/// 本クラスは `inventory` テーブルへ直接加算するだけで、そのクランプを経由しない。
/// 地形産出（Issue #138・2026-09-11 代表決定「貯められる上限は設けない」）を
/// 実現するための意図的な選択であり、`TerrainYieldLedger` が本クラスの [add] を
/// 呼ぶ際もこの挙動をそのまま利用する。将来、建築コスト消費など「上限が必要な
/// 文脈」が出てきた場合は、その呼び出し側が `core` の `Inventory` を使うか、
/// 本クラスに別途 cap 付きのメソッドを追加すること（本クラス自体を cap 付きに
/// 変更すると地形産出の「上限なし」要件を壊すため、安易に変更しないこと）。
class InventoryRepository {
  InventoryRepository(this._database);

  final GameDatabase _database;

  /// 資材ごとの所持数を全件読み出す（0件の資材はキーを持たない＝所持数0として
  /// 扱われる）。
  Future<Map<Resource, int>> readAll() async {
    final rows = await _database.select(_database.inventories).get();
    final result = <Resource, int>{};
    for (final row in rows) {
      final resource = resourceFromKey(row.resourceKey);
      if (resource == null) continue; // 未知のキーは無視する（罰しない側）。
      result[resource] = row.amount;
    }
    return result;
  }

  /// [resource] の現在の所持数（行が無ければ0）。
  Future<int> amountOf(Resource resource) async {
    final row = await (_database.select(_database.inventories)
          ..where((t) => t.resourceKey.equals(resourceKeyOf(resource))))
        .getSingleOrNull();
    return row?.amount ?? 0;
  }

  /// [resource] の所持数を [delta] だけ加算する（上限なし。クラスdoc参照）。
  ///
  /// [delta] が0以下の場合は何もしない。呼び出し側（[TerrainYieldLedger]）が
  /// `_database.transaction` の中でこのメソッドを呼ぶと、Drift の
  /// Zone スコープにより自動的に同じトランザクションに含まれる
  /// （別々の接続を開くわけではないため）。
  Future<void> add(Resource resource, int delta) async {
    if (delta <= 0) return;
    final key = resourceKeyOf(resource);
    final current = await (_database.select(_database.inventories)
          ..where((t) => t.resourceKey.equals(key)))
        .getSingleOrNull();
    final newAmount = (current?.amount ?? 0) + delta;
    await _database.into(_database.inventories).insertOnConflictUpdate(
          InventoriesCompanion(
            resourceKey: Value(key),
            amount: Value(newAmount),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
