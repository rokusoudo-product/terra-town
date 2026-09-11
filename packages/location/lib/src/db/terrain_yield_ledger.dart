import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';
import 'inventory_repository.dart';
import 'resource_key_codec.dart';

/// [TerrainYieldLedger.readSnapshot] の戻り値（Issue #138）。
class TerrainYieldLedgerSnapshot {
  const TerrainYieldLedgerSnapshot({
    required this.watermarkRowId,
    required this.remainderMicros,
  });

  /// 最後に地形産出を計上した `location_point.id`（行id）。未計上（アプリ初回起動）
  /// の場合は0（`location_point.id` は1始まりのautoincrementのため、0はどの行にも
  /// 一致しない番兵値として使える）。
  final int watermarkRowId;

  /// 資材ごとに持ち越されている端数〔マイクロ秒〕（0の資材はキーを持たない）。
  final Map<Resource, int> remainderMicros;

  static const initial = TerrainYieldLedgerSnapshot(
    watermarkRowId: 0,
    remainderMicros: {},
  );
}

/// 地形産出（受動・時間ベース）の永続化を行うインターフェース（Issue #138）。
///
/// `app` 側（`TerrainYieldAccrualCoordinator`）はこの抽象だけに依存させ、
/// Drift・`GameDatabase` を直接知らないようにする（`RewardSettingsStore` と同じ
/// テスト容易性のための設計）。
abstract interface class TerrainYieldLedgerStore {
  /// 直近の状態（ウォーターマーク・端数）を読み出す。行が無い場合は
  /// [TerrainYieldLedgerSnapshot.initial] を返す。
  Future<TerrainYieldLedgerSnapshot> readSnapshot();

  /// 資材の加算・端数・ウォーターマークの更新を**1つのトランザクション**で行う
  /// （二重計上防止の核心。クラスdoc「二重計上防止」参照）。
  Future<void> applyAccrual({
    required Map<Resource, int> grantedAmounts,
    required Map<Resource, int> remainderMicros,
    required int watermarkRowId,
  });
}

/// [TerrainYieldLedgerStore] の本番実装（`inventory`・`settings` テーブルに保存する。
/// Issue #138・T068）。
///
/// ## スキーマ変更をしない
/// 既存の `inventory` テーブル（T032）・`settings` テーブル（T034。
/// `RewardSettingsRepository` と同じ key-value 方式）をそのまま使う。
/// ウォーターマークは [watermarkRowIdKey]、端数は [remainderMicrosKey] に
/// それぞれ保存する。
///
/// ## ウォーターマークの方式（重要・Issue #138 本文の設計要件）
/// ウォーターマークは「最後に計上した位置記録の行id」（`location_point.id`）とする。
/// **セッションIDと単調時刻の組をウォーターマークにしない**（そのセッションの行が
/// 無いと永久に計上が止まる危険があるため）。
///
/// [NativePositionProvider] は起動のたびに記録の先頭（`sinceRowId = 0`）から
/// 全件を再生する。`TerrainYieldAccrualCoordinator`（`app/lib/map/economy/`）は
/// この全件再生を利用して、**ウォーターマークの行そのものが再生されてきた時点で
/// その行を「直前の点（prev）」として復元する**（新たに settings へ
/// セッションID・単調時刻を別途保存する必要が無い）。詳細は
/// `TerrainYieldAccrualCoordinator` のクラスdoc参照。
///
/// ## 二重計上防止（重要）
/// [applyAccrual] は資材の加算（`inventory` テーブル）と、端数・ウォーターマークの
/// 更新（`settings` テーブル）を**1つの `GameDatabase.transaction` で行う**。
/// アプリがクラッシュする等でこのトランザクションが完了しなかった場合、
/// SQLite のトランザクションはロールバックされ、資材もウォーターマークも
/// **どちらも進まない**（`terrain_yield_ledger_test.dart` で検証）。次回起動時は
/// 同じ区間が改めて計上される（失われない）。
///
/// ## 上限（cap）を適用しない
/// [InventoryRepository.add] を経由するため、`core` の `Inventory.defaultCap` の
/// ようなクランプは一切適用されない（2026-09-11 代表決定「貯められる上限は
/// 設けない」・[InventoryRepository] クラスdoc参照）。
class TerrainYieldLedger implements TerrainYieldLedgerStore {
  TerrainYieldLedger(this._database, {InventoryRepository? inventoryRepository})
      : _inventoryRepository = inventoryRepository ?? InventoryRepository(_database);

  final GameDatabase _database;
  final InventoryRepository _inventoryRepository;

  /// `settings.key` に保存するウォーターマークのキー名（テストからも参照できるよう
  /// public にする。`RewardSettingsRepository.stepCheckDisabledKey` と同じ方針）。
  static const String watermarkRowIdKey = 'terrain_yield.watermark_row_id';

  /// `settings.key` に保存する端数のキー名。
  static const String remainderMicrosKey = 'terrain_yield.remainder_micros';

  @override
  Future<TerrainYieldLedgerSnapshot> readSnapshot() async {
    final watermarkValue = await _readSetting(watermarkRowIdKey);
    final watermarkRowId =
        watermarkValue == null ? 0 : (int.tryParse(watermarkValue) ?? 0);

    final remainderValue = await _readSetting(remainderMicrosKey);
    final remainder = <Resource, int>{};
    if (remainderValue != null) {
      try {
        final decoded = jsonDecode(remainderValue);
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is! String || value is! int) return;
            final resource = resourceFromKey(key);
            if (resource != null && value > 0) {
              remainder[resource] = value;
            }
          });
        }
      } on FormatException {
        // 解釈不能な値（データ破損等）は「端数なし」として扱う（罰しない側に倒す。
        // RewardSettingsRepository と同じ方針）。
      }
    }

    return TerrainYieldLedgerSnapshot(
      watermarkRowId: watermarkRowId,
      remainderMicros: remainder,
    );
  }

  @override
  Future<void> applyAccrual({
    required Map<Resource, int> grantedAmounts,
    required Map<Resource, int> remainderMicros,
    required int watermarkRowId,
  }) async {
    await _database.transaction(() async {
      for (final entry in grantedAmounts.entries) {
        await _inventoryRepository.add(entry.key, entry.value);
      }
      await _writeSetting(watermarkRowIdKey, watermarkRowId.toString());
      await _writeSetting(
        remainderMicrosKey,
        jsonEncode({
          for (final entry in remainderMicros.entries)
            if (entry.value > 0) resourceKeyOf(entry.key): entry.value,
        }),
      );
    });
  }

  Future<String?> _readSetting(String key) async {
    final row = await (_database.select(_database.settings)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  Future<void> _writeSetting(String key, String value) async {
    await _database.into(_database.settings).insertOnConflictUpdate(
          SettingsCompanion(
            key: Value(key),
            value: Value(value),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
