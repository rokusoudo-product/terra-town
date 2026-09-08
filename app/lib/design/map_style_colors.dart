import 'package:flutter/material.dart';

/// DESIGN.md のカラートークン（`ColorTokens`、`Color` 型）から、MapLibre の
/// スタイル式が要求する `#RRGGBB` 形式の16進文字列と α（0.0〜1.0）を導出する。
///
/// 【背景・Issue #57】地図SDK（MapLibre）は Flutter の `Color` 型を受け取らない。
/// また `packages/location` は GPS_ARCHITECTURE 準拠で `terra_town` の配色に
/// 依存できない（依存すると他アプリへ持っていくときに配色が付いてきてしまう）。
/// そのため `packages/location` の地図レイヤー（`FogOfWarLayer` 等）へ値を
/// 渡す際は、composition root である `app` がこの変換を経由して注入する
/// （`location` 自体はこのファイルにも `Color` 型にも依存しない）。
///
/// 数値の正本はあくまで DESIGN.md のトークン（`ColorTokens`）であり、
/// このファイルは導出のみを行う。新しい `Color(0x...)` リテラルは追加しない
/// （`tools/check_design_tokens.sh` の allowlist は `design/` 配下のみ）。
extension MapStyleColor on Color {
  /// `#RRGGBB` 形式（アルファは含まない。MapLibre の `fill-color` 用）。
  /// 桁は大文字（DESIGN.md のカラートークン表記 `#2E7D32` 等に合わせる）。
  ///
  /// `Color.r/g/b` は 0.0〜1.0 の `double`（Flutter の wide-gamut Color 表現）。
  /// 8bit 相当に変換してから16進表記する。
  String get toMapLibreHexRGB {
    String channel(double component) {
      final value = (component * 0xFF).round().clamp(0, 0xFF);
      return value.toRadixString(16).padLeft(2, '0').toUpperCase();
    }

    return '#${channel(r)}${channel(g)}${channel(b)}';
  }

  /// `fill-opacity` 等に渡す不透明度（0.0〜1.0）。
  double get toMapLibreOpacity => a;
}
