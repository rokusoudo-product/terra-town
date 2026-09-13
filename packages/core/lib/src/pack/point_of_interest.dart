import '../geo/hex_id.dart';

/// 名所POI（名所図鑑 #6/#12 統合）の識別子（T024）。
///
/// 出典: `specs/001-mvp/plan.md` §3.2「名所POI | SQLite `poi(id, lat, lon, kind, name)`
/// | OSM 観光POI 抽出」。OSM由来のID等をそのまま保持する不透明な識別子として扱う。
class PointOfInterestId {
  /// POIを一意に表す文字列。
  final String value;

  const PointOfInterestId(this.value)
      : assert(value != '', 'PointOfInterestId は空文字を許容しない');

  @override
  bool operator ==(Object other) =>
      other is PointOfInterestId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'PointOfInterestId($value)';
}

/// 名所POI 1件のデータ（T024。[hexId] はIssue #158）。
///
/// 出典: plan.md §3.2 `poi(id, lat, lon, kind, name)`（OSM観光POI抽出）。
/// 緯度経度は地図上の表示（マーカー配置）に用いる事前計算済みの静的データであり、
/// GPS・地図SDKの型ではないため Issue #81 受け入れ基準（GPS・地図SDKの型を
/// 露出しない）には抵触しない。
class PointOfInterest {
  /// このPOIの識別子。
  final PointOfInterestId id;

  /// POIの名称。
  final String name;

  /// POIの種別（例: 観光地・史跡等。分類の正は `tools/pack-builder/` の抽出ルール）。
  final String kind;

  /// 緯度〔度〕。範囲: -90.0〜90.0。
  final double latitude;

  /// 経度〔度〕。範囲: -180.0〜180.0。
  final double longitude;

  /// このPOIが属するヘクス（Issue #158・`tools/pack-builder/extract_poi.py`が
  /// パック生成時にH3で事前計算済み。`region_pack.sqlite`の`hex_poi`テーブル）。
  ///
  /// **`null`になりうる（forward-compat）**: `hex_poi`が同梱されていない旧パック
  /// から読み込んだ場合は`null`になる（`RegionPackRepository`のクラスコメント参照）。
  /// `core`はGPS_ARCHITECTURE準拠で緯度経度→ヘクスの変換ロジックを持たないため、
  /// この値が`null`のPOIについて所属ヘクスを独自に計算し直すことはできない
  /// （`RegionPack.pointsOfInterestIn` はそのようなPOIを返さない）。
  final HexId? hexId;

  const PointOfInterest({
    required this.id,
    required this.name,
    required this.kind,
    required this.latitude,
    required this.longitude,
    this.hexId,
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
      other is PointOfInterest &&
      other.id == id &&
      other.name == name &&
      other.kind == kind &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.hexId == hexId;

  @override
  int get hashCode => Object.hash(id, name, kind, latitude, longitude, hexId);

  @override
  String toString() =>
      'PointOfInterest(id: $id, name: $name, kind: $kind, lat: $latitude, lon: $longitude, hexId: $hexId)';
}
