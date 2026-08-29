import 'package:flutter/material.dart';

/// DESIGN.md「カラートークン」節（12種 + fog）の唯一の実装対応物。
///
/// このファイル以外で `Color(0x...)` / `Colors.*` のリテラルを書かないこと
/// （Issue #25 受け入れ基準）。値を変更する場合は DESIGN.md 側も同一 PR で更新する。
/// 違反は `tools/check_design_tokens.sh` が CI で機械的に検出する（Issue #47）。
class ColorTokens {
  const ColorTokens._();

  // primary（主要アクション・自分の街の象徴色）
  static const Color primaryLight = Color(0xFF2E7D32);
  static const Color primaryDark = Color(0xFF7CC47F);

  // secondary（サブアクション・区画/水辺系）
  static const Color secondaryLight = Color(0xFF00695C);
  static const Color secondaryDark = Color(0xFF4DB6AC);

  // accent（獲得・名所ハイライト、10%）
  static const Color accentLight = Color(0xFFF9A825);
  static const Color accentDark = Color(0xFFFFCA45);

  // background（画面背景・地図以外）
  static const Color backgroundLight = Color(0xFFFAFAF7);
  static const Color backgroundDark = Color(0xFF121410);

  // surface（カード・パネル・HUD背景）
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E211C);

  // text
  static const Color textPrimaryLight = Color(0xFF1B1C18);
  static const Color textPrimaryDark = Color(0xFFE4E4DC);
  static const Color textSecondaryLight = Color(0xFF4A4B45);
  static const Color textSecondaryDark = Color(0xFFA8AAA0);

  // semantic
  static const Color successLight = Color(0xFF2E7D32);
  static const Color successDark = Color(0xFF7CC47F);
  static const Color warningLight = Color(0xFFF9A825);
  static const Color warningDark = Color(0xFFFFCA45);
  static const Color errorLight = Color(0xFFC62828);
  static const Color errorDark = Color(0xFFEF9A9A);
  static const Color infoLight = Color(0xFF1565C0);
  static const Color infoDark = Color(0xFF90CAF9);

  /// fog of war 暗幕（未開示ヘクス）。地図はライトのみ MVP のため単一値。
  /// DESIGN.md: rgba(20,22,16,0.62)
  static const Color fog = Color(0x9E141610);

  /// on-color（コントラスト用の前景色）は DESIGN.md に個別値の定義が無いため、
  /// 背景トークンの輝度から自動算出する（白 or 黒87%）。
  static Color _onColorFor(Color background) {
    final brightness = ThemeData.estimateBrightnessForColor(background);
    return brightness == Brightness.dark ? Colors.white : Colors.black87;
  }

  /// DESIGN.md のトークンを Material 3 ColorScheme にマッピングしたライトテーマ用配色。
  /// accent は Material 3 の tertiary スロットに、text-secondary は
  /// onSurfaceVariant / outline に対応させる。
  static ColorScheme get lightScheme => ColorScheme.light(
    primary: primaryLight,
    onPrimary: _onColorFor(primaryLight),
    secondary: secondaryLight,
    onSecondary: _onColorFor(secondaryLight),
    tertiary: accentLight,
    onTertiary: _onColorFor(accentLight),
    error: errorLight,
    onError: _onColorFor(errorLight),
    surface: surfaceLight,
    onSurface: textPrimaryLight,
    onSurfaceVariant: textSecondaryLight,
    outline: textSecondaryLight,
  );

  /// ダークテーマ用配色（地図以外の UI 向け。地図は本 Issue のスコープ外）。
  static ColorScheme get darkScheme => ColorScheme.dark(
    primary: primaryDark,
    onPrimary: _onColorFor(primaryDark),
    secondary: secondaryDark,
    onSecondary: _onColorFor(secondaryDark),
    tertiary: accentDark,
    onTertiary: _onColorFor(accentDark),
    error: errorDark,
    onError: _onColorFor(errorDark),
    surface: surfaceDark,
    onSurface: textPrimaryDark,
    onSurfaceVariant: textSecondaryDark,
    outline: textSecondaryDark,
  );
}

/// Material 3 の ColorScheme に無い DESIGN.md 独自トークン（success / warning / info / fog）を
/// 保持する ThemeExtension。`Theme.of(context).extension<AppSemanticColors>()` で参照する。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.info,
    required this.fog,
  });

  final Color success;
  final Color warning;
  final Color info;
  final Color fog;

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? info,
    Color? fog,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      info: info ?? this.info,
      fog: fog ?? this.fog,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) {
      return this;
    }
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      info: Color.lerp(info, other.info, t)!,
      fog: Color.lerp(fog, other.fog, t)!,
    );
  }
}

/// `theme.semanticColors` で AppSemanticColors に簡潔にアクセスするための拡張。
extension AppSemanticColorsX on ThemeData {
  AppSemanticColors get semanticColors => extension<AppSemanticColors>()!;
}
