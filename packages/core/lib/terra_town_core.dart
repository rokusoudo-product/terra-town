/// terra-town のゲームロジック（純粋 Dart）。
///
/// GPS_ARCHITECTURE 準拠: 本ライブラリは GPS・地図・Flutter に依存しない。
/// 位置は [PositionProvider] などの抽象を通してのみ受け取り、
/// 実装は `terra_town_location` 側に置く（依存は location -> core の一方向）。
///
/// 実装予定の構成は `specs/001-mvp/tasks.md` Phase 3 を参照:
///   - src/geo/        HexId・TileId・Distance（T020〜T021・実装済み）
///   - src/terrain/    TerrainType・地形→資材マッピング（T022・T028 実装済み）
///   - src/position/   PositionProvider 抽象・GeoPosition（T023・実装済み）
///   - src/pack/       RegionPack 抽象・PackVersion・District・PointOfInterest（T024・実装済み）・
///                     DisclosedHexSet（圧縮表現）・DisclosedHex/PackVersionResolver
///                     （パック更新の不変性ルール）（T035〜T036・実装済み）
///   - src/repository/ `Repository<T, ID>` 抽象（T038・実装済み）
///   - src/economy/    Resource・Inventory（T026〜T027・実装済み）
library;

export 'src/terra_town_core_base.dart';
export 'src/economy/inventory.dart';
export 'src/economy/resource.dart';
export 'src/geo/distance.dart';
export 'src/geo/hex_geometry.dart';
export 'src/geo/hex_id.dart';
export 'src/geo/tile_id.dart';
export 'src/pack/disclosed_hex.dart';
export 'src/pack/disclosed_hex_set.dart';
export 'src/pack/district.dart';
export 'src/pack/pack_version.dart';
export 'src/pack/pack_version_resolver.dart';
export 'src/pack/point_of_interest.dart';
export 'src/pack/region_pack.dart';
export 'src/position/geo_position.dart';
export 'src/position/position_provider.dart';
export 'src/repository/repository.dart';
export 'src/terrain/terrain_type.dart';
export 'src/terrain/terrain_yield.dart';
