import 'package:terra_town_location/terra_town_location.dart';

/// バーティカルスライス対象エリア（狭山湖周辺）の初期カメラ位置。
///
/// 【値の根拠】`tools/pack-builder` が出力する `pack.json` の bbox
/// （2026-09-10 実測・`pack_version = sayamako-v1-9a66e066b0d4`）:
///   - lon 139.352 〜 139.408 / lat 35.7675 〜 35.8125
///   - その中心 = 35.79000, 139.38000
///
/// 【`tiles.mbtiles` の metadata `center` を使わない理由（2026-09-10 実機で判明）】
/// Planetiler が書く metadata の `bounds` / `center`
/// （bounds = 139.2957,35.7043,139.53065,35.94732 / center = 139.41317,35.82581）は
/// **タイル境界にパディングされた範囲**であり、OSM 抽出データが実際に入っている範囲ではない。
/// この center（35.82581, 139.41317）は抽出 bbox の**北東側の外**にあたるため、
/// 初期表示が「タイルは存在するが中身が空」となり、画面のほぼ全面が空白になった。
/// 実機（Pixel 7a）で再現・修正を確認済み。**抽出 bbox の中心を使うこと。**
///
/// 【ズーム14を採用する理由】`building` レイヤーは minzoom 13 のため、パック推奨ズーム
/// （11）のままでは起動直後に建物が1つも見えない。パックの maxzoom である 14 を採用し、
/// 高ズームでのレイヤーが実際に描画されることを確認できるようにする。
///
/// 【tilt（傾き）を付ける理由】DESIGN.md「アートディレクション」の技術的含意(1)
/// 「カメラの pitch（傾き）を付けた俯瞰 — ほぼ無料でミニチュア感が出る。最優先」に
/// 対応する。角度45度は「ミニチュア感が出る」という目的を満たす範囲での実装判断の
/// 値であり、DESIGN.md に数値トークンとして定義されたものではない
/// （スプライトレイヤー等その他の演出は本Issueのスコープ外）。
MapCameraPosition sayamakoInitialCameraPosition() => const MapCameraPosition(
  latitude: 35.79000,
  longitude: 139.38000,
  zoom: 14,
  tilt: 45,
);
