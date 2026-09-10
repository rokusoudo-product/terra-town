import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'building_type.dart';

part 'game_database.g.dart';

/// 建築状態軸（`docs/terrain.md` §1.1）。
///
/// `building` テーブル（T033）に行が存在する時点でマスの建築状態は常に「建築後」だが
/// （未建築のマスは `building` テーブルに行を持たない）、terrain.md §1.1 の2値の軸を
/// スキーマ上でも明示的に読み取れるようにするため、あえて列として保持する。
/// 将来「撤去済み」等の状態が必要になった場合も、行を消さずこの列を追加すれば
/// 履歴を残したまま表現できる（本 Issue のスコープ外）。
enum BuildingConstructionState {
  /// 建築後（terrain.md §1.1「未建築 / 建築後」のうち後者）。MVP ではこの値のみを使う。
  built,
}

/// `disclosed_hex` テーブル（T031）。
///
/// 出典: `specs/001-mvp/plan.md` §6「`disclosed_hex`（開示済みヘクス・`pack_version`）」。
/// 1ヘクスにつき1行（[hexId] が主キー）。[packVersion] は開示**当時**のパックバージョンを
/// 記録する列であり、パック更新後も過去分は不変とする不変性ルール（plan.md §3.3）の
/// 前提となる。**不変性ルールそのものの実装は別 Issue（#84・T035〜T037）が担当し、
/// 本テーブルはそのための列を用意するに留める。**
///
/// 開示ヘクス集合の圧縮表現（Roaring Bitmap / ビットセット・plan.md §6）は同じく
/// Issue #84（T035）が担当するため、本テーブルは1行1ヘクスの素直な表現とする
/// （集合の圧縮は読み出し側でこのテーブルを集約して行う想定）。
@DataClassName('DisclosedHexRow')
class DisclosedHexes extends Table {
  @override
  String get tableName => 'disclosed_hex';

  /// H3 セルインデックス（`docs/terrain.md` §4.2）。`core` の `HexId.value` と対応する
  /// 非負整数。Dart の `int`（64bit 符号付き）でそのまま表現できる
  /// （H3 index は上位ビットにモード情報を含むが実質63bit以内に収まる）。
  IntColumn get hexId => integer()();

  /// このヘクスを開示した時点の地域パックバージョン（`PackVersion.value` と対応）。
  TextColumn get packVersion => text()();

  /// 開示した日時（端末のウォールクロック。位置記録自体の時刻は
  /// `elapsedRealtime` を使うが〔plan.md §7〕、これは記録の正ではなく
  /// UI 表示・デバッグ用のタイムスタンプ）。
  DateTimeColumn get discoveredAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {hexId};
}

/// `inventory` テーブル（T032）。
///
/// 出典: plan.md §6「`inventory`（資材）」。
///
/// 【`core` の `Resource` 型に依存しない理由（Issue #83 本文の注意書きに基づく判断）】
/// `packages/core/lib/src/economy/resource.dart` に資材種別 enum を追加する作業
/// （tasks.md T026、Issue #82・PR #89）が本 Issue と並行して進んでおり、
/// 本 Issue の時点では **未マージ**。未マージのコードに `location` 側の永続化スキーマを
/// 依存させると PR 間で結合が生まれてしまうため、[resourceKey] は `core` の enum を
/// 参照せず**生の文字列**として保持するに留める。想定する値は
/// `specs/001-mvp/spec.md` §6 の資材体系（建設系: 木・石・鉄／生活系: 塩・水・
/// 野菜・フルーツ・肉）に対応する文字列（例: `core` 側 enum が定まった際の `.name`）を
/// 置く想定だが、その対応付け自体は別途整備すること（本 Issue のスコープ外）。
/// 1資材種別につき1行（[resourceKey] が主キー）。
@DataClassName('InventoryRow')
class Inventories extends Table {
  @override
  String get tableName => 'inventory';

  /// 資材種別を表す生の文字列キー（上記のとおり `core` の enum には未依存）。
  TextColumn get resourceKey => text()();

  /// 所持数。負値は取らない想定だが、制約の強制は上位層（`core`）の責務とし、
  /// スキーマ上は素直な整数列とする。
  IntColumn get amount => integer().withDefault(const Constant(0))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {resourceKey};
}

/// `building` テーブル（T033）。
///
/// 出典: plan.md §6「`building`（建物・建築状態軸 terrain.md §1、区画・座標）」、
/// Issue #83 本文「建物種別・レベル・建築状態軸・ヘクス座標・区画」。
/// `docs/buildings.md` §2 の **3系統8種**（住宅・マンション・畑・農場・工場・
/// **採石場**・リゾート・ミュージアム）を [BuildingType] で表現する
/// （7種を前提にしないこと。採石場は Issue #72 で追加された8種目）。
///
/// 「1マス1建物」（buildings.md §3）の原則を [hexId] の一意制約で表現する。
@DataClassName('BuildingRow')
class Buildings extends Table {
  @override
  String get tableName => 'building';

  IntColumn get id => integer().autoIncrement()();

  /// このマス（ヘクス）の H3 セルインデックス。`disclosed_hex.hexId` と同じ体系。
  /// 「開示済みかつ空き地」のマスにのみ建築できる（buildings.md §3）という制約自体は
  /// `core`（判定ロジック）側の責務であり、本テーブルは結果だけを保持する。
  IntColumn get hexId => integer()();

  /// 建物種別（buildings.md §2 の8種）。列挙値の並べ替え・追加に強い
  /// `textEnum`（`.name` を文字列として永続化）で保存する。
  TextColumn get buildingType => textEnum<BuildingType>()();

  /// アップグレード段階（Lv.1〜Lv.3・仮。buildings.md §4.2）。初期建築は Lv.1。
  IntColumn get level => integer().withDefault(const Constant(1))();

  /// 建築状態軸（terrain.md §1.1）。本テーブルに行がある時点で常に [built]
  /// だが、明示的な列として保持する理由は [BuildingConstructionState] のドキュメント参照。
  TextColumn get constructionState =>
      textEnum<BuildingConstructionState>()
          .withDefault(Constant(BuildingConstructionState.built.name))();

  /// このマスが属する行政区画（`DistrictId.value` と対応）。パック範囲外・
  /// 未帰属の場合は null（`core` の `RegionPack.districtOf` が null を返す場合に対応）。
  TextColumn get districtId => text().nullable()();

  DateTimeColumn get builtAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column>> get uniqueKeys => [
        {hexId}, // 1マス1建物（buildings.md §3）
      ];
}

/// `district_progress` テーブル（T034）。
///
/// 出典: plan.md §6「`district_progress`（制覇率・発展度）」。
/// 具体的な算出式・発展度の定義は balance 検討（plan/tasks 工程）で確定するため
/// （buildings.md §4.2 と同様に本 Issue は仮値ではなく型のみを決める）、
/// [conquestRate]・[developmentScore] は汎用的な実数列として持たせるに留める。
@DataClassName('DistrictProgressRow')
class DistrictProgresses extends Table {
  @override
  String get tableName => 'district_progress';

  /// 区画識別子（`DistrictId.value` と対応）。
  TextColumn get districtId => text()();

  /// 制覇率。0.0〜1.0 を想定するが、範囲の強制は上位層の責務とする
  /// （分母は「区画内の到達可能ヘクス」— plan.md §5 代表回答）。
  RealColumn get conquestRate => real().withDefault(const Constant(0.0))();

  /// 発展度。具体的な算出式は balance 検討で確定する仮の実数値。
  RealColumn get developmentScore =>
      real().withDefault(const Constant(0.0))();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {districtId};
}

/// `collection` テーブル（T034・名所図鑑 #6/#12 統合）。
///
/// 出典: plan.md §6「`collection`（名所図鑑・#6/#12統合）」。
/// POI 1件の発見につき1行（[poiId] が主キー）。POI のメタデータ（名称・種別・
/// 緯度経度）自体は地域パック側（読み取り専用）が正であり、本テーブルは
/// 「いつ発見したか」という**プレイヤーの進捗**だけを保持する。
@DataClassName('CollectionRow')
class Collections extends Table {
  @override
  String get tableName => 'collection';

  /// `PointOfInterestId.value` と対応。
  TextColumn get poiId => text()();

  DateTimeColumn get discoveredAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {poiId};
}

/// `quest_daily` テーブル（T034・#11・端末内生成）。
///
/// 出典: plan.md §6「`quest_daily`（#11・端末内生成）」。
/// クエスト内容の具体的な生成ロジック（#11）は本 Issue のスコープ外のため、
/// [questKey] はクエスト種別を表す生の文字列キーに留め、進捗・達成状況のみを
/// スキーマとして定義する。
@DataClassName('QuestDailyRow')
class QuestDailies extends Table {
  @override
  String get tableName => 'quest_daily';

  IntColumn get id => integer().autoIncrement()();

  /// このクエストが属する日（端末のローカル日付の 00:00 を想定。タイムゾーン等の
  /// 扱いは生成ロジック側〔#11〕の責務）。
  DateTimeColumn get questDate => dateTime()();

  /// クエスト種別を表す生の文字列キー（生成ロジックは #11 側の責務）。
  TextColumn get questKey => text()();

  IntColumn get progress => integer().withDefault(const Constant(0))();

  IntColumn get goal => integer()();

  BoolColumn get completed => boolean().withDefault(const Constant(false))();

  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {questDate, questKey}, // 同じ日に同じクエストを重複生成しない
      ];
}

/// `settings` テーブル（T034・プライバシーゾーン等）。
///
/// 出典: plan.md §6「`settings`（プライバシーゾーン等）」。
/// 設定項目の具体的な内訳（プライバシーゾーンの座標・半径等）は本 Issue の
/// スコープ外（実際のデータ投入・ゲームロジックは書かない）のため、汎用的な
/// key-value 列とし、値の解釈（JSON 等）は呼び出し側に委ねる。
@DataClassName('SettingRow')
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();

  /// 設定値。複合的な値（例: プライバシーゾーンのリスト）は呼び出し側が
  /// JSON 文字列にエンコードして保持する想定。
  TextColumn get value => text()();

  DateTimeColumn get updatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {key};
}

/// ゲーム状態DB（T030）。
///
/// 出典: plan.md §6「ストレージ: SQLite（Drift 等）。ゲーム状態・地域パック
/// （読み取り専用）を分離」。本クラスは**ゲーム状態側**（読み書き可能）を表す。
/// 地域パック側（読み取り専用）は [RegionPackConnection]（`region_pack_connection.dart`）
/// として**別の接続**に分離しており、本クラスとは接続を共有しない
/// （誤って地域パックへ書き込む経路を構造的に作らないため）。
@DriftDatabase(
  tables: [
    DisclosedHexes,
    Inventories,
    Buildings,
    DistrictProgresses,
    Collections,
    QuestDailies,
    Settings,
  ],
)
class GameDatabase extends _$GameDatabase {
  GameDatabase(super.executor);

  /// 端末内の既定の保存先（アプリのドキュメントディレクトリ配下
  /// `game_state.sqlite`）を使う実運用向けインスタンス。
  ///
  /// `LazyDatabase` でファイルI/O（ディレクトリ解決）を遅延させ、
  /// 実際の SQLite オープンはバックグラウンド Isolate で行う
  /// （`NativeDatabase.createInBackground`）ことで、DB 初期化が UI スレッドを
  /// ブロックしないようにしている。
  factory GameDatabase.defaultConnection() {
    return GameDatabase(
      LazyDatabase(() async {
        final directory = await getApplicationDocumentsDirectory();
        final file = File(p.join(directory.path, 'game_state.sqlite'));
        return NativeDatabase.createInBackground(file);
      }),
    );
  }

  /// テスト用のインメモリDB。ファイルI/Oを伴わないため単体テストで使う。
  factory GameDatabase.forTesting() => GameDatabase(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        // 将来のスキーマ変更（列追加・テーブル追加等）は schemaVersion を上げたうえで
        // ここに onUpgrade のステップを追加すること
        // （https://drift.simonbinder.eu/docs/advanced-features/migrations/ の
        // stepByStep 方式を推奨）。本 Issue（#83）は初期スキーマ（v1）の導入のみを
        // 担当するため、onUpgrade は未実装。
      );
}
