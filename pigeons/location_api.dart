import 'package:pigeon/pigeon.dart';

// 【実行方法】本ファイルは packages/location を cwd として実行する
// （pigeon が dev_dependency として解決されているのが packages/location/pubspec.yaml
// のため）。出力パスは cwd（packages/location）からの相対パスで指定してある。
//   cd packages/location && dart run pigeon --input ../../pigeons/location_api.dart
@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/position/location_api.g.dart',
  dartOptions: DartOptions(),
  dartPackageName: 'terra_town_location',
  kotlinOut:
      '../../app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/LocationApi.g.kt',
  kotlinOptions: KotlinOptions(package: 'jp.rokusoudo.terra_town.location'),
))

/// 位置記録 platform channel の型定義（Issue #124・T049。Issue #131 で位置データの
/// 受け渡し方法も本ファイルに統合）。
///
/// `specs/001-mvp/plan.md` §1-C の決定 C「機微処理（背景位置・fused location・
/// モック検出・Play Integrity・歩数センサーはOS別実装が本質）」に基づき、
/// Pigeon の channel 契約ファイルを **iOS 移植の正** とする（advisor 評価：
/// 「Pigeon の channel 契約ファイルを iOS 移植の正とし、Dart 側ロジックは共通化する」）。
///
/// ## ⚠️ 位置データを Pigeon で運ぶ（Issue #131・2026-09-11 代表決定。方針転換）
/// 【この節は Issue #124 起票時の当初方針を、Issue #131 の実機不具合を受けて
/// 訂正したものである。以前の記述（取り消し線部分）は経緯として残す】
///
/// ~~本 Pigeon ファイルは位置データ（緯度経度・時刻・精度）を1件も運ばない。
/// `docs/location-track-db.md` §2・§3 が確立した、Dart 側が `location_track.sqlite`
/// を直接読み取り専用で開く経路（`NativePositionProvider`・
/// `packages/location/lib/src/db/location_track_connection.dart`）を使う。~~
///
/// **Issue #131 の実機検証（2026-09-11・Pixel 7a）で、この当初方針が構造的な不具合を
/// 持つことが判明した**: 同じアプリプロセスの中で Kotlin（`android.database.sqlite`）と
/// Dart（`package:sqlite3` + `sqlite3_flutter_libs`）という**2つの別々の SQLite** が
/// 同じ WAL ファイルを開いており、これは SQLite 公式
/// [How To Corrupt An SQLite Database File §2.2.1](https://www.sqlite.org/howtocorrupt.html)
/// が明示的に警告する構成（"Multiple copies of SQLite linked into the same
/// application"）だった。POSIX のファイルロックはプロセス単位のため、同一プロセス内の
/// 別々の SQLite 実装同士は互いのロックを認識できず、WAL の共有メモリ（`-shm`）の
/// 協調が成り立たない。結果として、Kotlin が記録した新しい行が Dart 側に**最大2分以上
/// 届かない**（開く順序によっては起きない場合もあるが、それは「問題が表に出ていないだけ」
/// であり安全な構成ではない）ことが決定的に再現した（詳細:
/// [PR #129 の検証コメント](https://github.com/rokusoudo-product/terra-town/pull/129#issuecomment-5629791422)）。
///
/// **修正方針（採用）**: `location_track.sqlite` を開くのは **Kotlin だけ**にする。
/// Dart はこのファイルを一切開かず、本ファイルの [LocationTrackingHostApi.getLocationPoints]
/// （host API）経由で Kotlin から行を受け取る。ファイルとスキーマの所有者が Kotlin に
/// 一本化され、`plan.md` §1-C 決定Cとも整合する（iOS 移植時は同じ契約を CoreLocation 側の
/// 保存先で実装すればよい）。
///
/// 不採用とした代替案（`docs/location-track-db.md` §2・§3 と同様、詳細は Issue #131 参照）:
/// - **開く順序の調整**（Kotlin を先に開かせる）: 同じ問題を運が良ければ踏まないだけで、
///   構成自体が抱える欠陥は直らない。
/// - **ポーリングごとに Dart の接続を開き直す**: 開くたびに `-shm` の初期化判定が走り、
///   Kotlin 側の WAL インデックスを壊しうる。現状より悪化する。
/// - Dart 側を `sqflite`（Android 標準の SQLite を使うプラグイン）に替える: SQLite の
///   Dart バインディングが2種類（`sqlite3`・`sqflite`）になり、スキーマ知識も二重になる。
/// - サービスを別プロセスにする: `LocationTrackingService.runningSessionId` がプロセス内の
///   静的状態を読んでいるため作り直しが必要で重い。
///
/// ### 当初「64bit整数の丸め」を理由に挙げていた点について（訂正）
/// 位置データを Pigeon で運ばない理由として、以前は「64bit整数の丸め」
/// （`docs/terrain.md` §4.4）を挙げていた。**これは JSON 系の経路（例:
/// `dart:convert` の `jsonEncode`/`jsonDecode` や MethodChannel の JSON コーデック）の
/// 話であり、当たらない。** 本ファイルが使う Pigeon の既定コーデック
/// （`StandardMessageCodec`。バイナリ形式）は、Kotlin の `Long`（64bit）と Dart の
/// `int`（Dart VM 上は64bit）を数値としてそのままバイナリで運ぶため、JSON のように
/// IEEE754 倍精度浮動小数点数（安全な整数範囲は 2^53 まで）を経由しない。
/// [LocationPointMessage.elapsedRealtimeNanos]（実機で `2634654803000000` 程度の値を
/// 確認済み）が Kotlin ⇔ Dart の往復で丸められずに一致することは
/// `native_position_provider_test.dart` でテストする（合成的に 2^53 を超える値、および
/// 生成されたメッセージコーデックでの往復の両方を確認する）。
///
/// 一方で、次の3つは制御・状態であり、これは以前からPigeonで渡している:
/// - サービスの起動・停止（[LocationTrackingHostApi.startTracking]・
///   [LocationTrackingHostApi.stopTracking]）。**2026-09-12（Issue #142・T059）**:
///   製品UI（`app/lib/features/permissions/tracking_control_button.dart`）が
///   release ビルドでも起動できるようになった。以前ここに書かれていた
///   「現状はデバッグ用 Intent（`MainActivity.handleDebugLocationServiceIntent`）
///   でしか起動できない」という制約は Issue #142 で解消済み（当該 Intent ハンドラは
///   同 Issue で削除した）。`kDebugMode` 限定の `LocationTrackingDebugPanel` は
///   実機確認用として引き続き同じ Pigeon API を呼ぶ。
/// - サービスの状態（稼働中か・現在の `session_id`。
///   [LocationTrackingHostApi.getTrackingStatus]）。
/// - 起動しなかった理由（[TrackingStartOutcome.permissionDenied]）。
enum TrackingStartOutcome {
  /// フォアグラウンド位置権限（`ACCESS_FINE_LOCATION`/`ACCESS_COARSE_LOCATION`）が
  /// 確認でき、位置記録 foreground service の起動を要求した
  /// （`Context#startForegroundService()` を呼んだ、という意味。実際に
  /// `startForeground()` まで到達したかはこの結果からは分からない。稼働状態の
  /// 確認は [LocationTrackingHostApi.getTrackingStatus] を使うこと）。
  started,

  /// フォアグラウンド位置権限が無いため、`startForegroundService()` 自体を
  /// **呼ばずに**起動を拒否した。
  ///
  /// **なぜこの区別が安全性に直結するか**: 権限が無い場合に
  /// `Context#startForegroundService()` を呼んでしまうと、システムは一定時間内の
  /// `Service.startForeground()` 呼び出しを義務づけるため、権限チェックを
  /// サービス内部だけに任せると `ForegroundServiceDidNotStartInTimeException` で
  /// アプリのプロセスごと強制終了されうる
  /// （2026-09-11 実機検証・Pixel 7a・PR #128 のレビューコメントで確認済み）。
  ///
  /// この修正（`LocationTrackingService.Companion.start()` 側で権限を確認し、
  /// 権限が無ければ `startForegroundService()` 自体を呼ばず `Boolean` の戻り値で
  /// 呼び出し側に通知する）は **PR #130（2026-09-11 マージ）で main に反映済み**。
  /// 本 Pigeon ハンドラ（`LocationApiHandler.kt`）は `Companion.start()` の戻り値を
  /// そのままこの結果に変換するだけで、自前の権限チェックは行わない。
  permissionDenied,
}

class TrackingStartResult {
  TrackingStartResult({required this.outcome});

  final TrackingStartOutcome outcome;
}

class TrackingStatus {
  TrackingStatus({required this.isRunning, this.sessionId});

  /// 位置記録 foreground service が現在稼働中か
  /// （`startForeground()` まで到達した状態を指す。権限拒否で拒否された場合は false）。
  final bool isRunning;

  /// 稼働中の場合の記録セッションID。
  ///
  /// `location_track.sqlite` の `location_point.session_id` 列、および
  /// `GeoPosition.trackingSessionId`（`packages/core`・本 Issue で追加）と同じ値。
  /// 未稼働時は null。
  final String? sessionId;
}

/// `location_point` の1行分（Issue #131）。
///
/// 列は `docs/location-track-db.md` §4 のスキーマそのまま
/// （`wall_clock_unix_millis`・`inserted_at_unix_millis` は Dart 側の用途が無いため
/// 含めない。理由は削除済みの `location_track_connection.dart` が持っていたのと同じ
/// ——改竄可能な参考情報・デバッグ用途のみの列であり、[GeoPosition] には反映しない）。
class LocationPointMessage {
  LocationPointMessage({
    required this.id,
    required this.sessionId,
    required this.elapsedRealtimeNanos,
    required this.latitude,
    required this.longitude,
    this.accuracyMeters,
    required this.possibleMockLocation,
    required this.hexId,
    this.stepCount,
  });

  /// `location_point.id`（`INTEGER PRIMARY KEY AUTOINCREMENT`）。挿入順に単調増加し、
  /// 値は再利用されない。[LocationTrackingHostApi.getLocationPoints] の `afterId` に
  /// そのまま渡せる。
  final int id;

  /// `location_point.session_id`。[TrackingStatus.sessionId] と同じ値。
  final String sessionId;

  /// `location_point.elapsed_realtime_nanos`（単調時計・ナノ秒）。
  ///
  /// 64bit整数がここでは丸められないことについては、本ファイル冒頭の
  /// 「当初『64bit整数の丸め』を理由に挙げていた点について（訂正）」を参照。
  final int elapsedRealtimeNanos;

  final double latitude;
  final double longitude;

  /// `location_point.accuracy_meters`。値が無い fix は null。
  final double? accuracyMeters;

  /// `location_point.possible_mock_location`（0/1）を bool にしたもの。
  final bool possibleMockLocation;

  /// `location_point.hex_id`（Issue #108）。緯度経度から Kotlin 側（[H3HexIndexer]
  /// 相当・`app/android/app/src/main/kotlin/jp/rokusoudo/terra_town/location/`）が
  /// 記録時点で計算した H3 インデックス（解像度11・`docs/terrain.md` §4.2）。
  ///
  /// ## non-null にした理由（判断に迷った点・PR本文にも記載）
  /// DB列自体（`location_point.hex_id`）は NULL 許容である（Issue #108・
  /// `docs/location-track-db.md` §4「移行手順」。SQLite は既定値なしの列を
  /// `ALTER TABLE` で `NOT NULL` として追加できないため）。しかし
  /// (1) v1→v2 マイグレーションが既存行を全件バックフィルする、
  /// (2) 新規行は [LocationTrackingService.recordPoint] が必ず値を計算して渡す、
  /// という2点により、schema_version 2 に到達した時点で「値が無い行」は実運用上
  /// 存在しない。Dart 側の消費者（[GeoPosition.hexId]・[HexLocator] 実装）にまで
  /// 「null かもしれない」という不確実性を伝播させると、あらゆる呼び出し箇所で
  /// null チェックが必要になり、`plan.md` §2「Dart は読むだけ」という単純さが
  /// 損なわれる。そのため本フィールドは **non-null** とし、万一 Kotlin 側の
  /// `location_point.hex_id` が NULL の行に遭遇した場合（マイグレーション漏れ等の
  /// 実装バグ）は、Kotlin 側（`LocationTrackDatabaseHelper.selectPointsAfter`）が
  /// Dart に渡す前に [IllegalStateException] を投げて気づけるようにしている
  /// （握りつぶして `0` 等の意味のある値に見えるダミー値を渡すことは、
  /// 「開示が静かに壊れる」という本プロジェクトが繰り返し避けてきた失敗様式に
  /// なるため採らない）。
  final int hexId;

  /// `location_point.step_count`（Issue #126・T101・schema v3）。
  ///
  /// この観測時点までの、Android の歩数センサー（`TYPE_STEP_COUNTER`）による
  /// 起動後の累積歩数。**nullable**（[hexId] とは対照的）: 歩数センサーを持たない
  /// 端末・`ACTIVITY_RECOGNITION` 権限が無い端末・まだ最初のセンサーイベントを
  /// 受け取っていない場合は null になる（罰しない側に倒す・Issue #126 本文
  /// 「⚠️ 歩数センサーについて」）。[GeoPosition.cumulativeStepCount]
  /// （`packages/core`）へそのまま写される（`NativePositionProvider` の
  /// ドキュメント参照）。
  final int? stepCount;
}

@HostApi()
abstract class LocationTrackingHostApi {
  /// 位置記録 foreground service の起動を要求する。
  ///
  /// フォアグラウンド位置権限が無い場合は [TrackingStartOutcome.permissionDenied] を
  /// 返し、`startForegroundService()` 自体を呼ばない（[TrackingStartOutcome] の
  /// ドキュメント参照）。
  TrackingStartResult startTracking();

  /// 位置記録 foreground service の停止を要求する。
  void stopTracking();

  /// 現在の稼働状態を問い合わせる。
  TrackingStatus getTrackingStatus();

  /// `location_point` から `id` が [afterId] より大きい行を、`id` 昇順で最大 [limit] 件返す
  /// （Issue #131）。
  ///
  /// - 記録がまだ1件も行われていない（`location_track.sqlite` 自体が存在しない）場合は
  ///   **ファイルを新規作成せず**空リストを返す（「記録0件＝ファイル無し」という既存の
  ///   意味を保つ。Kotlin 側実装は、読み取り用の共有ヘルパー経由で開く前に
  ///   ファイルの存在を確認すること。`SQLiteOpenHelper` 経由で先に開いてしまうと
  ///   `onCreate` が呼ばれて空のファイルが作られてしまう点に注意）。
  /// - 呼び出し側（Dart の `NativePositionProvider`）は、返却件数が [limit] 未満に
  ///   なるまで `afterId` を進めながら本メソッドを繰り返し呼び出し、溜まった行を
  ///   1回のポーリングで取り切る想定（長時間記録が続いた後の初回購読でも、1回の
  ///   メッセージが際限なく巨大にならないようにするため）。
  ///
  /// **`@async` にしてある**: Kotlin 側実装（`LocationApiHandler.kt`）は SQLite の
  /// 読み取りをメインスレッド以外（バックグラウンド Executor）で行う。UI スレッドで
  /// ブロッキング I/O を行わないため。
  @async
  List<LocationPointMessage> getLocationPoints(int afterId, int limit);
}
