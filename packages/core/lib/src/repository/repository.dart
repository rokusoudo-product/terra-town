/// エンティティ [T] を識別子 [ID] で読み書きするための永続化層の抽象（T038）。
///
/// 背景（Issue #10 代表回答・2026-07-23/24）:
/// - MVP は端末内完結（BEなし）。実装は `location/`・`app/` 側の SQLite（Drift・
///   tasks.md T030〜T034）で行う。
/// - 「将来のサーバー化を見据え Repository 層で抽象化だけ入れる」との決定に基づき、
///   将来のソーシャル/ランキング機能でのサーバ同期（Issue #16）でも、同じ契約を満たす
///   リモート実装に差し替えられるようにする。同期のプロトコル・コンフリクト解消方針
///   自体は Issue #16 側の検討事項であり、本抽象では扱わない。
///
/// `packages/core` はこの抽象の**定義のみ**を担当する（GPS_ARCHITECTURE 準拠：
/// `core` は SQLite・リモートAPI等の永続化手段のいずれにも依存しない）。
/// 具象実装（SQLite/Drift 版、将来のリモート版）は `packages/location` または
/// `app/` に置くこと。
///
/// **本 Issue（#81）のスコープは抽象の確定までであり、具象実装は空でよい。**
/// `disclosed_hex`・`inventory`・`building`・`district_progress`・`collection`・
/// `quest_daily`・`settings`（plan.md §6 の主なエンティティ）それぞれに対応する
/// 具体的なリポジトリ（例: `InventoryRepository extends Repository<Inventory, ...>`）は、
/// 対応するドメインモデル・スキーマの実装タスク（tasks.md T026〜T037・T030〜T034）で
/// 個別に定義する。
abstract interface class Repository<T, ID> {
  /// [id] に対応するエンティティを取得する。存在しない場合は null。
  Future<T?> findById(ID id);

  /// 保持している全エンティティを取得する。
  Future<List<T>> findAll();

  /// エンティティを新規作成または更新して保存する。
  Future<void> save(T entity);

  /// [id] に対応するエンティティを削除する。
  Future<void> delete(ID id);
}
