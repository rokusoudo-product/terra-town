/// Fog of war（未開示ヘクスの暗幕）レイヤーの受け皿。
///
/// 【設計方針・Issue #57（代表決定 2026-09-07・注入方式）】
/// `packages/location` は配色を一切知らない。色・不透明度は
/// composition root である `app` がコンストラクタ引数で注入する。
/// `location` に `terra_town` の配色パッケージへの依存を持たせないのは、
/// `GPS_ARCHITECTURE.md` の狙い（GPS まわりの実装を今後の GPS 利用アプリ間で
/// 使い回せる資産にすること）と整合させるため。`location` が特定アプリの
/// 配色に依存すると、他アプリへ移植する際に配色が付いてきてしまい、
/// この狙いに反する。
///
/// 色の正しさ（DESIGN.md のトークンと一致すること）を担保する責務は
/// `app` 側（`app/lib/map/fog_of_war_layer_factory.dart` とそのテスト）にあり、
/// `location` 側のテストはフェイク値を渡して「受け取った値をそのまま保持する」
/// ことだけを検証する。
///
/// MapLibre への実際のレイヤー登録・`feature-state` によるトグル処理
/// （`specs/001-mvp/plan.md` §8・タスク T056）は本 Issue のスコープ外。
/// ここではコンストラクタで値を受け取れる最小の骨組みのみを用意する。
class FogOfWarLayer {
  const FogOfWarLayer({required this.fillColorHex, required this.fillOpacity});

  /// MapLibre のスタイル式（`fill-color`）に渡す `#RRGGBB` 形式の16進文字列。
  /// 値の正しさは呼び出し側（`app`）の責務であり、ここでは検証しない。
  final String fillColorHex;

  /// `fill-opacity` に渡す不透明度（0.0〜1.0）。
  final double fillOpacity;
}
