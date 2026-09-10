/// ローカル MBTiles ファイルパスから MapLibre の `mbtiles://` ソース URI を組み立てる。
///
/// 【`url:`（[VectorSourceProperties.url] 相当）を採用する理由・research.md §6.2】
/// 実機検証（Issue #24・2026-09-09）では `VectorSourceProperties` の `url:`
/// （単一文字列）と `tiles:`（配列）のいずれも `addSource`/`addLayer` が例外なく
/// 成功した。ただしこの検証はソース/レイヤーをリセットせずに url→tiles の順で
/// 重ね書きしたため、実機で最終的に確認された描画がどちらの方式の寄与かは
/// 厳密には分離できていない（§6.2「精度の限界」）。
///
/// それでも tiles 方式のボタンを押す前（url 方式を追加した直後）に撮られた
/// スクリーンショットで既に描画が確認できているため、**url 方式単独で成立している
/// と読める（強い傍証）**。加えて `url:` は「1つの MBTiles ソースを参照する」という
/// 意味的にも自然で、TileJSON 由来の複数タイル URL 配列を想定した `tiles:` より
/// API 表面が単純なため、本実装（tasks.md T055）ではこちらを採用する。
///
/// 参照: `spikes/map_spike_gl/lib/map_probe_page.dart`（`final uri = 'mbtiles://$destPath'`）
/// と同じ構文。
String mbtilesSourceUrl(String localMbtilesFilePath) =>
    'mbtiles://$localMbtilesFilePath';
