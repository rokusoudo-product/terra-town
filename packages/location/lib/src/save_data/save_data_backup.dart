import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 上書き前の自動バックアップ（Issue #180 決定事項4）の書き込み先を抽象化する。
///
/// `app` 側（設定画面）のテストが実際のファイルI/Oに触れずにバックアップ失敗を
/// 再現できるよう、`RewardSettingsStore` 等と同じ「テスト容易性のための抽象化」
/// 方針を踏襲する。
abstract interface class SaveDataBackupWriter {
  /// [jsonContents] をバックアップ先へ書き込み、書き込んだファイルのパスを返す。
  /// 失敗した場合は例外を投げる（呼び出し側 `SaveDataTransferService` はこれを
  /// [SaveDataBackupFailedException] として扱う）。
  Future<String> write(String jsonContents);
}

/// [SaveDataBackupWriter] の本番実装。
///
/// Issue #180 決定事項4「アプリ内ストレージ」に保存する。ユーザーが選ぶ SAF の
/// 保存先とは異なり、権限確認なしにいつでも書き込める `getApplicationDocumentsDirectory()`
/// 配下（`GameDatabase.defaultConnection` が `game_state.sqlite` を置くのと同じ
/// ディレクトリ）の `save_data_backups/` サブディレクトリを使う。
///
/// ファイル名には UTC のタイムスタンプを含める（複数回インポートしても
/// 上書きされず、復旧案内で「いつのバックアップか」が分かるようにするため）。
class FileSaveDataBackupWriter implements SaveDataBackupWriter {
  const FileSaveDataBackupWriter();

  /// バックアップを置くサブディレクトリ名。
  static const String backupDirectoryName = 'save_data_backups';

  @override
  Future<String> write(String jsonContents) async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final backupDirectory = Directory(
      p.join(documentsDirectory.path, backupDirectoryName),
    );
    await backupDirectory.create(recursive: true);

    final timestamp = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp('[:.]'),
      '-',
    );
    final file = File(
      p.join(backupDirectory.path, 'pre-import-$timestamp.json'),
    );
    await file.writeAsString(jsonContents, flush: true);
    return file.path;
  }
}
