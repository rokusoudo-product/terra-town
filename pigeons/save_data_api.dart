import 'package:pigeon/pigeon.dart';

// 【実行方法】本ファイルは packages/location を cwd として実行する
// （pigeon が dev_dependency として解決されているのが packages/location/pubspec.yaml
// のため。`pigeons/location_api.dart` と同じ実行方法）。
//   cd packages/location && dart run pigeon --input ../../pigeons/save_data_api.dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/save_data/save_data_api.g.dart',
  dartOptions: DartOptions(),
  dartPackageName: 'terra_town_location',
  kotlinOut:
      '../../app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/savedata/SaveDataApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'jp.rokusoudo.terra_town.savedata'),
))

/// セーブデータのエクスポート/インポート（Issue #180・T105）で、Android の
/// ストレージ・アクセス・フレームワーク（SAF）経由のファイル保存/読み込みを行う
/// platform channel の型定義。
///
/// ## なぜ `pigeons/location_api.dart` と同じ Pigeon の仕組みを使うか（採用方式・PR本文にも記載）
/// Issue #180 決定事項6は、ファイル受け渡しの実現方法として次の二択を示している。
/// - (a) `app` 層のプラグイン（`file_selector`・`share_plus`・`file_picker` 等）
/// - (b) Pigeon → Kotlin の `ACTION_CREATE_DOCUMENT`／`ACTION_OPEN_DOCUMENT`
///
/// **本ファイルは (b) を採用する。** 理由（advisor相談・2026-09-14）:
/// 1. **新しい Gradle プラグインを追加しない。** `packages/location/pubspec.yaml` の
///    `maplibre_gl` に関する記録（Issue #67）が示すとおり、このリポジトリでは
///    Flutter プラグインの追加が Kotlin ツールチェーンの相互排他で実際にビルドを
///    壊した前例がある。`file_selector` 等の新規プラグインを追加するリスクを
///    冒すより、既存の Pigeon（`LocationTrackingHostApi`）と同じ仕組みを拡張する
///    方が安全である。
/// 2. **`file_selector` の Android 実装は保存（`getSaveLocation`）に対応していない**
///    （2026-09時点のパッケージ実装）。Issue の決定事項6が「file_selector の保存
///    **or** share_plus」と二択で書いているのはこのためであり、保存・読み込みの
///    両方を一貫した1つの仕組みで実装するには、いずれにせよ Kotlin 側の
///    `ACTION_CREATE_DOCUMENT` 実装が必要になる。
/// 3. Dart は `content://` URI のバイト列を直接読み書きできないため、
///    いずれの案でも最終的には Kotlin（`ContentResolver`）側での I/O が必要になる。
///
/// ## `Activity` を保持する理由（`LocationApiHandler` との違い）
/// `LocationApiHandler` は `Context`（`applicationContext`）だけで完結するが、
/// 本ハンドラ（`SaveDataApiHandler.kt`）は `startActivityForResult`/
/// `onActivityResult` という **Activity のライフサイクルに紐づく API** を使うため、
/// `Activity`（`MainActivity` 自身）を保持する。`FlutterActivity` は
/// `android.app.Activity` を継承しているため、`FlutterFragmentActivity` へ切り替え
/// なくてもこの古典的な API がそのまま使える。
///
/// ## `@async` の意味（`LocationApiHandler` とは異なる非同期の理由）
/// [getLocationPoints] 等の `@async` はブロッキング I/O をメインスレッド外で
/// 行うためだが、本ファイルの `@async` は **ユーザーがピッカーを操作し終えるまで
/// Dart 側の呼び出しを待たせる**ため（`onActivityResult` が呼ばれるまで
/// `suspendCancellableCoroutine` で一時停止する）。
@HostApi()
abstract class SaveDataFileHostApi {
  /// SAF の `ACTION_CREATE_DOCUMENT` でユーザーに保存先を選ばせ、[contents] を
  /// UTF-8 で書き込む。
  ///
  /// [suggestedFileName] は既定のファイル名（例:
  /// `terra-town-save-20260914-1200.json`）。ユーザーがピッカーをキャンセルした
  /// 場合は書き込みを行わず `false` を返す。書き込み自体が失敗した場合（I/O
  /// 例外）は例外を投げる。
  @async
  bool saveTextFile(String suggestedFileName, String contents);

  /// SAF の `ACTION_OPEN_DOCUMENT` でユーザーにファイルを選ばせ、内容を UTF-8
  /// として読み込む。
  ///
  /// MIME タイプでの絞り込みは行わない（ファイルマネージャーによって `.json` の
  /// MIME タイプの報告が `application/json`／`application/octet-stream`／`text/plain`
  /// など揺れるため、OS 側のフィルタに頼らず内容自体をアプリ側で検証する方針
  /// ——`packages/location/lib/src/save_data/` の JSON 検証ロジック参照）。
  /// ユーザーがピッカーをキャンセルした場合は `null` を返す。読み込み自体が
  /// 失敗した場合（I/O 例外・UTF-8 として解釈できない）は例外を投げる。
  @async
  String? openTextFile();
}
