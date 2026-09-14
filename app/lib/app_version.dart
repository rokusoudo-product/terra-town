/// アプリのバージョン文字列（Issue #180・T105）。
///
/// セーブデータのエクスポート（`save_data_transfer_service.dart`）のメタデータ
/// `app_version` にのみ使う参考情報（読み込み時の検証には使わない・
/// `schema_version` とは無関係）。
///
/// ## `package_info_plus` を追加しない理由
/// 新しい Gradle プラグインを追加するリスクを避ける方針
/// （`pigeons/save_data_api.dart` のドキュメント「なぜ `pigeons/location_api.dart`
/// と同じ Pigeon の仕組みを使うか」と同じ判断）のため、`pubspec.yaml` の
/// `version:` をこの定数へ**手で**転記する。乖離は `test/app_version_test.dart`
/// が `pubspec.yaml` を読んで機械的に検出する（このリポジトリの「規約ではなく
/// 仕組みで守る」文化・`tools/check_*.sh` と同じ方針）。
///
/// `pubspec.yaml` の `version:` を変更したら、必ず本定数も同じ値に更新すること。
const String kAppVersion = '1.0.0+1';
