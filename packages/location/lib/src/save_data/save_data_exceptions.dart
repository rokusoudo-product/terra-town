/// セーブデータのエクスポート/インポート（Issue #180・T105）で使う例外群。
library;

/// 読み込んだファイルが JSON として正しくない・必須キーが欠けている・
/// `format_version` が未知の場合に投げる（Issue #180 決定事項4「検証内容」）。
///
/// この例外が投げられた時点では **DB には一切触れていない**（`SaveDataTransferService`
/// のドキュメント参照）。呼び出し側（`app`）はこれを捕まえてエラー状態・復旧案内を
/// 表示すること。
class SaveDataFormatException implements Exception {
  const SaveDataFormatException(this.message);

  final String message;

  @override
  String toString() => 'SaveDataFormatException: $message';
}

/// 読み込んだファイルの `schema_version` が、このアプリが対応する現行バージョンより
/// **新しい**場合に投げる（Issue #180 決定事項4「`schema_version` が現在より新しい
/// ファイルは拒否する（『アプリを更新してください』）」）。
///
/// [SaveDataFormatException] と同じく、この例外が投げられた時点では DB には
/// 一切触れていない。
class SaveDataSchemaTooNewException implements Exception {
  const SaveDataSchemaTooNewException({
    required this.foundVersion,
    required this.supportedVersion,
  });

  /// ファイルに書かれていた `schema_version`。
  final int foundVersion;

  /// このアプリ（`GameDatabase.schemaVersion`）が対応する現行バージョン。
  final int supportedVersion;

  @override
  String toString() =>
      'SaveDataSchemaTooNewException: foundVersion=$foundVersion > '
      'supportedVersion=$supportedVersion';
}

/// 上書き前の自動バックアップ（Issue #180 決定事項4「上書きの直前に、現在の
/// データを自動でバックアップファイルに書き出す」）の書き込み自体が失敗した場合に
/// 投げる。
///
/// **この例外が投げられた場合、DB には一切触れていない**
/// （`SaveDataTransferService.importFromJsonString` は、バックアップの書き込みに
/// 失敗した場合は削除・上書きのトランザクションに進まず、ここで中断する。
/// 「上書きの直前にバックアップが確定していること」を保証するため）。
class SaveDataBackupFailedException implements Exception {
  const SaveDataBackupFailedException(this.cause);

  final Object cause;

  @override
  String toString() => 'SaveDataBackupFailedException: $cause';
}

/// 検証済み（[SaveDataFormatException]／[SaveDataSchemaTooNewException] は
/// 発生しない）のデータを実際に読み込む段階（DB のトランザクション）で失敗した
/// 場合に投げる。
///
/// この時点では既に自動バックアップ（[SaveDataBackupFailedException] が
/// 発生していない＝バックアップ自体は成功済み）が書き込まれているため、
/// [backupFilePath] を復旧案内に表示できる。DB 自体はトランザクションの
/// ロールバックにより読み込み前の状態のまま（Issue #180 決定事項4）。
class SaveDataImportFailedException implements Exception {
  const SaveDataImportFailedException({
    required this.backupFilePath,
    required this.cause,
  });

  /// 上書き前に書き出された自動バックアップファイルのパス（復旧案内用）。
  final String backupFilePath;

  final Object cause;

  @override
  String toString() =>
      'SaveDataImportFailedException: backupFilePath=$backupFilePath cause=$cause';
}

/// 読み込んだファイルの `schema_version` が、現行バージョンより**古い**場合に投げる
/// （Issue #180 決定事項4「古いものは読み替える（現時点で v3 未満の書き出しは
/// 存在しないが、読み替えの入口を用意する）」）。
///
/// 本 Issue の時点では実在する v3 未満のエクスポートが無いため、実際の読み替え
/// ロジックはまだ実装しない（`SaveDataTransferService` のドキュメント参照）。
/// この例外は「読み替えの入口」がまだ埋まっていないことを表す、意図的な
/// fail-loud な未実装表明であり、[SaveDataFormatException] とは区別する
/// （ファイルが壊れているのではなく、対応方法が未実装であるため）。
class SaveDataSchemaMigrationUnsupportedException implements Exception {
  const SaveDataSchemaMigrationUnsupportedException({
    required this.foundVersion,
    required this.supportedVersion,
  });

  /// ファイルに書かれていた `schema_version`。
  final int foundVersion;

  /// このアプリ（`GameDatabase.schemaVersion`）が対応する現行バージョン。
  final int supportedVersion;

  @override
  String toString() =>
      'SaveDataSchemaMigrationUnsupportedException: foundVersion=$foundVersion < '
      'supportedVersion=$supportedVersion（読み替え未実装）';
}

/// 記録中（foreground service 稼働中）にインポートを試みた場合に投げる
/// （Issue #180 決定事項4「記録中は読み込みを拒否する」）。
class SaveDataRecordingInProgressException implements Exception {
  const SaveDataRecordingInProgressException();

  @override
  String toString() =>
      'SaveDataRecordingInProgressException: 記録を停止してから読み込んでください';
}
