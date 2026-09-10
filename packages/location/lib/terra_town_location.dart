/// terra-town の GPS・地図・測位レイヤー。
///
/// GPS_ARCHITECTURE 準拠: 依存は location -> core の一方向。
/// `terra_town_core` が定義する抽象をここで実装し、地図SDK（MapLibre）や
/// ネイティブの位置取得（Kotlin foreground service / Pigeon channel）を隠蔽する。
///
/// 実装予定の構成は `specs/001-mvp/tasks.md` を参照:
///   - src/position/ NativePositionProvider（T050・未実装）・
///     H3HexLocator（`HexLocator` 抽象の暫定実装。Issue #115。Kotlin側への
///     移行予定はIssue #108・`future`）
///   - src/pack/     RegionPackRepository（T069）
///   - src/map/      MapView・FogOfWarLayer・各種レイヤー（T055〜T056・T071・T090・T094）
///   - src/db/       GameDatabase・RegionPackConnection（T030〜T034・Issue #83）
library;

import 'package:terra_town_core/terra_town_core.dart';

export 'src/db/building_type.dart';
export 'src/db/game_database.dart';
export 'src/db/region_pack_connection.dart';
export 'src/map/fog_hex_source.dart';
export 'src/map/fog_of_war_layer.dart';
export 'src/map/map_camera_position.dart';
export 'src/map/mbtiles_asset.dart';
export 'src/map/mbtiles_source.dart';
export 'src/map/map_view.dart';
export 'src/position/hex_locator_h3.dart';

/// 土台の疎通確認用。location から core を参照できることを示す。
/// 逆方向（core -> location）は tools/check_import_direction.sh が禁止する。
String locationScaffoldMarker() => 'terra_town_location -> $coreScaffoldMarker';
