// 使用中のプラグイン版数を画面上部に常時表示するためのバナー。
//
// 【重要】pubspec.yaml の maplibre_gl のバージョン指定を変更したときは、
// 必ずこの定数も手で書き換えること（README「バージョン」節参照）。
// pubspec.lock を実行時に読んで自動判定する実装はしていない
// （使い捨てハーネスでそこまでのコストをかける必要はないと判断）。
const String kPluginLabel = 'maplibre_gl';

/// pubspec.yaml の現在の状態と必ず一致させること。
///
/// 【2026-09-09 変更】release-0.27.0 への git 依存（2026-08-13 時点の暫定対応）を
/// 撤去し、2026-08-19 に pub.dev へ公開された正式版 `^0.27.0` に揃えた
/// （main の packages/location/pubspec.yaml と同じ判断・Issue #55）。
const String kPluginVersionLabel = 'maplibre_gl 0.27.0 (pub.dev)';

/// 代表がこの版で research.md に記録する際の注意書き。
const String kPluginVersionNote =
    'feature-state の Android 対応（上流#889）と Issue #366 のエンコードオフロードは'
    '両方 0.27.0 に収録済み（research.md §6.0）。git依存だった頃の'
    '「安定版/git mainの両方を回す」手順は不要になった。';
