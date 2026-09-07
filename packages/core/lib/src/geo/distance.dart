/// 距離を表す値オブジェクト。
///
/// Issue #33 の未解決の質問「Distance の単位はメートル固定でよいか」への
/// 2026-08-11 代表回答: **単位はメートル固定**。km・歩数などの表示変換は
/// UI 層の責務とし、型自体には単位情報を持たせない。
class Distance implements Comparable<Distance> {
  /// 距離〔メートル〕。
  final double meters;

  const Distance.meters(this.meters)
      : assert(meters >= 0, 'Distance は非負の値のみを表す');

  /// 距離0（原点）。
  static const Distance zero = Distance.meters(0);

  Distance operator +(Distance other) => Distance.meters(meters + other.meters);

  @override
  int compareTo(Distance other) => meters.compareTo(other.meters);

  bool operator <(Distance other) => meters < other.meters;

  bool operator <=(Distance other) => meters <= other.meters;

  bool operator >(Distance other) => meters > other.meters;

  bool operator >=(Distance other) => meters >= other.meters;

  @override
  bool operator ==(Object other) => other is Distance && other.meters == meters;

  @override
  int get hashCode => meters.hashCode;

  @override
  String toString() => 'Distance(${meters}m)';
}
