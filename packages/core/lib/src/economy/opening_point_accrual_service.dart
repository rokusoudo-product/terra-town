/// 開放ポイントの歩行距離換算レート〔ミリメートル〕。この距離ぶんの
/// 「移動距離 × 付与倍率」の積算に達するごとに開放ポイント1Pを付与する。
///
/// **1.5km = 1,500,000mm（2026-09-12 代表決定・Issue #143）。**
/// `docs/opening_points.md` §2.2 の「secretary 提案の仮置き値・代表の最終確認待ち」は
/// この決定により解消済み。ただし数値の正本は引き続き `specs/001-mvp/balance.csv`
/// （Issue #36・T106・**未作成**）であり、同ファイル作成時にはそちらから読む方式へ
/// 差し替えること（`resource_grant_service.dart` の
/// `terrainYieldAmountPerHexPerUnit` と同じ「確定値だが将来の差し替え対象」という
/// 位置づけ）。**本 Issue（#143）のスコープでは `balance.csv` は作らない。**
const int openingPointDistanceMillimetersPerPoint = 1500000;

/// 開放ポイントのストック上限（`docs/opening_points.md` §4・2026-07-22代表決定）。
///
/// 上限に達している間の新規付与分（歩行距離換算・[computeOpeningPointAccrual] が
/// 返す [OpeningPointAccrual.truncatedPoints]）は切り捨てる。
const int openingPointStockCap = 50;

/// メートル→ミリメートルの変換係数（整数演算のため距離をミリメートル単位に量子化する）。
const int _millimetersPerMeter = 1000;

/// [computeOpeningPointAccrual] の戻り値（Issue #143）。
class OpeningPointAccrual {
  const OpeningPointAccrual({
    required this.grantedPoints,
    required this.remainderMillimeters,
    required this.truncatedPoints,
  });

  /// この呼び出しで実際にストックへ加算すべきポイント量（上限でクランプ済み）。
  final int grantedPoints;

  /// 次回呼び出しに持ち越す端数〔ミリメートル〕。
  ///
  /// 呼び出し側は次回 [computeOpeningPointAccrual] を呼ぶ際、この値をそのまま
  /// `previousRemainderMillimeters` として渡すこと。**上限（[openingPointStockCap]）に
  /// 達している間もこの値は正しく積み上がり続ける**
  /// （クラスdoc「上限到達後の端数の扱い」参照）。
  final int remainderMillimeters;

  /// 上限に阻まれて実際には付与されなかったポイント量（0以上）。
  ///
  /// [grantedPoints] とは独立に「あと何ポイント切り捨てられたか」を可視化するための
  /// 診断用フィールド（デバッグパネル・ログでの説明に使う想定）。呼び出し側の状態
  /// 更新には使わない（上限判定は本関数が既に行っている）。
  final int truncatedPoints;

  /// 何も起きなかった場合の空の結果。
  static const zero =
      OpeningPointAccrual(grantedPoints: 0, remainderMillimeters: 0, truncatedPoints: 0);

  @override
  String toString() => 'OpeningPointAccrual(granted: $grantedPoints, '
      'remainder: ${remainderMillimeters}mm, truncated: $truncatedPoints)';
}

/// 区間の移動距離・付与倍率・現在のストック量から、開放ポイント（歩行距離換算・
/// `docs/opening_points.md` §2.2）の付与量を計算する決定論的な純粋関数
/// （Issue #143・T063）。
///
/// 出典: `docs/opening_points.md` §2.2「歩いた distance（GPS移動距離の累積）に応じて
/// 開放ポイントを付与する」・Issue #143 提案内容1「区間ごとの移動距離 × 付与倍率を
/// 積算し、換算レートに達するごとに1Pを付与する」。
///
/// ## なぜ自然回復（§2.1・1P/日）を計算しないか
/// **本関数・本 Issue（#143）は歩行距離換算（§2.2）のみを実装する。** 自然回復
/// （1日ごとに固定1P）は 2026-09-12 代表決定により MVP では実装しない
/// （[こちらの決定コメント](https://github.com/rokusoudo-product/terra-town/issues/143#issuecomment-5645908958)）。
/// 理由: 「1日ごと」の判定には端末の日付（壁時計）が必要だが、本プロジェクトは
/// 「時刻は単調時計・壁時計は使わない」を一貫した方針としており
/// （`specs/001-mvp/plan.md` §7、Issue #138 の地形産出も単調時計のみ）、
/// サーバを持たない端末内完結の構成では端末時刻の改竄を防げず、歩行優位
/// （`specs/001-mvp/spec.md` §3.2）の設計とも整合しない。自然回復は別 Issue
/// （`future` ラベル）に切り出す。**後続の実装者はこれを実装漏れと誤認しないこと**
/// （`docs/opening_points.md` §2.1 にも同じ理由を記載済み）。
///
/// ## 整数演算で端数を失わない（[resource_grant_service.dart] の
/// `computeTerrainYieldAccrual` と同じ方針）
/// [distanceMeters]（GPS区間距離・メートル）と [rewardMultiplier] の積を
/// ミリメートル単位の整数へ量子化（`floor`）し、[previousRemainderMillimeters]
/// （ミリメートル・整数）に加算したうえで [openingPointDistanceMillimetersPerPoint]
/// で整数除算する。商を付与ポイント数、余りを次回への端数として返す。
///
/// **量子化（メートル→ミリメートルの `floor`）は呼び出し1回につき1度だけ行う。**
/// これは実測された1区間（GPSの2点間）という、それ以上分割しようのない自然な単位に
/// 対して行う操作であり、以降の端数（ミリメートル未満は切り捨てられるが、
/// 1.5kmという換算レートに対して無視できる大きさ）は整数のまま
/// [remainderMillimeters] に正確に持ち越される。**区間を細かく分けて複数回
/// 呼び出しても、合計の [OpeningPointAccrual.grantedPoints] は1回で呼び出した
/// 場合と一致する**（`packages/core/test/economy/opening_point_accrual_test.dart`
/// 「分割しても合計が変わらない」で証明。多数回呼び出す実際の使われ方
/// 〔GPS区間ごとに1回呼ぶ〕とテストの前提が一致するよう、テストは各区間が
/// クリーンなミリメートル値になる入力を使う）。`double` は距離・倍率の入力にのみ
/// 現れ、内部の積算・比較はすべて整数で行う。
///
/// ## [rewardMultiplier] の適用（`RewardPolicy.classify` の出力をそのまま使う）
/// [rewardMultiplier] は `packages/core/lib/src/antispoof/reward_policy.dart` の
/// `RewardPolicy.classify` が区間ごとに返す倍率（モック位置疑い→0・速度超過→0・
/// 歩数不一致→0より大きく1未満・既定0.5・それ以外→1）をそのまま渡す想定
/// （Issue #143 提案内容2）。
///
/// **倍率0.5（歩数不一致）のときの距離の扱い（判断の記録・2026-09-12 実装時決定）**:
/// 「区間の移動距離を半分として積算する」を採用した。すなわち
/// `distanceMeters × 0.5` を換算レートに対する寄与distanceとして扱う（無効化
/// ではなく、その区間の"実効的な移動距離"を穏やかに減らす方式）。この距離の
/// 半減は、`RewardPolicy` クラスdoc「歩数突合（T101）の設計」が定義する
/// `stepMismatchMultiplier`（倍率そのもの・既定0.5・「無効化ではない穏やかな
/// 倍率」）の意味をそのまま距離に投影したものであり、新たな解釈を持ち込んでいない。
///
/// ## 上限到達後の端数の扱い（判断の記録・2026-09-12 実装時決定）
/// `docs/opening_points.md` §4「上限に達している間は新規付与分は加算されずに
/// 切り捨てられる」は**整数ポイント単位の付与**にのみ適用し、**ミリメートル単位の
/// 端数（[remainderMillimeters]）は上限に関わらず常に積み上がり続ける**方式を
/// 採用した。理由:
/// - 端数まで上限到達時に凍結・破棄すると、上限到達中に歩いた分の"あと少しで
///   1P"という進捗が完全に失われ、消費（T064・未実装）でストックが上限を
///   下回った直後の1歩で急に1Pが増えるという不自然な挙動になる
///   （凍結した端数を消費後に"復活"させる設計は状態管理が複雑になり、
///   本Issueのスコープ外の T064 の実装まで検証できない）。
/// - 一方で「切り捨てるのは整数ポイントのみ・端数は失わない」という規則は
///   本関数だけで完結し、消費処理（T064）の実装に依存しない・状態を汚さない
///   （[currentPoints] は呼び出し時点のストック量を渡すだけの引数であり、
///   本関数はそれを書き換えない）。
/// - 「上限到達中に稼いだ端数は、いずれ1Pに達しても上限を超えては付与されない」
///   という上限の趣旨（`docs/opening_points.md` §4「貯めすぎ・非稼働放置による
///   無限蓄積を防ぐ」）は、[grantedPoints] のクランプ（下記）で引き続き守られる。
///
/// [currentPoints]（呼び出し時点のストック量）と [cap]（既定
/// [openingPointStockCap]）から `capacityLeft = cap - currentPoints` を求め、
/// 本来付与されるはずだったポイント数（`rawGrantedPoints`）のうち
/// `capacityLeft` を超える分を [OpeningPointAccrual.truncatedPoints] として
/// 切り捨てる。
///
/// [distanceMeters] が負・[rewardMultiplier] が0〜1の範囲外・
/// [previousRemainderMillimeters]／[currentPoints] が負の場合は
/// [ArgumentError] を投げる（呼び出し側のバグを早期に検知するため。
/// `computeTerrainYieldAccrual` が負の経過時間を拒否するのと同じ方針）。
OpeningPointAccrual computeOpeningPointAccrual({
  required double distanceMeters,
  required double rewardMultiplier,
  required int currentPoints,
  required int previousRemainderMillimeters,
  int cap = openingPointStockCap,
}) {
  if (distanceMeters < 0) {
    throw ArgumentError.value(
      distanceMeters,
      'distanceMeters',
      '距離は非負でなければならない',
    );
  }
  if (rewardMultiplier < 0 || rewardMultiplier > 1) {
    throw ArgumentError.value(
      rewardMultiplier,
      'rewardMultiplier',
      '付与倍率は0以上1以下でなければならない（RewardPolicy.classify の仕様）',
    );
  }
  if (previousRemainderMillimeters < 0) {
    throw ArgumentError.value(
      previousRemainderMillimeters,
      'previousRemainderMillimeters',
      '端数は非負でなければならない',
    );
  }
  if (currentPoints < 0) {
    throw ArgumentError.value(
      currentPoints,
      'currentPoints',
      '所持ポイントは非負でなければならない',
    );
  }

  final weightedMillimeters =
      (distanceMeters * rewardMultiplier * _millimetersPerMeter).floor();
  final totalMillimeters = previousRemainderMillimeters + weightedMillimeters;
  final rawGrantedPoints = totalMillimeters ~/ openingPointDistanceMillimetersPerPoint;
  final remainderMillimeters = totalMillimeters % openingPointDistanceMillimetersPerPoint;

  final capacityLeft = cap - currentPoints;
  final grantedPoints = capacityLeft <= 0
      ? 0
      : (rawGrantedPoints <= capacityLeft ? rawGrantedPoints : capacityLeft);
  final truncatedPoints = rawGrantedPoints - grantedPoints;

  return OpeningPointAccrual(
    grantedPoints: grantedPoints,
    remainderMillimeters: remainderMillimeters,
    truncatedPoints: truncatedPoints,
  );
}
