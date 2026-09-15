import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';
import 'inventory_repository.dart';

/// チュートリアル開始資材（木50・石10）の1回限りの付与（Issue #188・T116）。
///
/// 出典: `docs/tutorial.md` §3「付与のタイミングと1回だけ付与する仕組み」。
/// `settings` テーブルのキー [grantedSettingsKey]
/// （`tutorial.initial_resources_granted`）が**無ければ**、
/// [startingResources]（`packages/core`・`balance.yaml` が正本）を
/// `inventory` へ**加算**（既存の所持数に足す。上書きしない）し、
/// 続けて印を書き込む。**この2つの書き込みは [GameDatabase.transaction] の
/// 同じトランザクションで行う**（片方だけが保存された状態を防ぐ。
/// `TerrainYieldLedger.applyAccrual`・`LandmarkAwareDisclosedHexRepository.save`
/// と同じ「二重計上防止」の考え方）。
///
/// キーが既にある場合は何もしない（2回目以降の起動・セーブデータ読み込み後の
/// 再作成でも二重に付与しない。`docs/tutorial.md` §5）。
///
/// [grantIfNeeded] の戻り値は「今回実際に付与したか」。`app` 側
/// （`RootScaffold`）はこれを使って、通知（SnackBar）をトランザクションの
/// 確定後にだけ表示する（`docs/tutorial.md` §4）。
///
/// ## 既存端末との分岐をしない（`docs/tutorial.md` §3）
/// 新規インストールか、本機能より前のバージョンから使い続けている端末かは
/// 判定しない。印の有無だけを条件にすることで自然に両対応する。
class TutorialStartingResourcesGrant {
  TutorialStartingResourcesGrant(
    this._database, {
    InventoryRepository? inventoryRepository,
  }) : _inventoryRepository =
           inventoryRepository ?? InventoryRepository(_database);

  final GameDatabase _database;
  final InventoryRepository _inventoryRepository;

  /// `settings.key` に保存する印のキー名（`docs/tutorial.md` §3。テストからも
  /// 参照できるよう public にする。`TerrainYieldLedger.watermarkRowIdKey` と
  /// 同じ方針）。
  static const String grantedSettingsKey =
      'tutorial.initial_resources_granted';

  /// 印として書き込む固定値。判定は [grantedSettingsKey] の存在有無のみで行う
  /// ため値自体に意味は持たせない（壁時計由来の値を持たせない方針。
  /// `docs/tutorial.md` §3・`docs/opening_points.md` §2.1・plan.md §7）。
  static const String grantedSettingsValue = '1';

  /// まだ付与されていなければ [startingResources] を `inventory` に加算し、
  /// 印を書き込む。実際に今回付与した場合は true、既に付与済みで何もしなかった
  /// 場合は false を返す。
  Future<bool> grantIfNeeded() async {
    var granted = false;

    await _database.transaction(() async {
      final existing = await (_database.select(_database.settings)
            ..where((t) => t.key.equals(grantedSettingsKey)))
          .getSingleOrNull();
      if (existing != null) return;

      for (final entry in startingResources.entries) {
        await _inventoryRepository.add(entry.key, entry.value);
      }

      await _database.into(_database.settings).insertOnConflictUpdate(
            SettingsCompanion(
              key: const Value(grantedSettingsKey),
              value: const Value(grantedSettingsValue),
              updatedAt: Value(DateTime.now()),
            ),
          );

      granted = true;
    });

    return granted;
  }
}
