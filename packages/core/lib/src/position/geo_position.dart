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
  ///
  /// **単調時計の値を保持しうる**（Android の `elapsedRealtime` 相当。plan.md §7
  /// 「時刻は単調時計」）。壁時計（改竄可能）を保持する保証はない。
  /// `packages/core/lib/src/antispoof/speed_filter.dart`（[SpeedFilter]）は
  /// この前提（単調・非減少列）で速度を計算する。[NativePositionProvider]
  /// （`packages/location`）が実機の値からこのフィールドを組み立てる際の方針は
  /// そのクラスのドキュメントを参照。
  final DateTime timestamp;

  /// 位置の推定精度（半径）。取得できない場合は null。
  final Distance? accuracy;

  /// この観測が偽装（なりすまし位置）の疑いがあるか。
  ///
  /// ## 追加した理由（2026-09-11 代表決定・Issue #124）
  /// 「偽装の疑いがある」という概念自体はプラットフォーム中立なドメイン概念であり
  /// （Android の `Location.isMock()`/`isFromMockProvider()` に限らず、iOS にも
  /// 同等の判定手段がある想定）、`core` に置いても GPS_ARCHITECTURE に反しない。
  /// **フィールド名・型に Android の用語（`isFromMockProvider`・`isMock` 等）を
  /// 持ち込まない**（Issue #124 本文の明示的な指示）。
  ///
  /// 持たせない場合、Kotlin 側のモック検出（Issue #126）と `core` 側の速度判定
  /// （[SpeedFilter]・Issue #125）が別々の経路になり、Issue #9 の段階的ペナルティ
  /// （モック検出＝無効化／速度・歩数の不一致＝レート低下）を1か所で判定できなくなる。
  ///
  /// ## 既定値は false（疑いなし）
  /// 理由: (1) 既存の `GeoPosition` 生成箇所（テスト・`FakePositionProvider` 等）は
  /// モックという概念自体を知らないため、既定を true にすると「未判定」ではなく
  /// 「疑いあり確定」のように読めてしまい意味が反転する。(2) 判定ロジック
  /// （Issue #126）が実装されるまでの間、この値を明示的に設定するのは
  /// [NativePositionProvider] のみであり、それ以外の生成箇所は「疑いなし」を返す方が
  /// 安全側（false negative であって false positive ではない）である。
  ///
  /// 値を**設定する**のは Issue #126（Kotlin 側のモック検出の判定ロジックそのもの）。
  /// 本 Issue（#124）が行うのは受け皿の定義と、`location_track.sqlite` の
  /// `possible_mock_location` 列（Android の `isMock()`/`isFromMockProvider()` の
  /// **生の値**をそのまま保存したもの。判定ロジックではない）を
  /// [NativePositionProvider] がそのまま写すところまで（判定ロジック自体は実装しない）。
  final bool spoofSuspected;

  /// この観測が属する「記録セッション」の不透明な識別子。
  ///
  /// ## 追加した理由（2026-09-11・Issue #124）
  /// [timestamp] に単調時計（`elapsedRealtime` 相当）を使う実装（[NativePositionProvider]）
  /// では、その時計は**端末再起動でリセットされる**。そのため記録セッション
  /// （foreground service の起動単位）ごとに新しい識別子を発行しており、
  /// **異なるセッションの [GeoPosition] 同士は [timestamp] の差分・比較を
  /// 行ってはならない**（`speed_filter.dart` の [SpeedFilter] が単調時計を前提に
  /// しているため、セッション境界をまたぐと速度判定が破綻する。
  /// `docs/location-track-db.md` §5参照）。
  ///
  /// `core` はこの識別子の中身（Kotlin の `session_id`・UUID文字列など）に一切関心を
  /// 持たない。**不透明な値**として「同じ値なら同一の連続した記録区間」「異なる値
  /// （または片方が null）なら [timestamp] の連続性を仮定してはならない」という
  /// 意味だけを持つ。この意味づけ自体はプラットフォーム中立（iOS 実装でも
  /// 「アプリのフォアグラウンド位置取得セッション」という同種の区切りが必要になる
  /// はず）であり、Android の実装詳細（`elapsedRealtime`・DBの `session_id` 列名）は
  /// このフィールド名・型に持ち込んでいない。
  ///
  /// ## 既定値は null
  /// 意味は「セッション情報なし＝呼び出し側が連続性を管理する（または単一の連続した
  /// 記録区間として扱ってよい）」。既存の `GeoPosition` 生成箇所（テスト・
  /// `FakePositionProvider` 等）はこの概念を知らないため、既定で「区切りなし」として
  /// 後方互換に振る舞う（[splitByTrackingSession] のドキュメント参照）。
  ///
  /// この境界を実際に守って位置の列を分割する責務は、[PositionProvider.positionUpdates]
  /// を消費する側（将来 [SpeedFilter] に接続する呼び出し側）にある。本 Issue の時点では
  /// その配線自体は行っていない（[splitByTrackingSession] はその配線が使うための
  /// ユーティリティとして用意した）。
  final String? trackingSessionId;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.spoofSuspected = false,
    this.trackingSessionId,
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
      other.accuracy == accuracy &&
      other.spoofSuspected == spoofSuspected &&
      other.trackingSessionId == trackingSessionId;

  @override
  int get hashCode => Object.hash(
        latitude,
        longitude,
        timestamp,
        accuracy,
        spoofSuspected,
        trackingSessionId,
      );

  @override
  String toString() => 'GeoPosition(lat: $latitude, lon: $longitude, at: $timestamp, '
      'accuracy: $accuracy, spoofSuspected: $spoofSuspected, '
      'trackingSessionId: $trackingSessionId)';
}
