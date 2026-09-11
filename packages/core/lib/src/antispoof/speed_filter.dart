import 'dart:collection';
import 'dart:math' as math;

import '../position/geo_position.dart';

/// 速度による GPS 偽装対策判定（T100・Issue #125）。
///
/// 出典: `specs/001-mvp/plan.md` §9・Issue #9 代表回答 9-2「徒歩上限速度（例: 時速10km）
/// 超過は『移動中』として開拓・資材付与を停止する。不正扱いはせず、単に報酬対象外に
/// するだけ（電車・車通勤を罰しない）」。
///
/// ## 最重要方針: 誤検出（正規ユーザーの報酬没収）を見逃しより避ける
/// Issue #125 本文・plan.md §9「都市部マルチパスで瞬間100km/h相当のスパイクは日常」。
/// **生の（平滑化前の）区間速度で判定すると、静止中・低速歩行中でも GPS のマルチパス
/// （ビル反射等）による瞬間的な位置跳躍で容易に閾値を超え、正規ユーザーの報酬が
/// 不当に没収される。** 本実装は [classify] の判定を**平滑化後の速度**でのみ行い、
/// 平滑化前の生の区間速度（[SpeedSegment.rawSpeedKmh]）は診断・テスト用途にのみ
/// 公開する（判定には使わない）。
///
/// ## 平滑化方式の選択: 移動平均（カルマン平滑は不採用）
/// Issue #125 は「移動平均かカルマンかは実装者が選んでよい」としている。**本実装は
/// 移動平均を採用した**。理由:
/// - GPS の観測ノイズ・プロセスノイズの共分散を実測なしに妥当な値へチューニングする
///   ことができない（Kalman は誤ったノイズパラメータでは平滑化が弱すぎる/強すぎる
///   どちらの方向にも壊れやすく、根拠のないパラメータをコードに埋め込むことになる）。
/// - 移動平均は「窓の中の総移動距離 ÷ 窓の経過時間」という単純な計算で、
///   決定論性・テスト容易性・パラメータの説明可能性（下記）に優れる。
/// - plan.md §7「サンプリングは距離ベース（移動検知）」のとおり位置更新の間隔は
///   一定でないため、**サンプル件数ではなく時間長で窓を定義する**（[smoothingWindow]）。
///   サンプル件数基準だと、サンプリング間隔が短くなる局面（例: 速く動いて距離フィルタが
///   頻繁に発火する）で窓の実時間長が縮み、平滑化が弱まってしまう。
///
/// ### 窓幅（既定 [defaultSmoothingWindow] = 120秒）の根拠
/// 実機のマルチパス特性はまだ計測できていない（`tasks.md` T017・R5 が実機検証を
/// 代表に委ねている理由そのもの）。そのため以下は**本実装が採用した想定**であり、
/// 実測（T017）の結果によっては見直すこと:
/// - スパイクの大きさ: 単発の悪い測位で真の位置から**約50mずれ、次の測位で元の
///   経路へ戻る**（跳んで戻る、が持続的にドリフトしない）。Issue #125 本文の
///   「瞬間100km/h相当」は、この50mのずれが約2秒間隔の測位に現れた場合の
///   瞬間速度（50m ÷ 2s ≈ 90km/h）にほぼ一致する。
/// - スパイクの頻度: **平滑化窓（120秒）ごとに高々1回**を最悪ケースとして仮定する
///   （本実装のテストでは140秒間隔で発生させている。窓内に複数のスパイクが同時に
///   入ると平滑化後速度も比例して上振れするため、これが本実装が誤検出を防げると
///   主張する範囲の境界である）。
/// - 徒歩の基準速度: 時速5km（≈1.39m/s）。
/// - 上記の下で、120秒の窓に単発の50mスパイク（跳んで戻るため窓内には往復分の
///   約100mが加わる）が1回含まれる場合:
///   窓内総移動距離 ≈ 徒歩120秒分（5km/h×120s ≈ 166.7m）＋スパイク往復100m
///   ＝ 266.7m。266.7m ÷ 120s ≈ 2.22m/s ≈ **8.0km/h** となり、閾値10km/hを
///   約20%の余裕を持って下回る（`speed_check_test.dart`
///   `マルチパスのスパイクを含む普通の歩行` で検証）。
/// - 一方で電車等の持続的な高速移動への追随は遅くなりすぎない: 徒歩(5km/h)から
///   時速40km/hへ切り替わった場合、窓が徐々に高速区間で埋まっていくため、
///   切り替わりから約17秒で平滑化後速度が10km/hを超え始める計算になる
///   （(120-t)*5 + t*40 > 120*10 を解くと t > 17.14）。
///   「報酬なしになるまでのタイムラグ」は罰則ではなく単なる報酬対象外化なので、
///   この程度の遅延は許容範囲と判断した。
///
/// ## 閾値・窓幅は設定値（正本は balance.csv ではない・要注意）
/// 【仮置き】[defaultThresholdKmh]（時速10km）は Issue #9 代表回答 9-2 が明示した
/// 具体値であり、資材付与レート等の他の balance 数値とは異なり
/// **spec/Issue で既に代表が確定した値**である。とはいえ将来 `balance.csv`
/// （Issue #36）が徒歩上限速度も含めて管理するようになった場合はそちらを正本とし、
/// 本定数は差し替えの対象とする。[defaultSmoothingWindow] は上記の根拠に基づく
/// 本実装独自の仮パラメータであり、実機計測（T017）や `balance.csv` 検討で
/// 見直されることを想定している。いずれも [SpeedFilter] のコンストラクタ引数で
/// 変更可能にしてあり、呼び出し側がハードコードされた値に縛られないようにしている。
///
/// ## 段階的ペナルティにおける位置づけ（Issue #9 代表回答 9-1）
/// 本判定は「区間ごとに報酬対象か否か」を返すのみで、**罰則（BAN・無効化）は行わない**。
/// モック位置検出（Issue #126・T099）の「無効化」、歩数センサー突合（Issue #126・T101）
/// の「レート低下」とは異なるペナルティ段階であり、[classify] は資材付与・開拓への
/// 組み込みは行わない（Issue #125 のスコープ外。呼び出し側が [SpeedSegment.rewardEligible]
/// を見て組み込むこと）。
///
/// ## スコープ外・前提
/// - [GeoPosition] は変更しない（Issue #124 が偽装判定フラグを追加する予定と競合するため）。
///   本判定は位置の列（緯度経度・時刻）だけを見て、モック検出フラグ等には依存しない。
/// - 入力の時刻は plan.md §7 の**単調時計**（`elapsedRealtime` 相当）を前提とし、
///   時刻順（非減少）で並んでいることを要求する（[classify] 参照）。
/// - GPS/地図SDKには依存しない。緯度経度間の距離計算はここで自前実装する
///   （球面近似のHaversine公式。`location/` の実装に依存しない）。
///
/// ## 実機検証の手順（`tasks.md` T017・R5「正規歩行で報酬没収が起きないことの確認」）
/// 本 Issue（#125）のスコープは合成データでの検証まで（Issue #125 本文「スコープ外」）。
/// 実機での確認は代表が行う想定だが、本実装（純粋関数）を使ってそのまま検証できるよう
/// 手順を残しておく（`plan.md`・`docs/` の変更は本 Issue のスコープ外のため、手順は
/// ここにコード doc として記録する）:
/// 1. 実機で普段どおりの徒歩ルート（都市部のビル街を含むことが望ましい。マルチパスが
///    起きやすい環境で検証する意味があるため）を歩き、`location/` 側の記録機構
///    （`PositionProvider` の実装。plan.md §7）で [GeoPosition] の列を記録する。
/// 2. 記録した列を `SpeedFilter().classify(recordedRoute)`（デフォルト設定でよい）に
///    そのまま渡す。`packages/core` は GPS 非依存の純粋ロジックのため、記録済みの
///    列さえあれば実機の外（デスクトップの `dart run` 等）でも判定を再現できる。
/// 3. 結果の [SpeedSegment] のうち `rewardEligible == false` になった区間があれば、
///    その `from.timestamp`〜`to.timestamp` の間、実際には徒歩以外の移動手段
///    （電車・車・自転車等）だったかを本人の記憶と突き合わせる。
/// 4. **もし実際には徒歩だったのに `rewardEligible == false` になった区間があれば、
///    それが誤検出であり本実装の想定（クラスdoc「窓幅の根拠」）が実際のマルチパス
///    特性より甘いことを意味する。** [thresholdKmh]・[smoothingWindow] の見直し、
///    または平滑化方式自体の再検討（移動平均→カルマン等）が必要になる。
/// 5. 誤検出が起きなければ「正規歩行で報酬没収が起きない」ことの実機確認が完了する。
///    合わせて、電車・車移動の区間で `rewardEligible == false` になり、かつ前後の
///    徒歩区間で `rewardEligible == true` に戻ることも確認できるとなお良い。
/// **本 Issue のスコープはこの手順の用意までであり、実機での実施自体は行っていない**
/// （「実機で確認した」とは記載しない）。
class SpeedFilter {
  // Duration の比較演算子・inMicroseconds は定数式として評価できないため、
  // このコンストラクタは const にできない（[thresholdKmh]・[smoothingWindow] の
  // 妥当性チェックを assert で行うため）。
  SpeedFilter({
    this.thresholdKmh = defaultThresholdKmh,
    this.smoothingWindow = defaultSmoothingWindow,
  })  : assert(thresholdKmh > 0, '閾値は正の値でなければならない'),
        assert(smoothingWindow.inMicroseconds > 0, '平滑化の窓は正の時間長でなければならない');

  /// 徒歩上限速度の既定閾値〔km/h〕。
  ///
  /// 出典: Issue #9 代表回答 9-2（「徒歩上限速度（例: 時速10km）超過は
  /// 『移動中』として開拓・資材付与を停止する」）。**「時速10km超」＝この値を
  /// 厳密に超えた場合にのみ報酬対象外とする**（[classify] のドキュメント参照）。
  /// balance.csv（Issue #36）が徒歩上限速度を管理するようになった場合はそちらへ
  /// 差し替えること（クラスdocの「閾値・窓幅は設定値」参照）。
  static const double defaultThresholdKmh = 10.0;

  /// 移動平均の既定窓幅。
  ///
  /// 【仮置き】根拠はクラスdoc「窓幅の根拠」参照。実機計測（tasks.md T017・R5）や
  /// balance.csv 検討で見直されることを想定した本実装独自のパラメータ。
  static const Duration defaultSmoothingWindow = Duration(seconds: 120);

  /// この閾値〔km/h〕を厳密に超えた区間のみ [SpeedSegment.rewardEligible] が false になる。
  final double thresholdKmh;

  /// 移動平均（区間速度の平滑化）に使う時間窓。
  final Duration smoothingWindow;

  /// 位置の列（歩行ルート）を先頭から順に処理し、隣接する2点ごとの区間について
  /// 平滑化後の速度による判定を返す。
  ///
  /// 返り値の長さは `positions.length - 1`（[positions] が0件または1件なら空リスト。
  /// 区間を作れないため）。各要素 `result[i]` は `positions[i]` から `positions[i + 1]`
  /// への区間に対応する。
  ///
  /// ## 前提: 単調時計・時刻の非減少列
  /// [positions] は `timestamp` が非減少（同時刻の重複は許容）であることを前提とする
  /// （plan.md §7「時刻は単調時計」）。逆行する時刻を検知した場合は
  /// [ArgumentError] を送出する（位置は本来ありえないデータであり、
  /// 「報酬なし」として静かに処理すると偽装対策のバグを見逃しかねないため、
  /// 呼び出し側に早期に気付かせる設計とした）。同一時刻で異なる位置に移動した場合
  /// （物理的に不可能）も同様に [ArgumentError] とする（0除算を避けるためだけに
  /// 無限大の速度を握りつぶすと、判定結果の信頼性を損なうため）。
  ///
  /// ## 決定論
  /// 本メソッドは純関数（外部状態を持たず、[positions] のみから結果が決まる）である。
  /// 同じ [positions] を渡せば常に同じ結果を返す
  /// （`speed_check_test.dart` 「同じ入力からは常に同じ判定が出る」で検証）。
  List<SpeedSegment> classify(List<GeoPosition> positions) {
    if (positions.length < 2) {
      return const [];
    }

    final results = <SpeedSegment>[];

    // 移動平均の窓: 直近の区間（distance・duration・区間の開始時刻）を保持する。
    // Duration ベースの窓のため、窓に残す/落とすの判定は区間の「開始時刻」で行う
    // （クラスdoc「窓幅の根拠」参照。サンプル件数ではなく経過時間で窓を定義する）。
    final window = Queue<_RawSegment>();
    var windowDistanceMeters = 0.0;

    for (var i = 1; i < positions.length; i++) {
      final from = positions[i - 1];
      final to = positions[i];

      final elapsed = to.timestamp.difference(from.timestamp);
      if (elapsed.isNegative) {
        throw ArgumentError(
          'positions の timestamp は非減少（単調時計）でなければならない: '
          'index ${i - 1} (${from.timestamp}) → $i (${to.timestamp}) で時刻が逆行している',
        );
      }

      final distanceMeters = _haversineMeters(from, to);
      if (elapsed == Duration.zero && distanceMeters > 0) {
        throw ArgumentError(
          '同一 timestamp (index: $i) で異なる位置への移動は物理的にありえない '
          '（distance=${distanceMeters}m, elapsed=0）。データの整合性を確認すること。',
        );
      }

      final rawSpeedKmh = elapsed == Duration.zero ? 0.0 : _kmh(distanceMeters, elapsed);

      window.addLast(_RawSegment(
        startTimestamp: from.timestamp,
        distanceMeters: distanceMeters,
      ));
      windowDistanceMeters += distanceMeters;

      // 窓の先頭（最も古い区間）が smoothingWindow より古くなったら落とす。
      // 窓に区間が1件も残らない状態は作らない（直近の区間そのものが smoothingWindow
      // より長い場合、平滑化後速度はその区間の生速度にフォールバックする。
      // 「平滑化できるだけの履歴がまだない」自然な挙動として許容する）。
      while (window.length > 1 &&
          to.timestamp.difference(window.first.startTimestamp) > smoothingWindow) {
        final dropped = window.removeFirst();
        windowDistanceMeters -= dropped.distanceMeters;
      }

      final windowElapsed = to.timestamp.difference(window.first.startTimestamp);
      final smoothedSpeedKmh =
          windowElapsed == Duration.zero ? 0.0 : _kmh(windowDistanceMeters, windowElapsed);

      results.add(SpeedSegment(
        from: from,
        to: to,
        rawSpeedKmh: rawSpeedKmh,
        smoothedSpeedKmh: smoothedSpeedKmh,
        // 「時速10km超」＝厳密に超えた場合のみ報酬対象外（Issue #9 代表回答 9-2）。
        // ちょうど閾値と等しい場合は報酬対象のまま（境界の扱いを明記する。
        // `speed_check_test.dart` 「境界付近の扱いが決定論的」で検証）。
        rewardEligible: smoothedSpeedKmh <= thresholdKmh,
      ));
    }

    return results;
  }
}

/// [SpeedFilter.classify] が返す、1区間（隣接する2つの [GeoPosition] の間）分の判定結果。
class SpeedSegment {
  const SpeedSegment({
    required this.from,
    required this.to,
    required this.rawSpeedKmh,
    required this.smoothedSpeedKmh,
    required this.rewardEligible,
  });

  /// 区間の始点。
  final GeoPosition from;

  /// 区間の終点。
  final GeoPosition to;

  /// この区間だけの生（平滑化前）の速度〔km/h〕。
  ///
  /// **判定（[rewardEligible]）には使わない。** マルチパスのスパイクをそのまま
  /// 反映するため、都市部では容易に非現実的な値になりうる（診断・テスト用途のみ。
  /// `speed_check_test.dart` の「平滑化なしだと誤検出する」で使用）。
  final double rawSpeedKmh;

  /// 移動平均（[SpeedFilter.smoothingWindow]）で平滑化した後の速度〔km/h〕。
  ///
  /// [rewardEligible] はこの値のみを見て決める。
  final double smoothedSpeedKmh;

  /// この区間が報酬（資材付与・開拓）の対象か。
  ///
  /// false は「不正」の烙印ではなく、単に「この区間は徒歩相当の速度ではなかった
  /// ので報酬対象外」という意味（Issue #9 代表回答 9-2「不正扱いはせず、単に
  /// 報酬対象外にするだけ」）。呼び出し側は false を BAN やペナルティの根拠に
  /// 使ってはならない。
  final bool rewardEligible;

  @override
  bool operator ==(Object other) =>
      other is SpeedSegment &&
      other.from == from &&
      other.to == to &&
      other.rawSpeedKmh == rawSpeedKmh &&
      other.smoothedSpeedKmh == smoothedSpeedKmh &&
      other.rewardEligible == rewardEligible;

  @override
  int get hashCode => Object.hash(from, to, rawSpeedKmh, smoothedSpeedKmh, rewardEligible);

  @override
  String toString() => 'SpeedSegment(from: $from, to: $to, raw: ${rawSpeedKmh}km/h, '
      'smoothed: ${smoothedSpeedKmh}km/h, rewardEligible: $rewardEligible)';
}

/// 移動平均の窓に保持する、生の区間データ（距離・区間開始時刻のみ）。
class _RawSegment {
  const _RawSegment({required this.startTimestamp, required this.distanceMeters});

  final DateTime startTimestamp;
  final double distanceMeters;
}

/// 地球を半径 [_earthRadiusMeters] の球とみなす Haversine 公式による2点間距離〔m〕。
///
/// GPS_ARCHITECTURE 準拠: 緯度経度は [GeoPosition] が既に公開している値であり、
/// GPS/地図SDKの型・APIには一切依存しない純粋な球面幾何計算である。
/// 高度差は考慮しない（[GeoPosition] が高度を保持しないため。徒歩程度の高度差は
/// 数十m規模の水平距離に対して無視できるスケール）。
const double _earthRadiusMeters = 6371000.0;

double _haversineMeters(GeoPosition a, GeoPosition b) {
  final lat1 = a.latitude * math.pi / 180.0;
  final lat2 = b.latitude * math.pi / 180.0;
  final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
  final dLon = (b.longitude - a.longitude) * math.pi / 180.0;

  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return _earthRadiusMeters * c;
}

/// [distanceMeters] を [elapsed] で割った速度〔km/h〕。[elapsed] は正であること
/// （呼び出し側で保証する）。
double _kmh(double distanceMeters, Duration elapsed) {
  final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  final metersPerSecond = distanceMeters / seconds;
  return metersPerSecond * 3.6;
}
