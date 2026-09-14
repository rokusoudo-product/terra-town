import 'package:terra_town_location/terra_town_location.dart';

/// セーブデータの Drift⇔JSON 処理（`packages/location` の
/// [SaveDataTransferService]）を抽象化する（Issue #180・T105）。
///
/// `SettingsScreen` の単体テストが Drift の実DB・自動バックアップの実ファイル
/// I/O に一切触れずに済むようにするための抽象化（`RewardSettingsStore` と
/// 同じテスト容易性の方針）。
abstract interface class SaveDataTransfer {
  /// 現在の `GameDatabase` の内容を JSON 文字列にする。
  Future<String> exportToJsonString({
    required String appVersion,
    required String packVersion,
  });

  /// [jsonString] を検証し、確認ダイアログ用の要約を返す。DB には触れない。
  /// 例外は [SaveDataTransferService.parseSummary] と同じもの
  /// （`save_data_exceptions.dart` 参照）。
  SaveDataSummary parseSummary(String jsonString);

  /// [jsonString] を実際に読み込む。戻り値は上書き前に書き込まれた自動
  /// バックアップファイルのパス。
  Future<String> importFromJsonString(String jsonString);
}

/// [SaveDataTransfer] の本番実装。[SaveDataTransferService] へ委譲し、
/// 自動バックアップの書き込み先（Issue #180 決定事項4）はアプリ内ストレージ
/// （[FileSaveDataBackupWriter]）に固定する。
class LocationSaveDataTransfer implements SaveDataTransfer {
  LocationSaveDataTransfer(
    this._service, {
    SaveDataBackupWriter? backupWriter,
  }) : _backupWriter = backupWriter ?? const FileSaveDataBackupWriter();

  final SaveDataTransferService _service;
  final SaveDataBackupWriter _backupWriter;

  @override
  Future<String> exportToJsonString({
    required String appVersion,
    required String packVersion,
  }) => _service.exportToJsonString(
    appVersion: appVersion,
    packVersion: packVersion,
  );

  @override
  SaveDataSummary parseSummary(String jsonString) =>
      _service.parseSummary(jsonString);

  @override
  Future<String> importFromJsonString(String jsonString) =>
      _service.importFromJsonString(jsonString, backupWriter: _backupWriter);
}

/// SAF 経由のファイル受け渡し（`packages/location` の [SaveDataFileChannel]）を
/// 抽象化する（Issue #180 決定事項6・7「ファイル受け渡しは app」）。
abstract interface class SaveDataFileAccess {
  /// SAF の保存ピッカーを開き、[contents] を書き込む。ユーザーがキャンセルした
  /// 場合は `false` を返す。
  Future<bool> saveTextFile(String suggestedFileName, String contents);

  /// SAF の選択ピッカーを開き、内容を読み込む。ユーザーがキャンセルした場合は
  /// `null` を返す。
  Future<String?> openTextFile();
}

/// [SaveDataFileAccess] の本番実装。
class PigeonSaveDataFileAccess implements SaveDataFileAccess {
  PigeonSaveDataFileAccess([SaveDataFileChannel? channel])
    : _channel = channel ?? PigeonSaveDataFileChannel();

  final SaveDataFileChannel _channel;

  @override
  Future<bool> saveTextFile(String suggestedFileName, String contents) =>
      _channel.saveTextFile(suggestedFileName, contents);

  @override
  Future<String?> openTextFile() => _channel.openTextFile();
}

/// 記録中（foreground service 稼働中）かどうかの確認を抽象化する（Issue #180
/// 決定事項4「記録中は読み込みを拒否する」）。
abstract interface class RecordingStatusCheck {
  Future<bool> isRecording();
}

/// [RecordingStatusCheck] の本番実装。[NativeLocationTrackingControl] へ委譲する。
class NativeRecordingStatusCheck implements RecordingStatusCheck {
  NativeRecordingStatusCheck([NativeLocationTrackingControl? control])
    : _control = control ?? NativeLocationTrackingControl();

  final NativeLocationTrackingControl _control;

  @override
  Future<bool> isRecording() async => (await _control.status()).isRunning;
}
