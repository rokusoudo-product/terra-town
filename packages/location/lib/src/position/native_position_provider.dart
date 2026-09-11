import 'dart:async';

import 'package:flutter/services.dart' show PlatformException;
import 'package:terra_town_core/terra_town_core.dart';

import 'location_api.g.dart';

/// [NativePositionProvider] が読み取りに使う最小限のインターフェース（Issue #131）。
///
/// ## なぜ生成された [LocationTrackingHostApi] を直接使わないか
/// [LocationTrackingHostApi] は Pigeon が生成する**具象クラス**（抽象クラスではない）で
/// あり、実際の platform channel 経由の呼び出しを行う実装を持つ。テストでフェイクに
/// 差し替えるにはサブクラス化してメソッドをオーバーライドするより、薄いインターフェースを
/// 1枚挟んで実装ごと差し替える方が単純で意図も明確なため、本インターフェースを用意した
/// （`native_position_provider_test.dart` のフェイク実装参照）。
///
/// GPS_ARCHITECTURE 上の位置づけ: 本インターフェース・[LocationTrackingHostApi] は
/// いずれも `packages/location` に閉じており、`core` に Pigeon を持ち込むわけではない。
abstract class LocationPointsApi {
  /// `location_point` から `id` が [afterId] より大きい行を `id` 昇順で最大 [limit] 件返す。
  ///
  /// 記録がまだ1件も無い場合は空リストを返す（Kotlin 側実装のドキュメント参照）。
  Future<List<LocationPointMessage>> getLocationPoints(int afterId, int limit);
}

/// [LocationPointsApi] の既定実装。Pigeon が生成した [LocationTrackingHostApi] へ
/// そのまま委譲するだけの薄いラッパー。
class _PigeonLocationPointsApi implements LocationPointsApi {
  _PigeonLocationPointsApi([LocationTrackingHostApi? api])
      : _api = api ?? LocationTrackingHostApi();

  final LocationTrackingHostApi _api;

  @override
  Future<List<LocationPointMessage>> getLocationPoints(int afterId, int limit) =>
      _api.getLocationPoints(afterId, limit);
}

/// [PositionProvider] の実機実装（Issue #124・T050。Issue #131 で読み取り経路を
/// ファイル直接読み取りから Pigeon 経由に変更）。
///
/// Kotlin 側 foreground service（Issue #123・PR #128・`LocationTrackingService`）が
/// `location_track.sqlite` に書き込む行を、Pigeon の host API
/// （[LocationPointsApi.getLocationPoints]・Kotlin 側実装は `LocationApiHandler.kt`）
/// 経由で取得し、[GeoPosition] に変換して [positionUpdates] から流す。
///
/// ## ⚠️ なぜファイルを直接読まなくなったか（Issue #131・2026-09-11 代表決定。方針転換）
/// 当初（Issue #124）は本クラスが `package:sqlite3` で `location_track.sqlite` を
/// 直接読み取り専用で開いていた（削除済みの `LocationTrackConnection` 参照）。
/// **しかし実機検証（PR #129・Pixel 7a）で、同じアプリプロセス内に Kotlin
/// （`android.database.sqlite`）と Dart（`package:sqlite3`）という2つの別々の
/// SQLite が同じ WAL ファイルを扱う構成になっており、これが SQLite 公式
/// [How To Corrupt An SQLite Database File §2.2.1](https://www.sqlite.org/howtocorrupt.html)
/// が警告する構成に該当し、Kotlin が記録した新しい行が Dart 側に**最大2分以上**
/// 届かない不具合を起こすことが判明した**（詳細:
/// [PR #129 の検証コメント](https://github.com/rokusoudo-product/terra-town/pull/129#issuecomment-5629791422)）。
///
/// 修正方針: **`location_track.sqlite` を開くのは Kotlin だけにする。** Dart は
/// このファイルを一切開かず、Pigeon 経由で行を受け取る（`pigeons/location_api.dart`
/// のドキュメント参照）。「開く順序の調整」「ポーリングごとに接続を開き直す」は
/// どちらも問題を残すため不採用（同ファイル参照）。
///
/// ## ポーリング方式を採る理由
/// Kotlin 側は Dart に新規行の到着を能動的に通知しない（EventChannel等は使わない。
/// 効率のため）。そのため本実装は [pollInterval] ごとに [LocationPointsApi.getLocationPoints]
/// を呼び、[sinceRowId] より大きい `id` の行を取得する。
///
/// ## 1回のポーリングで溜まった行を取り切る（[pageSize]）
/// 長時間の記録の後に初めて購読すると大量の行が溜まっている場合がある。1回の
/// Pigeon 呼び出しで際限なく巨大なメッセージを送らないよう、[pageSize] 件ずつ取得し、
/// 返却件数が [pageSize] 未満になるまで `afterId` を進めながら繰り返し呼び出す。
///
/// ## 重複防止（前回のポーリングが終わる前に次のポーリングが走らないようにする）
/// [LocationPointsApi.getLocationPoints] は非同期（`@async`・Kotlin 側はメインスレッド以外で
/// SQLite を読む）であるため、[pollInterval] より処理に時間がかかると
/// `Timer.periodic` の次のコールバックが前回の完了前に発火しうる。[_isPolling] で
/// 多重実行を防ぎ、同じ行が二重に [positionUpdates] へ流れないようにする。
///
/// ## 履歴の扱い（[sinceRowId] の既定値は 0＝全件）
/// 実運用の典型的な流れは「adb 等でサービスを先に起動 → 歩く → その後アプリを開く」
/// でありうるため、購読開始時点の最大 `id` から始める（＝以後の新規分だけ流す）
/// 設計は、購読前に記録された分を静かに読み飛ばしてしまう。**開示判定
/// （[DisclosureService]）は同じヘクスを何度処理しても副作用が無い（冪等）ため、
/// 全件を毎回流しても安全側に倒れる**（[SpeedFilter] はまだ本番配線されていないため
/// 実害もない）。そのため既定は「記録開始（`id > 0`）から全件」とした。
/// 「前回読み終えた `id` を永続化して次回はそこから」という最適化は Issue #124 の
/// スコープ外（Issue #131 のスコープ外でもある）。
///
/// ## GeoPosition への変換方針
/// - [GeoPosition.timestamp]: `elapsedRealtimeNanos`（単調時計・ナノ秒）を
///   [DateTime.fromMicrosecondsSinceEpoch] でマイクロ秒に丸めて変換する（isUtc: true。
///   壁時計は使わない。理由は [GeoPosition.timestamp] のドキュメント参照）。ナノ秒→
///   マイクロ秒の切り捨てにより1マイクロ秒未満の分解能は失われるが、GPS/fused location
///   の実用上の分解能（ミリ秒オーダー）を大きく下回るため実害はない。
/// - [GeoPosition.trackingSessionId]: `sessionId` をそのまま渡す。
/// - [GeoPosition.spoofSuspected]: `possibleMockLocation` を bool に変換するだけ。
///   判定ロジック自体は実装しない（Issue #126）。
/// - [GeoPosition.hexId]（Issue #108）: `LocationPointMessage.hexId`（Kotlin側
///   `H3HexIndexer` が記録時点で確定した H3 インデックス）を [HexId] でラップするだけ。
///   本クラスは変換ロジックを一切持たない（`RecordedHexLocator` のドキュメント参照）。
///
/// ## 64bit整数について
/// `elapsedRealtimeNanos` は実機で `2634654803000000` 程度の値になることを確認済み
/// （`docs/location-track-db.md` §8.3）。Pigeon の既定コーデック（`StandardMessageCodec`。
/// バイナリ形式）は Kotlin の `Long`（64bit）と Dart の `int`（VM上は64bit）を
/// そのまま運ぶため、`docs/terrain.md` §4.4 が警告する JSON 経路での 2^53 丸めは
/// 発生しない（`native_position_provider_test.dart` で検証。合成的に 2^53 を超える値、
/// および生成されたメッセージコーデックでの往復の両方を確認する）。
class NativePositionProvider implements PositionProvider {
  NativePositionProvider({
    LocationPointsApi? api,
    this.pollInterval = const Duration(seconds: 5),
    this.sinceRowId = 0,
    this.pageSize = 500,
  }) : _api = api ?? _PigeonLocationPointsApi();

  /// 位置データの取得先。既定は実際の Pigeon 経路（[_PigeonLocationPointsApi]）。
  /// テストではフェイク実装を注入する。
  final LocationPointsApi _api;

  /// 新規行の有無を確認する間隔。
  final Duration pollInterval;

  /// この `id` より大きい行だけを新規として流す。クラスdoc「履歴の扱い」参照。
  final int sinceRowId;

  /// 1回の [LocationPointsApi.getLocationPoints] 呼び出しで取得する最大件数。
  /// クラスdoc「1回のポーリングで溜まった行を取り切る」参照。
  final int pageSize;

  int _lastSeenId = 0;
  bool _isPolling = false;
  Timer? _timer;
  StreamController<GeoPosition>? _controller;

  @override
  Stream<GeoPosition> get positionUpdates {
    final controller = _controller ??= StreamController<GeoPosition>.broadcast(
      onListen: _start,
      onCancel: _stop,
    );
    return controller.stream;
  }

  void _start() {
    _lastSeenId = sinceRowId;
    unawaited(_poll());
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    final controller = _controller;
    if (controller == null || controller.isClosed) {
      return;
    }
    if (_isPolling) {
      // 前回のポーリングがまだ完了していない。多重実行による行の重複配信を避けるため
      // 今回はスキップする（クラスdoc「重複防止」参照）。
      return;
    }
    _isPolling = true;
    try {
      // 溜まった行を1回のポーリングで取り切るまで繰り返す（クラスdoc参照）。
      while (true) {
        final rows = await _api.getLocationPoints(_lastSeenId, pageSize);
        if (controller.isClosed) return;
        for (final row in rows) {
          _lastSeenId = row.id;
          controller.add(_toGeoPosition(row));
        }
        if (rows.length < pageSize) break;
      }
    } on PlatformException catch (error) {
      // Pigeon 呼び出し自体の失敗（Kotlin 側の予期しない例外等）。
      // ストリーム自体は壊さず、次回ポーリングで再試行する。
      // ignore: avoid_print
      print(
        'NativePositionProvider: 位置データの取得に失敗したため '
        '次回ポーリングで再試行します: $error',
      );
    } finally {
      _isPolling = false;
    }
  }

  static GeoPosition _toGeoPosition(LocationPointMessage row) {
    final accuracyMeters = row.accuracyMeters;
    return GeoPosition(
      latitude: row.latitude,
      longitude: row.longitude,
      // 単調時計（elapsedRealtime）をそのままマイクロ秒へ変換する。壁時計は使わない
      // （クラスdoc「GeoPosition への変換方針」参照）。
      timestamp: DateTime.fromMicrosecondsSinceEpoch(
        row.elapsedRealtimeNanos ~/ 1000,
        isUtc: true,
      ),
      accuracy: accuracyMeters == null ? null : Distance.meters(accuracyMeters),
      spoofSuspected: row.possibleMockLocation,
      trackingSessionId: row.sessionId,
      // Issue #108: row.hexId は Pigeon の LocationPointMessage.hexId（non-null）を
      // そのまま HexId でラップするだけ。Kotlin 側（H3HexIndexer）が記録時点で
      // 既に確定済みの値であり、ここでは変換を一切行わない。
      hexId: HexId(row.hexId),
    );
  }

  /// 使用済みのリソース（ポーリングタイマー・StreamController）を解放する。
  Future<void> close() async {
    _stop();
    await _controller?.close();
    _controller = null;
  }
}
