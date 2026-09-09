import '../geo/distance.dart';

/// 位置情報の1点分の観測値（GPS等での計測結果）。
///
/// GPS_ARCHITECTURE 準拠（`C:\Users\moets\.claude\GPS_ARCHITECTURE.md`）・
/// Issue #81 受け入れ基準:
/// GPS・地図SDKの**型**（例: `geolocator` の `Position`、MapLibre の `LatLng`）は
/// 一切公開せず、緯度経度・時刻・精度といった**計算済みの値だけ**を保持する。
/// 緯度経度から [HexId]／[TileId] への変換ロジックそのものは `core` に置かず、
/// `location/` の責務のままとする（hex_id.dart・tile_id.dart のドキュメント参照）。
class GeoPosition {
  /// 緯度〔度〕。範囲: -90.0〜90.0。
  final double latitude;

  /// 経度〔度〕。範囲: -180.0〜180.0。
  final double longitude;

  /// この位置が観測された時刻。
  final DateTime timestamp;

  /// 位置の推定精度（半径）。取得できない場合は null。
  final Distance? accuracy;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
  })  : assert(
          latitude >= -90.0 && latitude <= 90.0,
          '緯度は -90.0〜90.0 の範囲でなければならない',
        ),
        assert(
          longitude >= -180.0 && longitude <= 180.0,
          '経度は -180.0〜180.0 の範囲でなければならない',
        );

  @override
  bool operator ==(Object other) =>
      other is GeoPosition &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.timestamp == timestamp &&
      other.accuracy == accuracy;

  @override
  int get hashCode => Object.hash(latitude, longitude, timestamp, accuracy);

  @override
  String toString() =>
      'GeoPosition(lat: $latitude, lon: $longitude, at: $timestamp, accuracy: $accuracy)';
}
