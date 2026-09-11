import 'geo_position.dart';

/// [positions] を「[GeoPosition.timestamp] の差分・比較を行ってよい連続区間」に
/// 分割する（Issue #124）。
///
/// ## 何のためのユーティリティか
/// `packages/core/lib/src/antispoof/speed_filter.dart`（[SpeedFilter]）は、渡された
/// 位置の列の [GeoPosition.timestamp] が非減少（単調時計）であることを前提に速度を
/// 計算する。[NativePositionProvider]（`packages/location`）が供給する位置は
/// Android の `elapsedRealtime`（端末再起動でリセットされる単調時計）に由来し、
/// 記録セッション（foreground service の起動単位）が変わると、そのセッション内でしか
/// 時刻の差分に意味がない（`docs/location-track-db.md` §5.1・§5.2）。
///
/// 本関数は [GeoPosition.trackingSessionId] が変わる境界で列を分割し、各グループの
/// **内部**でのみ [timestamp] の差分計算（＝[SpeedFilter.classify] への入力）が
/// 安全であることを保証する。**グループをまたいで結合し直して [SpeedFilter.classify]
/// に渡してはならない**——それは本関数を使う意味を無くす。
///
/// ## 境界の判定方法
/// 隣接する2要素の [GeoPosition.trackingSessionId] が等しい（`null == null` を含む）
/// 限り同じグループにまとめ、異なれば新しいグループを開始する。
/// **[GeoPosition.trackingSessionId] が null の要素同士は連続しているとみなす**
/// （後方互換のための意図的な選択。[GeoPosition.trackingSessionId] のドキュメント
/// 「既定値は null」参照）。これは [NativePositionProvider] を使わない呼び出し側
/// （テストのフェイク実装・録画済み歩行ルートなど、そもそもセッションという概念を
/// 持たない位置の列）が、本関数を経由しても一切分割されず、従来どおり1つの連続区間
/// として扱われることを意味する。**セッション境界を明示したい場合にのみ
/// [GeoPosition.trackingSessionId] を設定すること。**
///
/// ## この関数が「配線」ではないことについて
/// 本関数は分割のロジックのみを提供する。実際に [SpeedFilter] へ接続する呼び出し側
/// （どのグループを・いつ・どう扱うか）は本 Issue（#124）のスコープ外であり未実装
/// （`speed_filter.dart` 自体もこの関数を呼ばない。本 Issue はそこへ接続する
/// 前段——`core` へセッション境界を伝えるための語彙——を用意するところまで）。
///
/// [positions] が空の場合は空リストを返す。
List<List<GeoPosition>> splitByTrackingSession(List<GeoPosition> positions) {
  if (positions.isEmpty) {
    return const [];
  }

  final groups = <List<GeoPosition>>[];
  var current = <GeoPosition>[positions.first];

  for (var i = 1; i < positions.length; i++) {
    final previous = positions[i - 1];
    final position = positions[i];
    if (position.trackingSessionId == previous.trackingSessionId) {
      current.add(position);
    } else {
      groups.add(current);
      current = <GeoPosition>[position];
    }
  }
  groups.add(current);

  return groups;
}
