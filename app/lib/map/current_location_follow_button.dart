import 'package:flutter/material.dart';

import '../design/spacing.dart';

/// 地図追従（カメラが現在地を追う）のオン/オフを切り替えるボタン（Issue #141・
/// T058 受け入れ基準「追従オンでカメラが現在地を追い、利用者が地図を動かすと
/// 追従が解除される。ボタンで再開できる」）。
///
/// 【色だけで情報を伝えない】DESIGN.md「色だけで情報を伝えない（アイコン＋
/// テキスト併用）」に従い、オン/オフの区別をアイコン自体の切り替え
/// （オン=[Icons.my_location]・オフ=[Icons.location_searching]）と
/// [Semantics] のラベルの両方で表現する（背景色の違いのみに頼らない）。
///
/// 【Material 3 準拠】DESIGN.md「プロジェクト固有ルール」の「ボタン・トグル・
/// エラー表示は Material 3 コンポーネントを用いる」に従い、標準の
/// [FloatingActionButton] を使う。色は [Theme] 経由（`ColorScheme`）で
/// 参照するのみで、色コードの直書きは持たない
/// （`tools/check_design_tokens.sh` 準拠）。
class CurrentLocationFollowButton extends StatelessWidget {
  const CurrentLocationFollowButton({
    super.key,
    required this.isFollowing,
    required this.onPressed,
  });

  /// 追従が有効かどうか。
  final bool isFollowing;

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      // 状態をラベルでも明示する（色だけに頼らないため。DESIGN.md参照）。
      label: isFollowing ? '地図の追従をオフにする' : '現在地に地図を合わせて追従する',
      child: SizedBox(
        // タップ対象 最低48×48dp（DESIGN.md「余白・レイアウト」）を
        // AppSpacing.minTapTarget で満たす。
        width: AppSpacing.minTapTarget.width,
        height: AppSpacing.minTapTarget.height,
        child: FloatingActionButton(
          heroTag: 'current_location_follow_button',
          tooltip: isFollowing ? '地図の追従をオフにする' : '現在地に地図を合わせて追従する',
          onPressed: onPressed,
          backgroundColor: isFollowing ? colorScheme.primary : colorScheme.surface,
          foregroundColor: isFollowing ? colorScheme.onPrimary : colorScheme.onSurface,
          child: Icon(isFollowing ? Icons.my_location : Icons.location_searching),
        ),
      ),
    );
  }
}
