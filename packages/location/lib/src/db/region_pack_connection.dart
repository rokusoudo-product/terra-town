import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// 地域パックDB（配布物・読み取り専用）への**別接続**（T030）。
///
/// 出典: plan.md §3・§6「地域パックは配布物であり書き換えない」「ゲーム状態・地域パック
/// （読み取り専用）を分離」。[GameDatabase]（`game_database.dart`）とは接続を共有しない。
///
/// 【書き込みを構造的に防ぐ方法】
/// 対象ファイルを SQLite の **`OpenMode.readOnly`** で開く。これはアプリ側の
/// コーディング規約（「書き込みメソッドを呼ばない」という自己規律）ではなく、
/// **SQLite 自身が** `INSERT`/`UPDATE`/`DELETE` 等の書き込み系SQL文をエラーにする
/// （`SQLITE_READONLY`）。読み取り専用モードで開いたファイルが存在しない場合も、
/// 新規作成は行われず [sqlite3.SqliteException] を送出する（`OpenMode.readWriteCreate`
/// 〔既定〕と異なり、読み取り専用モードはファイル作成を伴わないため）。
///
/// 【地域パックDBの実スキーマを本 Issue で定義しない理由】
/// 地域パックDBの実テーブル（`cell_terrain`/`hex_terrain`/`poi`/行政区画ポリゴン等。
/// plan.md §3.2）は `tools/pack-builder/`（Issue #38・#85・tasks.md T039〜T043。
/// 本 Issue 時点で未マージ）が生成するデータの構造に従う。本 Issue（#83・T030）の
/// スコープは「ゲーム状態DBと地域パックDBを別接続として分離する構成を作る」ことまでで
/// あり、地域パックDB側の Drift `Table` 定義（型安全なスキーマ）は持たせない。
/// 実際の読み取りロジック（`core` の `RegionPack` 抽象の実装）は `location/` 側の
/// 別タスク（tasks.md T069）が担当する。
///
/// 【将来、型安全なスキーマに置き換える経路】
/// [executor] は drift の [QueryExecutor] であるため、地域パックDBのスキーマが
/// 確定した時点で `GeneratedDatabase` のサブクラス（`GameDatabase` と同様の
/// `@DriftDatabase(tables: [...])` 構成）のコンストラクタにそのまま渡せる。
/// それまでの間は [rawSelect] で生SQLクエリを実行できる。
class RegionPackConnection {
  RegionPackConnection._(this.executor, this._rawDatabase);

  /// drift の実行口。地域パックDBのスキーマが確定した際、これを
  /// `GeneratedDatabase` サブクラスのコンストラクタへそのまま渡す想定。
  final QueryExecutor executor;

  final sqlite3.Database _rawDatabase;

  /// [packFilePath] にある地域パックDBファイルを**読み取り専用**で開く。
  ///
  /// 同梱パック（plan.md §3.3 の MVP 方針。`app/assets/` に同梱）を想定した
  /// ファイルパスを渡すこと。ファイルが存在しない場合は
  /// [sqlite3.SqliteException] を送出する。
  factory RegionPackConnection.open(String packFilePath) {
    final rawDatabase = sqlite3.sqlite3.open(
      packFilePath,
      mode: sqlite3.OpenMode.readOnly,
    );
    final executor = NativeDatabase.opened(
      rawDatabase,
      // この QueryExecutor を close() したときに、内部の sqlite3.Database も
      // 一緒に close する（接続を使い捨てにできるようにする）。
      closeUnderlyingOnClose: true,
    );
    return RegionPackConnection._(executor, rawDatabase);
  }

  /// テスト用: インメモリの地域パックDB相当を読み取り専用接続として開く。
  ///
  /// インメモリDBは元々「書き込み可能な状態で作る→テストデータを投入する」
  /// 手順が必要なため、渡された [seed] コールバックで先に投入してから
  /// 読み取り専用の [RegionPackConnection] として包み直す。
  factory RegionPackConnection.forTesting({
    void Function(sqlite3.Database database)? seed,
  }) {
    final rawDatabase = sqlite3.sqlite3.openInMemory();
    seed?.call(rawDatabase);
    final executor = NativeDatabase.opened(
      rawDatabase,
      closeUnderlyingOnClose: true,
    );
    return RegionPackConnection._(executor, rawDatabase);
  }

  /// 地域パックDBの実スキーマが未確定な間の暫定的な読み取り口。
  ///
  /// 書き込み系SQL文を渡した場合は SQLite 自身がエラーを返す（上記クラスコメント参照）。
  sqlite3.ResultSet rawSelect(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    return _rawDatabase.select(sql, parameters);
  }

  /// テスト専用: 書き込み系SQL文が実際に `SQLITE_READONLY` で拒否されることを
  /// 検証するための実行口（`test/db/region_pack_connection_test.dart` 参照）。
  /// 通常の呼び出し側はこのメソッドを使わないこと（読み取り専用という設計意図に反する）。
  @visibleForTesting
  void rawExecuteForTesting(String sql) => _rawDatabase.execute(sql);

  Future<void> close() => executor.close();
}
