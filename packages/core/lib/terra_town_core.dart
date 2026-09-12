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
///                     DisclosedHexSet（圧縮表現）・DisclosedHex（開示時点の地形分類
///                     スナップショットによるパック更新の不変性ルール）
///                     （T035〜T036・実装済み。Issue #96 で `PackVersionResolver` を廃止し
///                     スナップショット方式に改訂）
///   - src/repository/ `Repository<T, ID>` 抽象（T038・実装済み）
///   - src/economy/    Resource・Inventory（T026〜T027・実装済み）・
///                     地形産出（受動・時間ベース）の決定論的な計算
///                     （T066・T068・実装済み。Issue #138）・
///                     開放ポイントの歩行距離換算の決定論的な計算
///                     （T063・実装済み。Issue #143。自然回復〔1P/日〕は
///                     MVPでは未実装。理由は opening_point_accrual_service.dart 参照）
///   - src/disclosure/ HexLocator 抽象・DisclosureService（開示判定ロジック）
///                     （T054・実装済み。Issue #101）
///   - src/antispoof/  SpeedFilter（移動平均平滑化後の速度による偽装対策判定）
///                     （T100・実装済み。Issue #125）・RewardPolicy（モック検出・
///                     速度・歩数の段階的ペナルティを1か所に集約する判定。
///                     T099・T101・実装済み。Issue #126）
library;

export 'src/terra_town_core_base.dart';
export 'src/antispoof/reward_policy.dart';
export 'src/antispoof/speed_filter.dart';
export 'src/disclosure/disclosure_service.dart';
export 'src/disclosure/hex_locator.dart';
export 'src/economy/inventory.dart';
export 'src/economy/opening_point_accrual_service.dart';
export 'src/economy/resource.dart';
export 'src/economy/resource_grant_service.dart';
export 'src/economy/terrain_hex_counter.dart';
export 'src/geo/distance.dart';
export 'src/geo/hex_geometry.dart';
export 'src/geo/hex_id.dart';
export 'src/geo/tile_id.dart';
export 'src/pack/disclosed_hex.dart';
export 'src/pack/disclosed_hex_set.dart';
export 'src/pack/district.dart';
export 'src/pack/pack_version.dart';
export 'src/pack/point_of_interest.dart';
export 'src/pack/region_pack.dart';
export 'src/position/geo_position.dart';
export 'src/position/position_provider.dart';
export 'src/position/tracking_session.dart';
export 'src/repository/repository.dart';
export 'src/terrain/terrain_type.dart';
export 'src/terrain/terrain_yield.dart';
