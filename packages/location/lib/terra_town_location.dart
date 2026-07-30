/// terra-town の GPS・地図・測位レイヤー。
///
/// GPS_ARCHITECTURE 準拠: 依存は location -> core の一方向。
/// `terra_town_core` が定義する抽象をここで実装し、地図SDK（MapLibre）や
/// ネイティブの位置取得（Kotlin foreground service / Pigeon channel）を隠蔽する。
///
/// 実装予定の構成は `specs/001-mvp/tasks.md` を参照:
///   - src/position/ NativePositionProvider（T050）
///   - src/pack/     RegionPackRepository（T069）
///   - src/map/      MapView・FogOfWarLayer・各種レイヤー（T055〜T056・T071・T090・T094）
library;

import 'package:terra_town_core/terra_town_core.dart';

/// 土台の疎通確認用。location から core を参照できることを示す。
/// 逆方向（core -> location）は tools/check_import_direction.sh が禁止する。
String locationScaffoldMarker() => 'terra_town_location -> $coreScaffoldMarker';
