import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;
import 'package:terra_town_location/terra_town_location.dart';

void main() {
  // 【範囲】T030 の受け入れ基準「地域パックDB への書き込みが構造的に防がれている」を
  // 検証する。地域パックDBの実スキーマ（cell_terrain/hex_terrain/poi 等）は
  // `tools/pack-builder/` 側の別 Issue（#85）のスコープのため、ここでは
  // ダミーのテーブル・データで「読み取りはできる」「書き込みは拒否される」ことのみ確認する。

  late Directory tempDir;
  late String packFilePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('region_pack_connection_test');
    packFilePath = p.join(tempDir.path, 'region_pack.sqlite');

    // 地域パックDB相当のファイルを、書き込み可能なモードで先に作っておく
    // （tools/pack-builder が事前生成する配布物を模している）。
    final seedDatabase = sqlite3.sqlite3.open(packFilePath);
    seedDatabase.execute('CREATE TABLE hex_terrain (hex_id INTEGER PRIMARY KEY, terrain_type TEXT)');
    seedDatabase.execute(
      "INSERT INTO hex_terrain (hex_id, terrain_type) VALUES (1, 'forest')",
    );
    seedDatabase.close();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('読み取り専用で開いたパックDBから既存データを読み取れる', () {
    final connection = RegionPackConnection.open(packFilePath);
    addTearDown(connection.close);

    final result = connection.rawSelect(
      'SELECT terrain_type FROM hex_terrain WHERE hex_id = ?',
      [1],
    );

    expect(result.single['terrain_type'], 'forest');
  });

  test('読み取り専用で開いたパックDBへの書き込みは SQLite 自身が拒否する', () {
    final connection = RegionPackConnection.open(packFilePath);
    addTearDown(connection.close);

    // アプリ側の規約ではなく SQLite の OpenMode.readOnly により
    // SQLITE_READONLY で拒否されることを確認する（構造的な書き込み防止）。
    expect(
      () => connection.rawExecuteForTesting(
        "INSERT INTO hex_terrain (hex_id, terrain_type) VALUES (2, 'mountain')",
      ),
      throwsA(isA<sqlite3.SqliteException>()),
    );
  });

  test('存在しないパックDBファイルを読み取り専用で開こうとすると例外になる', () {
    final missingPath = p.join(tempDir.path, 'does_not_exist.sqlite');

    // OpenMode.readOnly は既定の readWriteCreate と異なりファイルを新規作成しないため、
    // 誤ったパスを渡した場合に「空のDBが黙って作られる」事故を防げる。
    expect(
      () => RegionPackConnection.open(missingPath),
      throwsA(isA<sqlite3.SqliteException>()),
    );
  });
}
