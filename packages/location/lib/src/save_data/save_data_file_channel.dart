import 'save_data_api.g.dart';

/// セーブデータのファイル本体を SAF（Storage Access Framework）経由でやり取りする
/// platform channel を抽象化する（Issue #180 決定事項6）。
///
/// `native_position_provider.dart` の `LocationPointsApi` と同じ理由（Pigeon が
/// 生成する具象クラスをそのままテストで使うと差し替えづらいため）で薄い
/// インターフェースを用意する。**この抽象自体は `packages/location` に置くが、
/// 実際に「いつ・どの文言のダイアログとともに」呼び出すかは `app`
/// （`settings_screen.dart`）の責務**（Issue #180 決定事項7「UIとファイル受け渡しは
/// app」）。
abstract interface class SaveDataFileChannel {
  /// SAF のファイル保存ピッカーを開き、[contents] を書き込む。
  /// ユーザーがキャンセルした場合は `false` を返す。
  Future<bool> saveTextFile(String suggestedFileName, String contents);

  /// SAF のファイル選択ピッカーを開き、内容を読み込む。
  /// ユーザーがキャンセルした場合は `null` を返す。
  Future<String?> openTextFile();
}

/// [SaveDataFileChannel] の既定実装。Pigeon が生成した [SaveDataFileHostApi] へ
/// そのまま委譲するだけの薄いラッパー。
class PigeonSaveDataFileChannel implements SaveDataFileChannel {
  PigeonSaveDataFileChannel([SaveDataFileHostApi? api])
    : _api = api ?? SaveDataFileHostApi();

  final SaveDataFileHostApi _api;

  @override
  Future<bool> saveTextFile(String suggestedFileName, String contents) =>
      _api.saveTextFile(suggestedFileName, contents);

  @override
  Future<String?> openTextFile() => _api.openTextFile();
}
