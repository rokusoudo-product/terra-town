/// terra-town のゲームロジック（純粋 Dart）。
///
/// GPS_ARCHITECTURE 準拠: 本ライブラリは GPS・地図・Flutter に依存しない。
/// 位置は [PositionProvider] などの抽象を通してのみ受け取り、
/// 実装は `terra_town_location` 側に置く（依存は location -> core の一方向）。
///
/// 実装予定の構成は `specs/001-mvp/tasks.md` Phase 3 を参照:
///   - src/geo/      HexId・TileId・Distance（T020〜T021）
///   - src/terrain/  TerrainType・地形→資材マッピング（T022・T028）
///   - src/position/ PositionProvider 抽象（T023）
///   - src/pack/     RegionPack 抽象・pack_version（T024）
///   - src/economy/  Resource・Inventory（T026〜T027）
library;

export 'src/terra_town_core_base.dart';
