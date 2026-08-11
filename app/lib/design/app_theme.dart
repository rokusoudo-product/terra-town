import 'package:flutter/material.dart';

import 'color_tokens.dart';
import 'spacing.dart';
import 'typography.dart';

/// DESIGN.md のトークン層から Material 3 `ThemeData`（ライト/ダーク）を生成する。
///
/// 画面側は `Theme.of(context)` 経由でのみ色・タイポグラフィを参照し、
/// カラーコード・フォントサイズ・余白の直書きは行わないこと（Issue #25 受け入れ基準）。
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _themeFrom(
    colorScheme: ColorTokens.lightScheme,
    backgroundColor: ColorTokens.backgroundLight,
    semanticColors: const AppSemanticColors(
      success: ColorTokens.successLight,
      warning: ColorTokens.warningLight,
      info: ColorTokens.infoLight,
      fog: ColorTokens.fog,
    ),
  );

  static ThemeData dark() => _themeFrom(
    colorScheme: ColorTokens.darkScheme,
    backgroundColor: ColorTokens.backgroundDark,
    semanticColors: const AppSemanticColors(
      success: ColorTokens.successDark,
      warning: ColorTokens.warningDark,
      info: ColorTokens.infoDark,
      // 地図はライトのみ MVP のため fog は単一値（ダークテーマでも同値）。
      fog: ColorTokens.fog,
    ),
  );

  static ThemeData _themeFrom({
    required ColorScheme colorScheme,
    required Color backgroundColor,
    required AppSemanticColors semanticColors,
  }) {
    final textTheme = AppTypography.textTheme(
      primary: colorScheme.onSurface,
      secondary: colorScheme.onSurfaceVariant,
    );

    final minTapTargetStyle = ButtonStyle(
      minimumSize: WidgetStateProperty.all(AppSpacing.minTapTarget),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: colorScheme.brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: backgroundColor,
      textTheme: textTheme,
      extensions: <ThemeExtension<dynamic>>[semanticColors],
      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(style: minTapTargetStyle),
      filledButtonTheme: FilledButtonThemeData(style: minTapTargetStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: minTapTargetStyle),
      textButtonTheme: TextButtonThemeData(style: minTapTargetStyle),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: AppSpacing.minTapTarget),
      ),
    );
  }
}
