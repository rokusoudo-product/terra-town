import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';

/// [OpeningPointLedger.readSnapshot] の戻り値（Issue #143）。
class OpeningPointLedgerSnapshot {
  const OpeningPointLedgerSnapshot({
    required this.watermarkRowId,
    required this.remainderMillimeters,
    required this.points,
  });

  /// 最後に開放ポイントを計上した `location_point.id`（行id）。未計上（アプリ初回
  /// 起動）の場合は0（`TerrainYieldLedgerSnapshot.watermarkRowId` と同じ番兵値の
  /// 考え方）。
  final int watermarkRowId;

  /// 持ち越されている端数〔ミリメートル〕。
  final int remainderMillimeters;

  /// 現在の開放ポイント所持数（ストック。0〜[openingPointStockCap]）。
  final int points;

  static const initial = OpeningPointLedgerSnapshot(
    watermarkRowId: 0,
    remainderMillimeters: 0,
    points: 0,
  );
}

/// 開放ポイント（歩行距離換算・Issue #143）の永続化を行うインターフェース。
///
/// `app` 側（`OpeningPointAccrualCoordinator`）はこの抽象だけに依存させ、
/// Drift・`GameDatabase` を直接知らないようにする（`TerrainYieldLedgerStore`と
/// 同じテスト容易性のための設計）。
abstract interface class OpeningPointLedgerStore {
  /// 直近の状態（ウォーターマーク・端数・所持ポイント数）を読み出す。行が無い場合は
  /// [OpeningPointLedgerSnapshot.initial] を返す。
  Future<OpeningPointLedgerSnapshot> readSnapshot();

  /// ポイントの加算・端数・ウォーターマークの更新を**1つのトランザクション**で行う
  /// （二重計上防止の核心。`TerrainYieldLedgerStore.applyAccrual` と同じ方針）。
  Future<void> applyAccrual({
    required int grantedPoints,
    required int remainderMillimeters,
    required int watermarkRowId,
  });
}

/// [OpeningPointLedgerStore] の本番実装（`settings` テーブルに保存する。
/// Issue #143・T063）。
///
/// ## `inventory` テーブルを使わない（`Resource` ではないため）
/// 開放ポイントは `packages/core` の `Resource` enum（木・石・鉄等）に属さない
/// 独立した通貨であり（`docs/opening_points.md`「開放ポイント」）、
/// `InventoryRepository`／`inventory` テーブルは経由しない。所持数
/// （[OpeningPointLedgerSnapshot.points]）自体も `settings` テーブルの
/// key-value として保存する。
///
/// ## スキーマ変更をしない
/// 既存の `settings` テーブル（T034。`RewardSettingsRepository`・
/// `TerrainYieldLedger` と同じ key-value 方式）をそのまま使う。ウォーターマークは
/// [watermarkRowIdKey]、端数は [remainderMillimetersKey]、所持ポイント数は
/// [pointsKey] にそれぞれ保存する。
///
/// ## ウォーターマークの方式（`TerrainYieldLedger` と同じ設計・Issue #143 が踏襲）
/// ウォーターマークは「最後に開放ポイントを計上した位置記録の行id」
/// （`location_point.id`）とする。**セッションIDと単調時刻の組をウォーターマークに
/// しない**（そのセッションの行が無いと永久に計上が止まる危険があるため）。
/// [NativePositionProvider] は起動のたびに記録の先頭（`sinceRowId = 0`）から
/// 全件を再生するため、`OpeningPointAccrualCoordinator`（`app/lib/map/economy/`）が
/// ウォーターマークの行を「直前の点」として復元する（`TerrainYieldAccrualCoordinator`
/// クラスdoc「ウォーターマークの方式」と同じ考え方。ただし開放ポイントは
/// `RewardPolicy.classify` の移動窓判定に必要な直近区間を保持する必要があるため、
/// 復元する文脈はウォーターマーク行1件だけでなく直近の窓幅ぶんになる。詳細は
/// `OpeningPointAccrualCoordinator` クラスdoc参照）。
///
/// ## 二重計上防止（重要）
/// [applyAccrual] は所持ポイントの加算・端数・ウォーターマークの更新を**1つの
/// `GameDatabase.transaction` で行う**。アプリがクラッシュする等でこの
/// トランザクションが完了しなかった場合、SQLite のトランザクションはロールバック
/// され、**所持ポイント・端数・ウォーターマークのいずれも進まない**
/// （`opening_point_ledger_test.dart` で検証）。次回起動時は同じ区間が改めて
/// 計上される（失われない）。
///
/// ## 上限（50P）はここでは適用しない
/// 上限のクランプ（`docs/opening_points.md` §4）は
/// `computeOpeningPointAccrual`（`packages/core`）が既に行っている
/// （呼び出し側が渡す `grantedAmounts` は既にクランプ済みの値）。本クラスは
/// 渡された値をそのまま加算するだけで、二重にクランプしない
/// （`InventoryRepository` が地形産出について「上限を一切適用しない」のと対照的に、
/// 本クラスは「呼び出し側が既にクランプ済みの値を渡す」という前提が異なる）。
class OpeningPointLedger implements OpeningPointLedgerStore {
  OpeningPointLedger(this._database, {OpeningPointBalanceStore? balanceStore})
      : _balanceStore = balanceStore ?? OpeningPointBalanceRepository(_database);

  final GameDatabase _database;

  /// 所持ポイント数の読み書き（[OpeningPointBalanceStore]）。既定は
  /// [OpeningPointBalanceRepository]（本番実装）だが、`TerrainYieldLedger` が
  /// `InventoryRepository` を差し替え可能にしているのと同じ理由（トランザクション
  /// のロールバックをテストで再現するため）で差し替え可能にしてある
  /// （`opening_point_ledger_test.dart`「トランザクションの原子性」参照）。
  final OpeningPointBalanceStore _balanceStore;

  /// `settings.key` に保存するウォーターマークのキー名。
  static const String watermarkRowIdKey = 'opening_point.watermark_row_id';

  /// `settings.key` に保存する端数〔ミリメートル〕のキー名。
  static const String remainderMillimetersKey = 'opening_point.remainder_millimeters';

  /// `settings.key` に保存する所持ポイント数のキー名。
  static const String pointsKey = 'opening_point.points';

  @override
  Future<OpeningPointLedgerSnapshot> readSnapshot() async {
    final watermarkValue = await _readSetting(watermarkRowIdKey);
    final watermarkRowId =
        watermarkValue == null ? 0 : (int.tryParse(watermarkValue) ?? 0);

    final remainderValue = await _readSetting(remainderMillimetersKey);
    final remainderMillimeters =
        remainderValue == null ? 0 : (int.tryParse(remainderValue) ?? 0);

    final points = await _balanceStore.read();

    return OpeningPointLedgerSnapshot(
      watermarkRowId: watermarkRowId,
      remainderMillimeters: remainderMillimeters,
      points: points,
    );
  }

  @override
  Future<void> applyAccrual({
    required int grantedPoints,
    required int remainderMillimeters,
    required int watermarkRowId,
  }) async {
    await _database.transaction(() async {
      if (grantedPoints > 0) {
        final currentPoints = await _balanceStore.read();
        await _balanceStore.write(currentPoints + grantedPoints);
      }
      await _writeSetting(watermarkRowIdKey, watermarkRowId.toString());
      await _writeSetting(remainderMillimetersKey, remainderMillimeters.toString());
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

/// [OpeningPointLedger] が所持ポイント数（`opening_point.points`）の読み書きに
/// 使う薄いリポジトリ。`InventoryRepository` を`TerrainYieldLedger`が差し替え
/// 可能にしているのと同じ「テスト時に書き込み失敗を注入できるようにする」ための
/// 抽象化（Issue #143）。
abstract interface class OpeningPointBalanceStore {
  /// 現在の所持ポイント数（未保存なら0）。
  Future<int> read();

  /// 所持ポイント数を [value] で置き換える。
  Future<void> write(int value);
}

/// [OpeningPointBalanceStore] の本番実装（`settings` テーブルの
/// [OpeningPointLedger.pointsKey] に保存する）。
class OpeningPointBalanceRepository implements OpeningPointBalanceStore {
  OpeningPointBalanceRepository(this._database);

  final GameDatabase _database;

  @override
  Future<int> read() async {
    final row = await (_database.select(_database.settings)
          ..where((t) => t.key.equals(OpeningPointLedger.pointsKey)))
        .getSingleOrNull();
    return row == null ? 0 : (int.tryParse(row.value) ?? 0);
  }

  @override
  Future<void> write(int value) async {
    await _database.into(_database.settings).insertOnConflictUpdate(
          SettingsCompanion(
            key: const Value(OpeningPointLedger.pointsKey),
            value: Value(value.toString()),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
