import 'package:terra_town_location/terra_town_location.dart';

/// バーティカルスライス対象エリア（狭山湖周辺）の初期カメラ位置。
///
/// 【値の根拠・推測していない】`app/assets/pack/tiles.mbtiles` の metadata テーブル
/// 実測値（2026-09-10・`tools/pack-builder/README.md`「実測（狭山湖周辺エリア）」）:
///   - center = 139.41317, 35.82581（パック推奨ズーム 11）
///   - bounds = 139.2957, 35.7043, 139.53065, 35.94732
///   - パックのズーム範囲 = 0〜14
///
/// 【ズーム14を採用する理由】`building` レイヤーは minzoom 13 のため、パック
/// 推奨ズーム（11）のままでは起動直後に建物が1つも見えない。本Issueの主目的が
/// 「実際の地域パック（Planetiler生成・高ズーム）でのMBTiles読込の確認」
/// （plan.md §8「未計測」の解消）であるため、パックの maxzoom である 14 を採用し、
/// 高ズームでのレイヤーが実際に描画されることを代表が確認できるようにする。
///
/// 【tilt（傾き）を付ける理由】DESIGN.md「アートディレクション」の技術的含意(1)
/// 「カメラの pitch（傾き）を付けた俯瞰 — ほぼ無料でミニチュア感が出る。最優先」に
/// 対応する。角度45度は「ミニチュア感が出る」という目的を満たす範囲での実装判断の
/// 値であり、DESIGN.md に数値トークンとして定義されたものではない
/// （スプライトレイヤー等その他の演出は本Issueのスコープ外）。
MapCameraPosition sayamakoInitialCameraPosition() => const MapCameraPosition(
  latitude: 35.82581,
  longitude: 139.41317,
  zoom: 14,
  tilt: 45,
);
