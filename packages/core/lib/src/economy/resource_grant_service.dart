import '../terrain/terrain_type.dart';
import '../terrain/terrain_yield.dart';
import 'resource.dart';

/// 1時間に相当するマイクロ秒数（`Duration.microsecondsPerHour` と同じ値を明示的に
/// 定義したもの）。地形産出の「1時間に1個」という仮値の分母として使う。
///
/// 【仮値であることについて】この定数自体（時間の単位）は仮値ではないが、
/// これを使う [terrainYieldAmountPerHexPerUnit]（分子側の量）は仮値であり、
/// 正本は `specs/001-mvp/balance.csv`（Issue #36・T106・未作成）である
/// （[terrainYieldAmountPerHexPerUnit] のドキュメント参照）。
const int terrainYieldMicrosecondsPerUnit = Duration.microsecondsPerHour;

/// 【仮値】1ヘクスあたり、その地形の産出資材それぞれ [terrainYieldMicrosecondsPerUnit]
/// （1時間）に1個産出する（2026-09-11・Issue #138・代表決定）。
///
/// 正本は `specs/001-mvp/balance.csv`（Issue #36・T106・**未作成**）。同ファイルが
/// 作成された際は、この定数をそちらから読む方式へ差し替えること。**本 Issue の
/// スコープでは `balance.csv` は作らない**（Issue #138 本文「起票時に決定済みの
/// 事項」2番）。
///
/// **貯められる上限は設けない**（同・代表決定）。`core` の `Inventory` クラスは
/// `defaultCap`（仮値999）による上限クランプの仕組みを持つが、地形産出の
/// 資材付与は `packages/location` の `TerrainYieldLedger` が `inventory` テーブルへ
/// 直接加算する経路を使い、あえて `Inventory` クラスを経由しない
/// （`TerrainYieldLedger` のクラスdoc参照）。これにより「地形産出には上限を
/// 設けない」という決定事項が `Inventory.defaultCap` に阻まれることなく実現される。
const int terrainYieldAmountPerHexPerUnit = 1;

/// [computeTerrainYieldAccrual] の戻り値（T066・T068・Issue #138）。
class TerrainYieldAccrual {
  const TerrainYieldAccrual({
    required this.granted,
    required this.remainderMicros,
  });

  /// この呼び出しで実際に付与すべき資材ごとの量（0個の資材はキーを持たない）。
  final Map<Resource, int> granted;

  /// 次回呼び出しに持ち越す端数〔マイクロ秒〕（資材ごと。0の資材はキーを持たない）。
  ///
  /// 呼び出し側は次回 [computeTerrainYieldAccrual] を呼ぶ際、この値をそのまま
  /// `previousRemainderMicros` として渡すこと。そうすることで端数が失われない
  /// （1時間未満の産出が積み上がって、いずれ1個分に達する）ことを保証する。
  final Map<Resource, int> remainderMicros;

  /// 何も起きなかった（経過時間0・開示済みヘクスなし等）場合の空の結果。
  static const empty = TerrainYieldAccrual(granted: {}, remainderMicros: {});

  @override
  String toString() =>
      'TerrainYieldAccrual(granted: $granted, remainderMicros: $remainderMicros)';
}

/// 開示済みヘクスの地形分類ごとの件数と経過時間から、地形産出（受動・時間ベース）の
/// 資材付与量を計算する決定論的な純粋関数（T066・T068・Issue #138）。
///
/// 出典: `specs/001-mvp/spec.md` §6「入手（地形産出＝受動・薄く常時）」。
/// 産出量は地形→資材のマッピング（[terrainYieldOf]）を1ヘクスあたりの基礎産出量として
/// 使い、二重定義しない。
///
/// ## 整数演算で端数を失わない
/// 資材ごとに「寄与ヘクス数 × 経過マイクロ秒 × [terrainYieldAmountPerHexPerUnit]」を
/// 整数のまま [previousRemainderMicros] に積み上げ、[terrainYieldMicrosecondsPerUnit]
/// （1時間のマイクロ秒）で整数除算した商を [TerrainYieldAccrual.granted] として返し、
/// 余りを [TerrainYieldAccrual.remainderMicros] として返す。`double` は一切使わない。
///
/// **区間を細かく分けて複数回呼び出しても、合計の [TerrainYieldAccrual.granted] は
/// 1回で呼び出した場合と一致する**（呼び出し側が毎回 [remainderMicros] を正しく
/// 持ち越す限り）。これは剰余を保ったまま合算しているためで、
/// `packages/core/test/economy/resource_grant_test.dart` で証明する。
///
/// ## 1ヘクスが複数資材を産出する場合（山→石・鉄）
/// [hexCountByTerrain] の同じヘクス数が、そのテラインが産出する資材それぞれに
/// 独立して適用される（[terrainYieldOf] が返す集合の要素ごとに、同じヘクス数を
/// 加算する）。山1ヘクスなら石1個/時間・鉄1個/時間が**それぞれ独立に**積み上がる
/// （合計で1時間に2個ではない）。
///
/// ## 空き地
/// [TerrainType.vacantLot] は [terrainYieldOf] が空集合を返すため、
/// [hexCountByTerrain] にいくつ含まれていても資材付与には一切寄与しない。
///
/// [elapsedMicroseconds] が負の場合は [ArgumentError] を投げる（呼び出し側が
/// 単調時計の差分を渡す前提であり、負の経過時間は呼び出し側のバグを示す）。
TerrainYieldAccrual computeTerrainYieldAccrual({
  required Map<TerrainType, int> hexCountByTerrain,
  required int elapsedMicroseconds,
  Map<Resource, int> previousRemainderMicros = const {},
}) {
  if (elapsedMicroseconds < 0) {
    throw ArgumentError.value(
      elapsedMicroseconds,
      'elapsedMicroseconds',
      '負の経過時間は扱えない（呼び出し側は単調時計の非負の差分を渡すこと）',
    );
  }

  // 資材ごとの寄与ヘクス数を集計する（山のように1ヘクスが複数資材を産出する場合、
  // 各資材に同じヘクス数を独立して加算する）。
  final hexCountByResource = <Resource, int>{};
  hexCountByTerrain.forEach((terrain, count) {
    if (count <= 0) return;
    for (final resource in terrainYieldOf(terrain)) {
      hexCountByResource.update(
        resource,
        (value) => value + count,
        ifAbsent: () => count,
      );
    }
  });

  if (hexCountByResource.isEmpty && previousRemainderMicros.isEmpty) {
    return TerrainYieldAccrual.empty;
  }

  final granted = <Resource, int>{};
  final remainder = <Resource, int>{};
  final resources = <Resource>{
    ...hexCountByResource.keys,
    ...previousRemainderMicros.keys,
  };
  for (final resource in resources) {
    final hexCount = hexCountByResource[resource] ?? 0;
    final prevRemainder = previousRemainderMicros[resource] ?? 0;
    final totalMicros = prevRemainder +
        hexCount * elapsedMicroseconds * terrainYieldAmountPerHexPerUnit;
    final grantedAmount = totalMicros ~/ terrainYieldMicrosecondsPerUnit;
    final newRemainder = totalMicros % terrainYieldMicrosecondsPerUnit;
    if (grantedAmount > 0) granted[resource] = grantedAmount;
    if (newRemainder > 0) remainder[resource] = newRemainder;
  }
  return TerrainYieldAccrual(granted: granted, remainderMicros: remainder);
}
