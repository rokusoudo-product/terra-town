import 'package:flutter/material.dart';

/// DESIGN.md「余白・レイアウト」節の唯一の実装対応物。
///
/// 8pt グリッド（8/16/24/32/48/64、例外は 4 のみ）＋ 最小タップ領域 48×48dp。
class AppSpacing {
  const AppSpacing._();

  /// 8pt グリッドの唯一の例外値。
  static const double xs = 4;

  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  /// タップ対象 最低 48×48dp（DESIGN.md「余白・レイアウト」）。
  static const Size minTapTarget = Size(xxl, xxl);
}
