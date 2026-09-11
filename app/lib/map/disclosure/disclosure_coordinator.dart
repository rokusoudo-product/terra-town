import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart' show hexIdToFeatureId;

/// 位置 → 開示判定 → 保存 → 霧の解除の配線（composition root・Issue #137）。
///
/// `DisclosureService.disclose`（`core`・T054・Issue #101）に位置情報の列
/// （実運用では `NativePositionProvider.positionUpdates`）を流し、新規開示ごとに
/// [reveal] を呼んで霧を解除するところまでを1か所にまとめる。
///
/// ## `FogOfWarController` を直接持たない理由（テスト容易性）
/// `FogOfWarController` はコンストラクタが private で、実際の `MapLibreMapController`
/// （地図SDKの実プラットフォームビュー）を要求するため、`flutter test` 環境では
/// フェイクを注入できない。本クラスは「featureId を受け取り霧を解除する」という
/// 効果だけを [reveal]（関数型）として受け取ることで、widget テストなしに
/// ロジック（開示判定→保存→revealの呼び出し）を検証できるようにする。
///
/// ## `setStyle` によるコントローラの差し替えへの対応（Issue #102）
/// [reveal] を「呼び出し側が現在の `FogOfWarController` を読んで呼ぶクロージャ」として
/// 渡すことで、`MapView.onFogLayerReady` が（将来 `setStyle` 経由で）再度発火し
/// 新しい `FogOfWarController` に差し替わっても、本クラス自体は何も変更せずに
/// 最新のコントローラを使い続けられる（呼び出し側 `map_screen.dart` 参照）。
/// 一方、位置ストリームの購読（[start]）は「一度開始したら継続する」ものであり、
/// コントローラの差し替えのたびに再購読してはならない（[start] は2回目以降
/// 何もしない）。
///
/// ## 呼び出し順序が重要（advisor 指摘・Issue #102）
/// [start] は、[known]（[DisclosedHexSet]）に永続化済みの開示済みヘクスが
/// **すべて読み込まれた後**に呼ぶこと（`disclosure_restore.dart`
/// `restoreDisclosedHexes` 参照）。順序を誤ると、まだ [known] に登録されていない
/// 既知のヘクスへ実機の移動で再度到達した際、[DisclosureService.recordPosition] が
/// 「新規開示」と誤認しうる（`DisclosedHexRepository.save` は `insertOrIgnore` の
/// ため実際の上書きは起きないが、無駄な処理・[known] への遅延登録は避けるべき）。
///
/// ## [positionUpdates] の最初の購読者は本クラスでなければならない（advisor 指摘）
/// `NativePositionProvider.positionUpdates` は broadcast `StreamController` であり、
/// `onListen`（購読開始時点の履歴の全件再生。`native_position_provider.dart`
/// クラスdoc「履歴の扱い」参照）は 0→1件目の購読者にのみ発火し、broadcast
/// Stream は過去に流したイベントを後から購読した相手に再送しない。そのため、
/// もし [start] より先に**別の購読者**（例: デバッグパネルが独自に
/// `positionUpdates` を購読する等）が現れると、履歴の再生はその購読者だけに
/// 届き、本クラスは「購読を開始した以降に新しく届いた行」しか処理できなくなる
/// （＝アプリを開く前に歩いた分の開示が一切行われない）。呼び出し側
/// （`map_screen.dart`）は同じ `NativePositionProvider` インスタンスを
/// デバッグパネルと共有してはならない。
class DisclosureCoordinator {
  DisclosureCoordinator({
    required this.service,
    required this.positionUpdates,
    required this.reveal,
  });

  final DisclosureService service;
  final Stream<GeoPosition> positionUpdates;

  /// 新規開示（featureId）ごとに呼ばれる、霧を解除する効果。
  final Future<void> Function(int featureId) reveal;

  StreamSubscription<DisclosedHex>? _subscription;

  /// 位置ストリームの購読を開始する。**[known] の復元が完了した後に呼ぶこと**
  /// （クラスdoc「呼び出し順序」参照）。2回目以降の呼び出しは何もしない
  /// （`setStyle` 等で呼び出し側が再度呼んでも購読は1つのまま保たれる）。
  void start() {
    if (_subscription != null) return;
    _subscription = service.disclose(positionUpdates).listen(
      _onDisclosed,
      onError: (Object error, StackTrace stackTrace) {
        _log('位置ストリームの処理中にエラーが発生し、購読が終了しました: $error');
        developer.log(
          'DisclosureCoordinator: 位置ストリームの処理中にエラーが発生しました'
          '（以後、位置の更新は開示判定に反映されません）',
          name: 'terra_town.disclosure_coordinator',
          error: error,
          stackTrace: stackTrace,
          level: 1000,
        );
      },
    );
  }

  /// 購読を止める（画面破棄時に呼ぶ）。
  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }

  /// デバッグパネル（「地図の中心のヘクスを開示」・`kDebugMode` 限定）から、
  /// **本番と同じ経路**（[DisclosureService.recordPosition] → 新規開示なら
  /// [reveal]）を通すための窓口。
  ///
  /// [positionUpdates] を経由しない直接呼び出しのため [start] の有無に関わらず
  /// 動作する（実機の現在地が地域パック範囲外でも、この経路単体で開示・保存・
  /// 霧の解除を確認できるようにするための Issue #137 の要件）。
  Future<DisclosedHex?> recordManualPosition(GeoPosition position) async {
    final disclosed = await service.recordPosition(position);
    if (disclosed != null) {
      await reveal(hexIdToFeatureId(disclosed.hexId.value));
    }
    return disclosed;
  }

  void _onDisclosed(DisclosedHex disclosed) {
    final featureId = hexIdToFeatureId(disclosed.hexId.value);
    // 位置ストリームの逐次処理（`DisclosureService.disclose` の `await for`）を
    // 霧の解除（platform channel 往復）で止めないよう、あえて await しない。
    // 失敗してもストリーム自体は継続させ、ログにのみ残す。
    unawaited(
      reveal(featureId).catchError((Object error, StackTrace stackTrace) {
        _log('霧の解除に失敗しました（featureId=$featureId）: $error');
        developer.log(
          'DisclosureCoordinator: revealに失敗しました',
          name: 'terra_town.disclosure_coordinator',
          error: error,
          stackTrace: stackTrace,
          level: 1000,
        );
      }),
    );
  }

  void _log(String message) {
    developer.log(message, name: 'terra_town.disclosure_coordinator');
    debugPrint('[terra_town.disclosure_coordinator] $message');
  }
}
