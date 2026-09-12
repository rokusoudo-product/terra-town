import 'package:flutter/foundation.dart' show immutable;
import 'package:terra_town_core/terra_town_core.dart';

/// 現在地マーカー（点）の見た目の設定値（Issue #141・T058）。
///
/// 【Issue #57 の注入方式を踏襲】`location` は配色を知らない。色は composition
/// root（`app`）が DESIGN.md のトークンから導出し、`#RRGGBB` 形式の16進文字列と
/// して注入する（`app/lib/map/current_location_marker_factory.dart`・
/// `fog_of_war_layer.dart` の `FogOfWarLayer` と同じ役割分担）。
///
/// 【精度円（[GeoPosition.accuracy]）を表示しない理由（Issue #141 提案4）】
/// 本 Issue は「精度を円などで表現するかは実装者判断でよいが、やらない場合は
/// その旨をコードコメントに残す」としている。本実装は精度円を**実装しない**。
/// 理由: (1) まず「自分がどこにいるか」を確実に見せることを優先し、地図上の
/// レイヤー（地域パック・fog・現在地）をこれ以上増やさない（DESIGN.md「MVP の
/// フィデリティ」の「作り込みではなく方向性の担保を優先する」方針と同じ考え方）。
/// (2) 精度円は緯度経度の半径をズームに応じてピクセル半径へ変換する必要があり、
/// `circle-radius` のズーム式（あるいはメートル単位に対応する `circle-pitch-scale`
/// 等の組み合わせ）の検証が別途必要になる。将来必要になれば、本ファイルに
/// 精度円用の2つ目の Feature（`Polygon`/円近似）を追加する形で拡張できる
/// （[buildCurrentLocationFeatureCollection] のドキュメント参照）。
@immutable
class CurrentLocationMarkerStyle {
  const CurrentLocationMarkerStyle({
    required this.fillColorHex,
    required this.strokeColorHex,
    this.radius = 8.0,
    this.strokeWidth = 3.0,
  });

  /// `#RRGGBB` 形式の16進文字列。値の正しさは呼び出し側（`app`）の責務。
  final String fillColorHex;

  /// マーカーの縁取り色（`#RRGGBB`）。地図（地域パック・fog）の上でも塗り色を
  /// 視認しやすくするための白系の縁取りを想定するが、値自体は呼び出し側が
  /// 決める。
  final String strokeColorHex;

  /// マーカー本体の半径（地図ピクセル）。DESIGN.md にサイズトークンが無いため
  /// （「サイズ・余白は grep での機械判定が難しいため対象外」・
  /// `tools/check_design_tokens.sh` 冒頭コメント）実装判断の値とする。
  final double radius;

  /// 縁取りの太さ（地図ピクセル）。
  final double strokeWidth;
}

/// 現在地の点を表す GeoJSON FeatureCollection を組み立てる純粋関数（T058）。
///
/// [position] が null の場合（位置がまだ1件も届いていない場合）は
/// `features` が空の FeatureCollection を返す。fill レイヤーは features が
/// 0件であれば何も描画しないため、「マーカーを出さない」状態はこの空の
/// FeatureCollection をソースへ設定するだけで表現できる（Issue #141 提案3
/// 「位置が未取得の場合の表示」の決定: マーカーを出さない）。
///
/// 【「記録サービスが停止している場合」の表示についての決定（Issue #141 提案3）】
/// 本実装は「記録サービスが停止中」を独立した状態として扱わない。停止中は
/// 単に新しい位置（[GeoPosition]）が届かなくなるだけであり、[position] に
/// 渡す値の出どころ（`TerrainYieldPipeline.currentPosition`）は最後に処理した
/// 位置を保持し続ける。そのためマーカーは**最後に届いた位置に留まる**
/// （多くの地図アプリの「現在地」表示と同じ挙動）。
/// まとめると: 未取得 = マーカーなし（本関数が空の FeatureCollection を返す）／
/// 停止中（=新規の位置が届かないだけ） = 最後の位置に留める、の2択で決定済み。
Map<String, dynamic> buildCurrentLocationFeatureCollection(GeoPosition? position) {
  if (position == null) {
    return const {'type': 'FeatureCollection', 'features': <Map<String, dynamic>>[]};
  }
  return {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [position.longitude, position.latitude],
        },
        'properties': const <String, dynamic>{},
      },
    ],
  };
}

/// 追従カメラのオン/オフを、利用者操作によるカメラ移動と区別するための
/// 小さな状態機械（Issue #141 提案2）。
///
/// ## なぜ必要か
/// `maplibre_gl` の `MapLibreMapController.animateCamera`/`moveCamera` が返す
/// [Future] は「移動を開始した」時点で完了し、「移動が収まった」時点
/// （＝`onCameraIdle`）では完了しない（`animateCamera`のドキュメント
/// 「completes after the change has been started on the platform side」）。
/// そのため `onCameraIdle` が「自分（[MapView]）が発行した移動の収束」なのか
/// 「利用者がドラッグ/ピンチした結果の収束」なのかを、[Future] の完了だけでは
/// 区別できない。
///
/// ## 採用した区別方法（Issue #141 提案2「区別できない場合は自前でカメラ移動を
/// 発行した直後のイベントを無視する等の方法を取る」に対応）
/// 自前でカメラ移動 API を呼ぶ直前に [markProgrammaticMove] を呼び、「次に届く
/// 1回の `onCameraIdle` は自分が発行した移動の収束である」とマークする。
/// [handleCameraIdle] はそのマークがあれば消費して追従を維持し（解除を
/// 通知しない）、マークが無ければ利用者操作とみなして追従解除の要否を返す。
///
/// ## 既知の制約（Issue #141 提案2「選んだ方法と理由をコードコメントに残す」）
/// 自分の `animateCamera` によるカメラ移動が収まる**前**に利用者が地図に
/// 触れた場合、`maplibre_gl`（内部的には native SDK）側でジェスチャーと
/// API呼び出しによる移動が1回の `onCameraIdle` に合流しうる。この場合は
/// 「自分の移動」として消費され、その回に限り追従は解除されない（次の
/// 位置更新でカメラが再度追従先の位置へ動くため、実害は「その1回だけ利用者の
/// 操作直後の解除が遅れる」程度に留まる）。`maplibre_gl` は
/// `onCameraMoveStarted` に移動の原因（ジェスチャー起因か API 起因か）を
/// 渡さない（`flutter-maplibre-gl` の `controller.dart` で確認済み）ため、
/// これ以上の精緻な区別はできない。
///
/// ## 既知の制約その2: カメラが既に目的地にいる場合のフラグの取り残し
/// [markProgrammaticMove] を呼んで `animateCamera` を発行しても、カメラが
/// 既にその目的地にいる（移動量ゼロ）場合、SDK が `onCameraIdle` を
/// 発火させない可能性がある。この場合フラグが立ったまま残り、次に来る
/// **利用者操作**による `onCameraIdle` を「自分の移動」として誤って消費し、
/// 追従が解除されない（その次の利用者操作からは正しく解除される）。
/// 具体的に起こりうる操作列: 追従オン→（地図を動かさずに）オフ→オン
/// （`didUpdateWidget` がオン化直後に現在地へ `_moveCameraTo` を呼ぶが、
/// カメラは既にそこにいるため実質何も動かない）→ここで利用者がドラッグ
/// しても1回目は解除されない。秘書セッションの実機確認手順にこの操作列
/// （追従オン→オフ→オン→ドラッグ）を明記し、2回目のドラッグで解除される
/// ことを確認する運用とする（実装での完全な解消は見送った。上記「既知の
/// 制約」と同種のトレードオフであり、実害は「解除が1回遅れる」程度）。
class CameraFollowTracker {
  bool _expectingOwnIdle = false;

  /// 自前でカメラ移動 API（`animateCamera`/`moveCamera`）を呼ぶ直前に呼ぶ。
  void markProgrammaticMove() {
    _expectingOwnIdle = true;
  }

  /// `onCameraIdle` が発火するたびに呼ぶ。戻り値が true の場合、この収束は
  /// 利用者操作によるものであり追従を解除すべきことを意味する（呼び出し側は
  /// これを機に [MapView.onFollowDismissedByUser] を呼ぶ）。
  ///
  /// [followEnabled] が false（そもそも追従がオフ）の場合は常に false を返す
  /// （解除するもの自体が無いため）。
  bool handleCameraIdle({required bool followEnabled}) {
    if (_expectingOwnIdle) {
      _expectingOwnIdle = false;
      return false;
    }
    return followEnabled;
  }
}
