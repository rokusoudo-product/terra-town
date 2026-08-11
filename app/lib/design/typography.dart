import 'package:flutter/material.dart';

/// DESIGN.md「タイポグラフィ」節の唯一の実装対応物。
///
/// スケール: 12 / 14 / 16 / 20 / 24 / 32（本文 16・補助 12）。行間 1.5〜1.7。
/// フォント: 日本語 UI は Noto Sans JP が第一候補だが、モバイルはシステムデフォルト可
/// （DESIGN.md）のため、本アプリではシステムデフォルトフォントを使用する
/// （カスタムフォント同梱は本 Issue のスコープ外）。
class AppTypography {
  const AppTypography._();

  static const double scale12 = 12;
  static const double scale14 = 14;
  static const double scale16 = 16; // 本文基準
  static const double scale20 = 20;
  static const double scale24 = 24;
  static const double scale32 = 32;

  /// 行間 1.5〜1.7 の範囲内で統一的に採用する値。
  static const double lineHeight = 1.6;

  /// [primary] は本文色、[secondary] は補助テキスト色（DESIGN.md text-secondary）。
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    TextStyle style(
      double size, {
      FontWeight weight = FontWeight.normal,
      Color? color,
    }) {
      return TextStyle(
        fontSize: size,
        height: lineHeight,
        fontWeight: weight,
        color: color ?? primary,
      );
    }

    return TextTheme(
      displayLarge: style(scale32, weight: FontWeight.w600),
      displayMedium: style(scale32, weight: FontWeight.w600),
      displaySmall: style(scale24, weight: FontWeight.w600),
      headlineLarge: style(scale24, weight: FontWeight.w600),
      headlineMedium: style(scale24, weight: FontWeight.w600),
      headlineSmall: style(scale20, weight: FontWeight.w600),
      titleLarge: style(scale20, weight: FontWeight.w500),
      titleMedium: style(scale16, weight: FontWeight.w500),
      titleSmall: style(scale14, weight: FontWeight.w500),
      bodyLarge: style(scale16), // 本文
      bodyMedium: style(scale14),
      bodySmall: style(scale12, color: secondary), // 補助
      labelLarge: style(scale14, weight: FontWeight.w500),
      labelMedium: style(scale12, weight: FontWeight.w500),
      labelSmall: style(scale12, weight: FontWeight.w500, color: secondary),
    );
  }
}
