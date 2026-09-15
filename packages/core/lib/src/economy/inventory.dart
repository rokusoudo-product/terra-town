import 'resource.dart';

/// 資材ごとの所持数を管理するインベントリ（T027）。
///
/// 出典: `specs/001-mvp/spec.md` §6・Issue #82 受け入れ基準
/// 「`Inventory` が加算・消費・上限を扱える」。
///
/// ⚠️ **[defaultCap] の値は balance 調整で変わりうる（status: 仮）。**
/// 正本は `specs/001-mvp/balance.yaml`（`inventory.default_cap`）であり、
/// 照合テスト（`packages/core/test/balance/balance_yaml_test.dart`）で本定数
/// との一致を確認している。コンストラクタで渡す `caps`（資材ごとの個別上限）は
/// balance.yaml に対応する項目がなく、呼び出し側が独自に決める暫定値のままである
/// （本 Issue #82 のスコープは「加算・消費・上限」という**仕組み**の実装まで）。
class Inventory {
  /// 資材ごとの上限が個別指定されていない場合に使う上限値。
  ///
  /// 【仮】正本は `specs/001-mvp/balance.yaml`（`inventory.default_cap`）。
  /// 照合テストで一致を確認している。
  static const int defaultCap = 999;

  final Map<Resource, int> _quantities = {};
  final Map<Resource, int> _caps;

  /// [caps] で資材ごとの上限値を個別に指定できる。指定のない資材は
  /// [defaultCap] を上限として扱う（[defaultCap] の正本は balance.yaml。
  /// 個別の `caps` は balance.yaml に対応項目が無い暫定値）。
  Inventory({Map<Resource, int>? caps}) : _caps = Map.of(caps ?? const {});

  /// [resource] の現在の所持数。未加算の資材は 0。
  int amountOf(Resource resource) => _quantities[resource] ?? 0;

  /// [resource] の上限値（未指定の場合は [defaultCap]）。
  int capOf(Resource resource) => _caps[resource] ?? defaultCap;

  /// [resource] を [amount] だけ加算する。
  ///
  /// 上限（[capOf]）を超える分は切り捨てる（クランプ）。**これは本実装が
  /// 採用した実装上の選択であり、`docs/terrain.md`・`docs/buildings.md`・
  /// `spec.md` のいずれにも「上限超過分をどう扱うか」の記述はない（要確認）。**
  /// `specs/001-mvp/balance.yaml`（Issue #36）で上限値と合わせてこの挙動
  /// （クランプ／産出停止等）自体が確定した場合は、本コメントおよび実装を
  /// 見直すこと。
  ///
  /// 返り値は実際に加算された量（上限に阻まれた分を差し引いた量）。
  int add(Resource resource, int amount) {
    if (amount < 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        '負の値は加算できない（消費する場合は consume を使うこと）',
      );
    }
    final current = amountOf(resource);
    final cap = capOf(resource);
    final next = (current + amount > cap) ? cap : current + amount;
    _quantities[resource] = next;
    return next - current;
  }

  /// [resource] を [amount] だけ消費する。
  ///
  /// 所持数が [amount] に満たない場合は何も変更せず false を返す
  /// （部分的な消費は行わない。建設・強化のコスト支払いのような
  /// 「必要量が揃っていなければ実行しない」用途を想定）。
  /// 消費できた場合は true を返す。
  bool consume(Resource resource, int amount) {
    if (amount < 0) {
      throw ArgumentError.value(amount, 'amount', '負の値は消費できない');
    }
    final current = amountOf(resource);
    if (current < amount) {
      return false;
    }
    _quantities[resource] = current - amount;
    return true;
  }
}
