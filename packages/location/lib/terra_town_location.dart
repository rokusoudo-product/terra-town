/// terra-town の GPS・地図・測位レイヤー。
///
/// GPS_ARCHITECTURE 準拠: 依存は location -> core の一方向。
/// `terra_town_core` が定義する抽象をここで実装し、地図SDK（MapLibre）や
/// ネイティブの位置取得（Kotlin foreground service / Pigeon channel）を隠蔽する。
///
/// 実装予定の構成は `specs/001-mvp/tasks.md` を参照:
///   - src/position/ NativePositionProvider（T050・実装済み。Issue #124。Issue #131 で
///     `location_track.sqlite` の直接読み取りから Pigeon 経由の取得に変更。Issue #108 で
///     `LocationPointMessage.hexId` の受け渡しを追加）・
///     NativeLocationTrackingControl（Pigeon `LocationTrackingHostApi` の
///     ラッパー。T049）・RecordedHexLocator（`HexLocator` 抽象の本番実装。Issue #108。
///     緯度経度→H3の変換自体は Kotlin 側 `H3HexIndexer` が記録時点で行い、本クラスは
///     `GeoPosition.hexId` を返すだけ。旧 `H3HexLocator`〔`h3_flutter`〕は撤去済み）
///   - src/pack/     RegionPackRepository（T069）
///   - src/map/      MapView・FogOfWarLayer・各種レイヤー（T055〜T056・T071・T090・T094）
///   - src/db/       GameDatabase・RegionPackConnection（T030〜T034・Issue #83）。
///     `location_track.sqlite` は Issue #131（2026-09-11 代表決定）により
///     **Kotlin 側のみが開く**ため、Dart 側の読み取り専用接続クラス
///     （`LocationTrackConnection`）は削除済み（`docs/location-track-db.md` §2・§3）。
///     RewardSettingsRepository（Issue #135・歩数判定オプトアウト設定の
///     `settings` テーブルへの読み書き・`RewardPolicy` への橋渡し）もここに置く。
library;

import 'package:terra_town_core/terra_town_core.dart';

export 'src/db/building_type.dart';
export 'src/db/game_database.dart';
export 'src/db/region_pack_connection.dart';
export 'src/db/reward_settings_repository.dart';
export 'src/map/fog_hex_source.dart';
export 'src/map/fog_of_war_layer.dart';
export 'src/map/map_camera_position.dart';
export 'src/map/mbtiles_asset.dart';
export 'src/map/mbtiles_source.dart';
export 'src/map/map_view.dart';
export 'src/position/location_api.g.dart';
export 'src/position/native_location_tracking_control.dart';
export 'src/position/native_position_provider.dart';
export 'src/position/recorded_hex_locator.dart';

/// 土台の疎通確認用。location から core を参照できることを示す。
/// 逆方向（core -> location）は tools/check_import_direction.sh が禁止する。
String locationScaffoldMarker() => 'terra_town_location -> $coreScaffoldMarker';
