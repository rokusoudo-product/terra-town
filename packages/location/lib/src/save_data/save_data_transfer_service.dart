import 'package:drift/drift.dart';

import '../db/game_database.dart';
import '../db/opening_point_ledger.dart';
import '../db/terrain_yield_ledger.dart';
import 'location_point_id_source.dart';
import 'save_data_backup.dart';
import 'save_data_codec.dart';
import 'save_data_exceptions.dart';
import 'save_data_summary.dart';

/// セーブデータのエクスポート/インポート本体（Issue #180・T105）。
///
/// `app`（設定画面）はこのクラスと [SaveDataFileChannel]（`save_data_file_channel.dart`。
/// SAF 経由のファイル本体の受け渡し）を組み合わせて使う。本クラス自身は
/// ファイル選択・保存ダイアログには一切触れない（Issue #180 決定事項7「UI と
/// ファイル受け渡しは app」）。
///
/// ## 書き出し（[exportToJsonString]）
/// `GameDatabase` の7テーブルすべて（`settings` を含む）を読み出し、
/// `save_data_codec.dart` の [encodeSaveDataDocument] で JSON 文字列にする
/// （Issue #180 決定事項2「ゲーム状態の7テーブルすべてを書き出す」・
/// 「位置記録（`location_track.sqlite`）は書き出さない」）。
///
/// ## 読み込み（[parseSummary] → 呼び出し側の確認 → [importFromJsonString]）
/// 呼び出し側の想定フロー（Issue #180 決定事項4）:
/// 1. `app` が SAF でファイルを選び、内容（文字列）を取得する。
/// 2. [parseSummary] を呼ぶ。構造検証に失敗した場合は
///    [SaveDataFormatException]／[SaveDataSchemaTooNewException]／
///    [SaveDataSchemaMigrationUnsupportedException] が投げられる
///    ——**この時点では DB に一切触れていない**。
/// 3. 検証に成功したら、返された [SaveDataSummary] を確認ダイアログに表示し、
///    ユーザーの同意を得る。
/// 4. 同意が得られたら [importFromJsonString] を呼ぶ。
///
/// [importFromJsonString] の内部手順（決定事項4「安全策」）:
/// 1. もう一度パース・検証する（[parseSummary] と別呼び出しのため、呼び出しの
///    間にファイルが変わる余地は無いが、DB操作の直前に再検証することで
///    「検証済みの内容だけがDBに書き込まれる」という不変条件をコード上でも
///    保つ）。
/// 2. 上書き前の自動バックアップを書き込む（[SaveDataBackupWriter]）。
///    **これが失敗した場合は [SaveDataBackupFailedException] を投げて中断する
///    （DB には一切触れない）**。
/// 3. `GameDatabase.transaction`（**1トランザクション**）で
///    「全削除→全挿入→ウォーターマーク補正」を行う。失敗した場合は
///    [SaveDataImportFailedException]（[SaveDataBackupFailedException.backupFilePath]
///    を含む）を投げる。トランザクションはロールバックされ、DB は読み込み前の
///    状態のまま。
///
/// ## ウォーターマークの補正（Issue #180 決定事項3・最重要）
/// `terrain_yield.watermark_row_id`・`opening_point.watermark_row_id` は、
/// ファイルに含まれていた値の**有無に関わらず**、常に読み込み先端末の現在の
/// `max(location_point.id)`（[LocationPointIdSource.getMaxLocationPointId]。
/// 記録が無ければ0）で**上書き**する。ファイルにこれらのキーが無い場合
/// （記録開始前にエクスポートされた等）に「補正しない」と、読み込み先端末に
/// 既存の記録があった場合、ウォーターマークが0のままそれら全件が新規計上されて
/// しまう（`pigeons/location_api.dart`・Issue #180 本文「ウォーターマークの罠」
/// 参照）。`*.remainder_*`（端数）はファイルの値をそのまま使う
/// （決定事項3「端数はファイルの値をそのまま使う」）。
///
/// ## `core`・`app` への依存
/// 本クラスは `GameDatabase`（Drift）にのみ依存し、Pigeon（[LocationPointIdSource]
/// の既定実装のみが依存）・SAF（[SaveDataFileChannel]）には触れない。
/// [LocationPointIdSource] を差し替えれば、単体テストは Pigeon/platform channel に
/// 一切触れずに済む。
class SaveDataTransferService {
  SaveDataTransferService(
    this._database, {
    LocationPointIdSource? locationPointIdSource,
    int? currentSchemaVersion,
  }) : _locationPointIdSource =
           locationPointIdSource ?? PigeonLocationPointIdSource(),
       currentSchemaVersion = currentSchemaVersion ?? _database.schemaVersion;

  final GameDatabase _database;
  final LocationPointIdSource _locationPointIdSource;

  /// このアプリが対応する `schema_version`（既定は [GameDatabase.schemaVersion]）。
  /// テストで「対応バージョンより新しいファイル」を作らずに拒否ケースを
  /// 再現できるよう差し替え可能にしてある。
  final int currentSchemaVersion;

  /// 現在の `GameDatabase` の内容を JSON 文字列にする（Issue #180 決定事項1・2）。
  ///
  /// [appVersion]・[packVersion] は呼び出し側（`app`）が用意する（`packages/location`
  /// は `app` のバージョン管理・地域パックの読み込みに関する知識を持たない）。
  /// 上書き前の自動バックアップ（[importFromJsonString] 内部）はこれらを渡さず
  /// 既定値（`'unknown'`）のまま呼ぶ——バックアップの主目的はデータの復元であり、
  /// メタデータの正確さは復旧に必須ではないため。
  Future<String> exportToJsonString({
    String appVersion = 'unknown',
    String packVersion = 'unknown',
    DateTime? exportedAt,
  }) async {
    final disclosedHexes = await _database.select(_database.disclosedHexes).get();
    final inventories = await _database.select(_database.inventories).get();
    final buildings = await _database.select(_database.buildings).get();
    final districtProgresses =
        await _database.select(_database.districtProgresses).get();
    final collections = await _database.select(_database.collections).get();
    final questDailies = await _database.select(_database.questDailies).get();
    final settings = await _database.select(_database.settings).get();

    return encodeSaveDataDocument(
      appVersion: appVersion,
      packVersion: packVersion,
      exportedAt: exportedAt ?? DateTime.now(),
      schemaVersion: currentSchemaVersion,
      disclosedHexes: disclosedHexes,
      inventories: inventories,
      buildings: buildings,
      districtProgresses: districtProgresses,
      collections: collections,
      questDailies: questDailies,
      settings: settings,
    );
  }

  /// [jsonString] を検証し、確認ダイアログ用の要約を返す（クラスdoc「読み込み」
  /// 手順1〜2参照）。DB には一切触れない。
  SaveDataSummary parseSummary(String jsonString) {
    final document = _parse(jsonString);
    return _summaryOf(document);
  }

  /// [jsonString] を実際に読み込む（クラスdoc「読み込み」手順4参照）。
  ///
  /// 戻り値は書き込まれた自動バックアップファイルのパス（成功時も、復旧目的で
  /// 呼び出し側がユーザーに提示してよい）。
  Future<String> importFromJsonString(
    String jsonString, {
    required SaveDataBackupWriter backupWriter,
  }) async {
    final document = _parse(jsonString);
    final maxLocationPointId = await _locationPointIdSource
        .getMaxLocationPointId();

    final backupJson = await exportToJsonString();
    final String backupFilePath;
    try {
      backupFilePath = await backupWriter.write(backupJson);
    } catch (error) {
      // クラスdoc「安全策」手順2: バックアップが失敗した場合は DB に一切触れず中断する。
      throw SaveDataBackupFailedException(error);
    }

    try {
      await _database.transaction(() async {
        await _database.delete(_database.disclosedHexes).go();
        await _database.delete(_database.inventories).go();
        await _database.delete(_database.buildings).go();
        await _database.delete(_database.districtProgresses).go();
        await _database.delete(_database.collections).go();
        await _database.delete(_database.questDailies).go();
        await _database.delete(_database.settings).go();

        for (final row in document.disclosedHexes) {
          await _database.into(_database.disclosedHexes).insert(row);
        }
        for (final row in document.inventories) {
          await _database.into(_database.inventories).insert(row);
        }
        for (final row in document.buildings) {
          await _database.into(_database.buildings).insert(row);
        }
        for (final row in document.districtProgresses) {
          await _database.into(_database.districtProgresses).insert(row);
        }
        for (final row in document.collections) {
          await _database.into(_database.collections).insert(row);
        }
        for (final row in document.questDailies) {
          await _database.into(_database.questDailies).insert(row);
        }
        for (final row in document.settings) {
          await _database.into(_database.settings).insert(row);
        }

        // クラスdoc「ウォーターマークの補正」: ファイルの値の有無に関わらず、
        // 常にこの端末の現在の最大 location_point.id で上書きする。
        await _upsertSetting(
          TerrainYieldLedger.watermarkRowIdKey,
          maxLocationPointId.toString(),
        );
        await _upsertSetting(
          OpeningPointLedger.watermarkRowIdKey,
          maxLocationPointId.toString(),
        );
      });
    } catch (error) {
      throw SaveDataImportFailedException(
        backupFilePath: backupFilePath,
        cause: error,
      );
    }

    return backupFilePath;
  }

  SaveDataDocument _parse(String jsonString) => parseSaveDataDocument(
    jsonString,
    currentSchemaVersion: currentSchemaVersion,
  );

  SaveDataSummary _summaryOf(SaveDataDocument document) {
    var openingPoints = 0;
    for (final setting in document.settings) {
      if (setting.key.value == OpeningPointLedger.pointsKey) {
        openingPoints = int.tryParse(setting.value.value) ?? 0;
        break;
      }
    }
    return SaveDataSummary(
      exportedAt: document.exportedAt,
      disclosedHexCount: document.disclosedHexes.length,
      openingPoints: openingPoints,
      collectionCount: document.collections.length,
    );
  }

  Future<void> _upsertSetting(String key, String value) async {
    await _database
        .into(_database.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: Value(DateTime.now()),
          ),
        );
  }
}
