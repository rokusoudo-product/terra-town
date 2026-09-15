/// 建物の種別（3系統8種。T082）。
///
/// 出典: `docs/buildings.md` §2「建物種別（MVP・3系統8種）」。
/// 住宅系（住宅・マンション）・生産系（畑・農場・工場・採石場）・
/// 娯楽系（リゾート・ミュージアム）の3系統・計8種。この enum は同ドキュメントの
/// 3系統・掲載順にそのまま対応させている。
///
/// 【`packages/location` との関係・Issue #191】
/// 元々 `packages/location/lib/src/db/building_type.dart` に `building` テーブル
/// （T033・Drift）専用の enum として定義されていた（Issue #83 時点では
/// `packages/core` 側の建物種別がまだ確定していなかったため）。本 Issue（#191）で
/// `core` に一本化し、`location` は本 enum をそのまま使うよう変更した
/// （GPS_ARCHITECTURE 準拠・依存は location -> core の一方向）。
///
/// **列挙値の名前は1文字も変えていない。** `building` テーブルの `buildingType`
/// 列は `textEnum<BuildingType>()`（`.name` を文字列として永続化）で保存して
/// いるため、名前を変えると既存セーブデータの復元に失敗する
/// （`packages/location/lib/src/db/game_database.dart` の `Buildings` テーブル
/// 定義・`GameDatabase.schemaVersion` は本 Issue で変更していない）。
enum BuildingType {
  /// 住宅系: 住宅（人口上限 少なめ。buildings.md §5.1）。
  house,

  /// 住宅系: マンション（人口上限 多め。buildings.md §5.1）。
  apartment,

  /// 生産系: 畑（野菜・フルーツを生産。buildings.md §2）。
  cropField,

  /// 生産系: 農場（肉を生産。★新資材・buildings.md §6.1）。
  livestockFarm,

  /// 生産系: 工場（生産率向上・街全体の産出に効く。buildings.md §2）。
  factoryBuilding,

  /// 生産系: 採石場（石・鉄を産出。空き地であればどこでも建築可、山への隣接は
  /// 産出倍率のみに影響する。buildings.md §2・§6.3・Issue #72）。
  quarry,

  /// 娯楽系: リゾート（海に隣接する空き地に建築。buildings.md §2）。
  resort,

  /// 娯楽系: ミュージアム（プレイヤーが建設した住宅系建物に隣接する空き地に建築。
  /// buildings.md §2・Issue #70 で配置制約を再定義）。
  museum,
}
