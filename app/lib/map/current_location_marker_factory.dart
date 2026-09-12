import 'package:terra_town_location/terra_town_location.dart';

import '../design/color_tokens.dart';
import '../design/map_style_colors.dart';

/// composition root（`app`）で `CurrentLocationMarkerStyle`（現在地マーカーの
/// 見た目・T058）を組み立てる。
///
/// 【Issue #57・注入方式】色を知っているのは `app` 側のみ。`packages/location`
/// の `CurrentLocationMarkerStyle` はコンストラクタで受け取った16進文字列を
/// 保持するだけで、配色そのものには関与しない（`fog_of_war_layer_factory.dart`
/// と同じ役割分担）。
///
/// 【色トークンの選定理由（Issue #141 提案5）】
/// DESIGN.md のカラートークンに現在地マーカー専用のトークンは定義されていない。
/// Issue #141 は「既存トークンから選ぶか、理由を添えて DESIGN.md に追記」を
/// 求めており、本実装は**既存トークンから選ぶ**側を採る（DESIGN.md への
/// 新規トークン追加は行っていない）。
///   - 塗り色 = `info`（#1565C0・ライト）。DESIGN.md 上の定義用途は
///     「情報・チュートリアル」だが、地図上で現在地を青系の点で示すのは
///     地図アプリ全般で広く定着した表現であり、`primary`（緑・探索/自分の街の
///     象徴色）・`accent`（獲得・名所ハイライト）・`secondary`（区画/水辺系）と
///     いった既存トークンの意味と衝突しない色として選んだ。
///   - 縁取り色 = `surface`（#FFFFFF・ライト）。地図（地域パックの緑・水色や
///     fog の暗幕）の上でも塗り色を視認しやすくするための白い縁取りとして、
///     DESIGN.md の「カード・パネル背景」トークンを流用した。新規に「白」
///     トークンを追加する理由が無いため、既存の `surface` で足りると判断した。
/// 地図はライトテーマのみ MVP（DESIGN.md「プロジェクト固有ルール」）のため、
/// ダーク側のマッピングは考慮しない（`buildFogOfWarLayer` と同じ前提）。
CurrentLocationMarkerStyle buildCurrentLocationMarkerStyle() {
  return CurrentLocationMarkerStyle(
    fillColorHex: ColorTokens.infoLight.toMapLibreHexRGB,
    strokeColorHex: ColorTokens.surfaceLight.toMapLibreHexRGB,
  );
}
