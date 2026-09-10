import 'package:flutter/foundation.dart' show immutable;

/// [MapView] の初期カメラ位置を表す値オブジェクト。
///
/// `terra_town_location` は地図SDK（MapLibre）を隠蔽する方針
/// （`terra_town_location.dart` 冒頭コメント）のため、呼び出し側（`app`）は
/// MapLibre の `CameraPosition`/`LatLng` 型を直接扱わずに済むよう、
/// 本パッケージ独自の値オブジェクトとして提供する。
@immutable
class MapCameraPosition {
  const MapCameraPosition({
    required this.latitude,
    required this.longitude,
    this.zoom = 0,
    this.tilt = 0,
    this.bearing = 0,
  });

  final double latitude;
  final double longitude;

  /// ズームレベル。
  final double zoom;

  /// カメラの傾き（度）。0 は真上から見下ろす状態。
  ///
  /// DESIGN.md「アートディレクション」の技術的含意(1)「カメラの pitch（傾き）を
  /// 付けた俯瞰 — ほぼ無料でミニチュア感が出る。最優先」に対応するパラメータ。
  final double tilt;

  /// 方位（度。真北 = 0、時計回り）。
  final double bearing;
}
