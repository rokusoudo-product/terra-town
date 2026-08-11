// 使用中のプラグイン版数を画面上部に常時表示するためのバナー。
//
// 【重要】pubspec.yaml の依存を pub.dev安定版 <-> git main で切り替えたときは、
// 必ずこの定数も手で書き換えること（README「バージョン切り替え」参照）。
// pubspec.lock を実行時に読んで自動判定する実装はしていない
// （使い捨てハーネスでそこまでのコストをかける必要はないと判断）。
const String kPluginLabel = 'maplibre_gl';

/// pubspec.yaml の現在の状態と必ず一致させること。
/// - pub.dev 安定版を使っている場合: 'maplibre_gl 0.26.2 (pub.dev stable)'
/// - git 依存で main を参照している場合: 'maplibre_gl main@`<commit>` (git, unreleased)'
const String kPluginVersionLabel = 'maplibre_gl 0.26.2 (pub.dev stable)';

/// 代表がこの版で research.md に記録する際の注意書き。
const String kPluginVersionNote =
    '安定版=「今日出荷できるか」 / git main=「0.27.0(feature-state Android対応・#366性能改善)で直るか」。'
    '両方回すことを推奨（README参照）。';
