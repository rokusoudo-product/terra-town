import 'package:terra_town_core/terra_town_core.dart';

/// [GeoPosition] 1件に、その記録が由来する `location_point` テーブルの行 `id`
/// （Pigeon の `LocationPointMessage.id`）を添えたもの（Issue #138）。
///
/// ## なぜ `GeoPosition`（`core`）に足さないか
/// 行 `id` は `packages/location`（Pigeon・`location_track.sqlite`）が持つ
/// 永続化層の実装詳細であり、GPS_ARCHITECTURE 準拠の `core` に持ち込まない
/// （`GeoPosition` のクラスdoc「GPS・地図SDKの型は一切公開せず、緯度経度・時刻・
/// 精度といった計算済みの値だけを保持する」という方針と同じ理由）。
/// [TerrainYieldAccrualCoordinator]（`app/lib/map/economy/`）が二重計上防止の
/// ウォーターマーク（「最後に計上した行 id」）として必要とするため、
/// `location` 層のこの薄いラッパー型で運ぶ。
///
/// [NativePositionProvider.recordedPositionUpdates] が実際に流す型。
/// 行 id を必要としない既存の呼び出し側（fog of war の開示判定・デバッグパネルの
/// 位置ログ表示等）は、引き続き [NativePositionProvider.positionUpdates]
/// （`Stream<GeoPosition>`）を使えばよい（後方互換）。
class LocationPointRecord {
  const LocationPointRecord({required this.rowId, required this.position});

  /// `location_point.id`（Kotlin側 autoincrement・単調増加・一意）。
  final int rowId;

  final GeoPosition position;

  @override
  bool operator ==(Object other) =>
      other is LocationPointRecord &&
      other.rowId == rowId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(rowId, position);

  @override
  String toString() => 'LocationPointRecord(rowId: $rowId, position: $position)';
}
