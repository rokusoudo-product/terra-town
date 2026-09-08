/// ヘクス（表示用マス）の決定論的な識別子。
///
/// GPS_ARCHITECTURE 準拠（`C:\Users\moets\.claude\GPS_ARCHITECTURE.md`）・
/// docs/terrain.md §4・plan.md §5:
/// 緯度経度→ヘクス幾何の変換ロジックそのものは `core` に置かず、`location/`
/// または表示レイヤーの責務とする（2026-08-11 代表回答）。
/// [HexId] はその変換の**結果**だけを保持する値オブジェクトであり、
/// ヘクス幾何・地図SDKには一切依存しない。
///
/// Issue #33 コメント（2026-08-13・Issue #24 実機計測より）:
/// fog of war 実装は全ヘクスを地図ソースに一度だけ追加し、以後
/// `setFeatureState` でヘクス単位に開示をトグルする方式を採用した。
/// Android では MapLibre の Feature に `promoteId`（Web専用）が使えず、
/// Feature 直下の整数 `id` に一意かつ決定論的に対応付ける必要があるため、
/// [HexId] は整数値をそのまま内部表現として持つ。
/// 「[HexId] → 地図 Feature の `id`」への変換自体は `location/` または
/// 表示レイヤーの責務であり、`core` はここでは関与しない。
class HexId {
  /// ヘクスを一意に表す非負整数値。
  ///
  /// 同一の入力（緯度経度）からは常に同一の値が渡されることを
  /// 呼び出し側（`location/`）が保証する。`core` 側はその値の
  /// 等価性・ハッシュ整合性のみを担保する。
  final int value;

  const HexId(this.value) : assert(value >= 0, 'HexId は非負の整数のみを表す');

  /// 地図 Feature の整数 `id` に渡すための明示的な取り出し。
  ///
  /// 現状は [value] と同一だが、将来 [HexId] の内部表現が変わっても
  /// 呼び出し側（`location/`）のコードを壊さないよう、変換用の窓口として
  /// 明示的に用意している。
  int toInt() => value;

  @override
  bool operator ==(Object other) => other is HexId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'HexId($value)';
}
