// 使用中のプラグイン版数を画面上部に常時表示するためのバナー。
//
// 【重要】pubspec.yaml の依存を pub.dev安定版 <-> git main で切り替えたときは、
// 必ずこの定数も手で書き換えること（README「バージョン切り替え」参照）。
const String kPluginLabel = 'maplibre (josxha/flutter-maplibre)';

/// pubspec.yaml の現在の状態と必ず一致させること。
/// - pub.dev 安定版を使っている場合: 'maplibre 0.3.5 (pub.dev stable)'
/// - git 依存で main を参照している場合: 'maplibre main@`<commit>` (git, unreleased)'
const String kPluginVersionLabel = 'maplibre 0.3.5 (pub.dev stable)';

const String kPluginVersionNote =
    'このアプリは性能計測UIを持たない最小プローブ（research.md §3.2でfeature-stateの実装根拠が'
    '見つからなかったため）。MBTiles参照ボタンは構文が特定できなかったため無効化している。README参照。';
