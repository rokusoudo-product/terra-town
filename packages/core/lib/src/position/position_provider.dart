import 'geo_position.dart';

/// 位置情報の取得口を抽象化するインターフェース（T023）。
///
/// GPS_ARCHITECTURE 準拠（`C:\Users\moets\.claude\GPS_ARCHITECTURE.md` 代替手段1）:
/// `core` 側に必要最小限の抽象を定義し、`location/` がそれを実装する。
/// 依存の向きは常に `location/` → `core/` であり、`core` は
/// GPS・地図SDK（`geolocator`・`maplibre_gl` 等）のいずれにも依存しない。
///
/// **GPS・地図SDK の型は一切露出しない**（Issue #81 受け入れ基準）。
/// 公開するのは [GeoPosition] が保持する緯度経度・時刻・精度といった
/// 計算済みの値のみ。
///
/// 位置更新は GPS_ARCHITECTURE 代替手段3（イベント／コールバック）に従い
/// push 型（[Stream]）で受け渡す。`core` 側が位置を能動的に取りに行くのではなく、
/// 実装（`location/` のフォアグラウンドサービス等）が観測のたびに流す。
///
/// plan.md §10:
/// 「テスト戦略と絡む: `PositionProvider` のフェイク実装＋録画済み歩行ルートの
/// リプレイテスト（core/location分離が活きる場所）」。
/// `core` 側のテストでは実 GPS の代わりにフェイク実装（`implements PositionProvider`）
/// を注入し、固定の [GeoPosition] 列を [positionUpdates] から流す
/// （`test/position/position_provider_test.dart` 参照）。
///
/// 実装（Kotlin ネイティブの距離フィルタ・フォアグラウンドサービス等）は
/// `packages/location`（`NativePositionProvider`・tasks.md T050）に置く。
abstract interface class PositionProvider {
  /// 位置更新の購読。
  ///
  /// 新しい観測が得られるたびに [GeoPosition] を1件流す。
  /// サンプリング方針（距離フィルタ・時間上限など、plan.md §7・Issue #10）や
  /// フォアグラウンド限定である点（plan.md §10）は実装側の責務であり、
  /// この抽象は関知しない。
  Stream<GeoPosition> get positionUpdates;
}
