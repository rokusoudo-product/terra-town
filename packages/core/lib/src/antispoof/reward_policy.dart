import 'dart:collection';
import 'dart:math' as math;

import '../position/geo_position.dart';
import '../position/tracking_session.dart';
import 'speed_filter.dart';

/// GPS 偽装対策（Issue #9）の段階的ペナルティを1か所に集約する判定
/// （Issue #126・T099・T101）。
///
/// ## 何のための型か
/// Issue #9 代表回答 9-1 は3段階のペナルティを定義している:
///
/// | 検出 | 挙動 |
/// |---|---|
/// | モック位置検出 | 開拓・資材付与を**無効化** |
/// | 速度超過（時速10km超・[SpeedFilter]・Issue #125） | その区間だけ報酬なし |
/// | 速度/歩数の不一致（本 Issue・T101） | 付与レートを**低下**（無効化ではない） |
///
/// これらが別々の呼び出し側でバラバラに判定されると、将来どこかの経路だけ実装が
/// ずれて一貫性が崩れる（Issue #126 本文「判定を1か所に集めること」）。本クラスは
/// [SpeedFilter]（速度）と歩数センサー突合（本ファイルで新規実装）の両方を合成し、
/// 呼び出し側（`DisclosureService`・将来の資材付与処理）が単一の窓口から
/// 判定を得られるようにする。
///
/// ## 開拓を止めるのはモックだけ（Issue #126 本文・重要）
/// [allowsDisclosure] は **[GeoPosition.spoofSuspected] のみ**を見る。速度超過・
/// 歩数不一致は「開拓」自体は止めない（`plan.md` §9・Issue #9 の表のとおり、
/// この2つは「報酬（資材付与）」側のみに作用する）。位置ごとの単純なゲートに
/// とどめ、[classify] が行うウィンドウ判定（速度・歩数）を [allowsDisclosure]・
/// `DisclosureService` には一切持ち込まない。
///
/// ## [classify] はセッションをまたがない
/// [GeoPosition.trackingSessionId] が変わる境界（[splitByTrackingSession]）は
/// `elapsedRealtime` の連続性が切れる境界であり、ここをまたいで速度・歩数の
/// ウィンドウを計算すると意味のない値になる（`docs/location-track-db.md` §5）。
/// 本クラスは必ずセッション単位に分割してから内部のウィンドウ判定を行う。
///
/// ## [SpeedFilter] は書き直さない（Issue #126 本文の明示的な指示）
/// 速度による報酬対象外化は既に [SpeedFilter]（Issue #125）が実装済みであり、
/// 本クラスは**その出力を合成するだけ**で [SpeedFilter] 自体には一切手を入れない。
///
/// ## モック位置を速度・歩数のウィンドウ計算に混ぜない（Issue #126 本文）
/// モック位置（テレポート）を [SpeedFilter] の移動平均窓や歩数突合のウィンドウに
/// 混ぜてしまうと、その1点だけで実際には起きていない急加速・急減速が計算に
/// 混入し、**モックの前後にある正規の歩行区間まで巻き添えで報酬対象外になる**
/// （advisor 指摘）。そのため [classify] は、セッション内をさらに
/// 「[GeoPosition.spoofSuspected] が連続して false である最大区間（run）」に
/// 分割し、[SpeedFilter]・歩数ウィンドウのどちらも run 単位でのみ実行する。
/// [GeoPosition.spoofSuspected] が true の点そのものが端点になる区間は
/// [RewardSegmentReason.mockSuspected]（倍率0）として run の外で個別に扱う。
///
/// ## 歩数突合（T101）の設計
/// 歩数センサー（`TYPE_STEP_COUNTER`）は起動後の累積値で、Android は
/// バッチ配送（`maxReportLatencyUs`）や OS 側の遅延で**数秒〜十数秒単位のまとめ
/// 配送になりうる**（Kotlin 側は `maxReportLatencyUs=0` を指定して最小化を試みるが
/// 保証ではない。`LocationTrackingService` のドキュメント参照）。距離しきい値
/// 15m（約10〜20秒相当）の1区間だけで歩数差分を見ると、たまたま歩数イベントが
/// 届く前の区間で `stepDelta == 0` になり、正規の歩行を誤検出しうる。
///
/// そのため本クラスは [SpeedFilter] と同じ考え方（サンプル件数ではなく時間長の
/// 窓）を歩数突合にも適用する。既定窓幅は [SpeedFilter.smoothingWindow] と
/// **同じ値**（既定120秒）を使う。速度・歩数という別々の判定が別々の時間基準を
/// 持つと「どちらの窓で見た時点の状態か」が説明しづらくなるため、時間基準を
/// 1つに統一する。
///
/// ### 罰しない側に倒す4条件（Issue #126 本文・要求どおり）
/// 歩数ウィンドウが次のいずれかに該当する場合、そのウィンドウの末尾区間は
/// 歩数突合による倍率低下を**適用しない**（倍率1）:
///
/// 1. ウィンドウ内のいずれかの区間で、端点のどちらかの
///    [GeoPosition.cumulativeStepCount] が null（センサー無し・権限無し・
///    未取得）。
/// 2. ウィンドウ内のいずれかの区間で歩数が減少している（端末再起動等。
///    `elapsedRealtime` はセッション内で単調増加するが、歩数センサーの
///    累積値は OS 再起動やセンサーのリセットで巻き戻りうるため、
///    「不明」として扱い罰しない）。
/// 3. ウィンドウの合計移動距離が [minWindowDistanceMeters] 未満
///    （静止・短距離では判定しない。GPS の精度ゲート＝30m
///    〔`LocationSamplingPolicy.maxAcceptedAccuracyMeters`〕の揺れだけで
///    誤検出しないための下限。既定100mは、徒歩（時速5km）で約72秒相当＝
///    精度ゲート30mの2点分〔往復60m相当〕を明確に上回る）。
/// 4. 区間が既に速度超過で倍率0（[SpeedFilter.rewardEligible] が false）。
///    既に無効化されている区間に歩数不一致の判定を重ねて二重に扱わない
///    （[classify] 側の制御。本条件はウィンドウ計算そのものには現れない）。
///
/// 上記のいずれにも該当しない場合のみ、「歩数 × [maxStrideMeters]（歩幅上限・
/// 余裕を持った値）」で説明できる距離を、実際の移動距離が上回るかを判定する。
/// 上回る場合のみ [stepMismatchMultiplier]（**0ではない**穏やかな倍率）を返す。
///
/// ### 閾値の根拠（正本は `specs/001-mvp/balance.csv`・Issue #36・T106・未作成）
/// 以下はいずれも本実装が採用した**仮の値**であり、実機検証（`tasks.md` T017・
/// R5「正規歩行で報酬没収が起きないことの確認」）で見直すことを前提とする。
/// `balance.csv` 作成時はそちらへ移すこと。
///
/// - [maxStrideMeters]（既定 1.5m）: [SpeedFilter.defaultThresholdKmh]
///   （時速10km）を超えた区間は既に速度超過として別扱いになるため、歩数突合が
///   実際に判定する範囲は「時速10km以下」。仮に2歩/秒（早歩き〜小走りの
///   ケイデンス）とすると、時速10km（≈2.78m/s）を2歩/秒で割ると1歩あたり
///   約1.39mになる。これに、歩幅の個人差（長身の早歩き）・歩数センサーの
///   遅延で一時的に歩数が「追いついていない」状態を過大評価しないための余裕を
///   加え、**1.5m**とした（1.39mから約8%の上乗せ）。
/// - [minWindowDistanceMeters]（既定 100m）: 上記クラスdoc「4条件」の3参照。
/// - [stepMismatchMultiplier]（既定 0.5）: Issue #126 本文「0にはしない穏やかな
///   倍率」の要求を満たす仮の値。半減とした根拠は「不正の確信が低い
///   （閾値超過はしているが歩数センサーの精度自体が高くないため）ため、
///   無効化に近い強いペナルティは避ける」という判断であり、確たる実測根拠は
///   まだない。
///
/// ### 歩数判定そのものを無効化する設定（Issue #135・自己申告オプトアウト）
/// 車いす・時速10km未満の自転車など、**歩数がほぼ出ない正規の移動手段**の利用者は、
/// 上記の判定だけでは正規の移動でも歩数不一致（倍率0.5）が継続的にかかってしまう
/// （代表要望・2026-09-11）。代表決定は「自動判定ではなく自己申告の設定」（車いすと
/// ジョイスティックによる位置偽装を区別できないため）。[useStepCheck] を `false`
/// にすると、[classify] は本クラスdoc「歩数突合（T101）の設計」の判定を一切行わず
/// （[stepMismatchMultiplier] を返すことはなく [RewardSegmentReason.stepMismatch] も
/// 出ない）、当該区間は歩数の観点では倍率1として扱う。
///
/// **①モック位置検出（[allowsDisclosure]）・②速度判定（[SpeedFilter]・時速10km超）は
/// [useStepCheck] の値に関わらず常に適用する**（電動車いすも時速6km以下のため
/// 速度判定には掛からない）。自己申告のため誰でも歩数判定を回避できるが、MVP の
/// 脅威モデル（チートの被害者は本人のみ・`plan.md` §9）では許容する
/// （`specs/001-mvp/spec.md` NFR-5・`plan.md` §9 参照）。
///
/// この値の永続化・UI（設定タブのスイッチ）は `packages/location`
/// （`RewardSettingsRepository`）・`app`（設定画面）側の責務であり、本クラスは
/// 単純な bool を受け取るだけで、Drift・Flutter・設定の保存方法を一切知らない
/// （`tools/check_import_direction.sh`）。実際の資材付与処理（`classify` の結果を
/// 使って付与量を計算する処理）はまだ存在しない（tasks.md T068）ため、本設定が
/// 実際の付与に効くのは T068 の実装後になる。
///
/// **最終調整は `tasks.md` T017（代表の実機スパイク）で行う**（Issue #126 本文）。
class RewardPolicy {
  RewardPolicy({
    SpeedFilter? speedFilter,
    Duration? stepWindow,
    this.minWindowDistanceMeters = defaultMinWindowDistanceMeters,
    this.maxStrideMeters = defaultMaxStrideMeters,
    this.stepMismatchMultiplier = defaultStepMismatchMultiplier,
    this.useStepCheck = true,
  })  : speedFilter = speedFilter ?? SpeedFilter(),
        stepWindow = stepWindow ?? (speedFilter ?? SpeedFilter()).smoothingWindow,
        assert(minWindowDistanceMeters >= 0, '最小ウィンドウ距離は非負でなければならない'),
        assert(maxStrideMeters > 0, '歩幅上限は正の値でなければならない'),
        assert(
          stepMismatchMultiplier > 0 && stepMismatchMultiplier < 1,
          '歩数不一致の倍率は0より大きく1未満でなければならない'
          '（0は無効化＝別のペナルティ段階、1は「不一致なし」と区別がつかなくなるため）',
        );

  /// 速度超過判定（Issue #125）。**書き直さず、出力（[SpeedSegment.rewardEligible]）
  /// を合成するだけ**（クラスdoc参照）。
  final SpeedFilter speedFilter;

  /// 歩数突合に使う移動窓の時間長。既定は [speedFilter] の
  /// [SpeedFilter.smoothingWindow] と同じ値（クラスdoc「歩数突合の設計」参照）。
  final Duration stepWindow;

  /// このウィンドウ内の合計移動距離未満では歩数突合の判定を行わない〔m〕。
  static const double defaultMinWindowDistanceMeters = 100.0;
  final double minWindowDistanceMeters;

  /// 「歩数 × この値」で説明できる距離とみなす歩幅上限〔m〕。
  static const double defaultMaxStrideMeters = 1.5;
  final double maxStrideMeters;

  /// 歩数不一致と判定された区間に適用する倍率（0<倍率<1・無効化ではない）。
  static const double defaultStepMismatchMultiplier = 0.5;
  final double stepMismatchMultiplier;

  /// 歩数突合そのものを行うか（既定 `true`＝使う）。`false` にすると
  /// [classify] は歩数不一致（[RewardSegmentReason.stepMismatch]）を一切出さない
  /// （クラスdoc「歩数判定そのものを無効化する設定」参照・Issue #135）。
  /// モック位置検出（[allowsDisclosure]）・速度判定（[SpeedFilter]）はこの値に
  /// 関わらず常に適用される。
  final bool useStepCheck;

  /// この観測地点で開拓（[DisclosedHex] の生成・霧を晴らす処理）を行ってよいか。
  ///
  /// **モック位置検出（[GeoPosition.spoofSuspected]）のみを見る**（クラスdoc
  /// 「開拓を止めるのはモックだけ」参照）。速度・歩数はここでは判定しない。
  /// `static` にしてあるのは、この規則を [RewardPolicy] のインスタンス化なしに
  /// `DisclosureService` 側から直接呼べるようにするため（規則の重複防止。
  /// クラスdoc参照）。
  static bool allowsDisclosure(GeoPosition position) => !position.spoofSuspected;

  /// 位置の列（1つ以上のセッションを含んでよい）を処理し、隣接する2点ごとの
  /// 区間について資材付与レートの倍率を返す。
  ///
  /// 返り値の長さ・意味は [SpeedFilter.classify] と同様、セッション内で
  /// `positions.length - 1` 件になる（セッション境界・[GeoPosition.spoofSuspected]
  /// の run 境界をまたいだ区間は作らない。クラスdoc「モック位置を...混ぜない」
  /// 参照）。
  List<RewardSegment> classify(List<GeoPosition> positions) {
    final results = <RewardSegment>[];
    for (final session in splitByTrackingSession(positions)) {
      results.addAll(_classifySession(session));
    }
    return results;
  }

  List<RewardSegment> _classifySession(List<GeoPosition> session) {
    final n = session.length;
    if (n < 2) {
      return const [];
    }

    final results = List<RewardSegment?>.filled(n - 1, null);

    // 1. 端点のどちらかが spoofSuspected な区間は、run 分割の外で先に確定する
    //    （SpeedFilter・歩数ウィンドウのどちらにも混ぜない。クラスdoc参照）。
    for (var k = 0; k < n - 1; k++) {
      final from = session[k];
      final to = session[k + 1];
      if (from.spoofSuspected || to.spoofSuspected) {
        results[k] = RewardSegment(
          from: from,
          to: to,
          multiplier: 0.0,
          reason: RewardSegmentReason.mockSuspected,
          distanceMeters: _haversineMeters(from, to),
        );
      }
    }

    // 2. spoofSuspected が false な点だけの最大連続区間（run）ごとに
    //    SpeedFilter・歩数ウィンドウを実行する。
    var i = 0;
    while (i < n) {
      if (session[i].spoofSuspected) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < n && !session[j + 1].spoofSuspected) {
        j++;
      }
      if (j > i) {
        final run = session.sublist(i, j + 1);
        final speedSegments = speedFilter.classify(run);
        // Issue #135: useStepCheck が false なら歩数突合そのものをスキップし、
        // 全区間を「不一致なし」（倍率1）として扱う（速度判定は下の
        // speedSegment.rewardEligible 分岐でこれまでどおり別途適用される）。
        final stepMultipliers = useStepCheck
            ? _stepWindowMultipliers(run)
            : List<double>.filled(speedSegments.length, 1.0);
        for (var s = 0; s < speedSegments.length; s++) {
          final k = i + s;
          final speedSegment = speedSegments[s];
          final distanceMeters = _haversineMeters(speedSegment.from, speedSegment.to);
          if (!speedSegment.rewardEligible) {
            // 4条件のうち条件4: 既に速度超過で倍率0の区間には歩数判定を重ねない。
            results[k] = RewardSegment(
              from: speedSegment.from,
              to: speedSegment.to,
              multiplier: 0.0,
              reason: RewardSegmentReason.overSpeed,
              distanceMeters: distanceMeters,
              speedSegment: speedSegment,
            );
          } else {
            final stepMultiplier = stepMultipliers[s];
            results[k] = RewardSegment(
              from: speedSegment.from,
              to: speedSegment.to,
              multiplier: stepMultiplier,
              reason: stepMultiplier < 1.0
                  ? RewardSegmentReason.stepMismatch
                  : RewardSegmentReason.none,
              distanceMeters: distanceMeters,
              speedSegment: speedSegment,
            );
          }
        }
      }
      i = j + 1;
    }

    return results.map((segment) => segment!).toList(growable: false);
  }

  /// [run]（spoofSuspected が全て false な連続区間）について、隣接区間ごとの
  /// 歩数突合による倍率を返す（長さは `run.length - 1`）。
  ///
  /// クラスdoc「歩数突合の設計」の移動窓・4条件をそのまま実装する。
  List<double> _stepWindowMultipliers(List<GeoPosition> run) {
    final n = run.length;
    if (n < 2) {
      return const [];
    }

    final results = <double>[];
    final window = Queue<_StepRawSegment>();
    var windowDistanceMeters = 0.0;
    var windowStepDelta = 0;
    // ウィンドウ内に歩数不明（4条件の1・2）な区間が1つでもあれば、
    // ウィンドウ全体を「判定不能＝罰しない」として扱う（クラスdoc参照）。
    var unknownStepCountInWindow = 0;

    for (var i = 1; i < n; i++) {
      final from = run[i - 1];
      final to = run[i];
      final distanceMeters = _haversineMeters(from, to);

      final fromSteps = from.cumulativeStepCount;
      final toSteps = to.cumulativeStepCount;
      int? stepDelta;
      if (fromSteps == null || toSteps == null || toSteps < fromSteps) {
        // 条件1（null）・条件2（減少＝端末再起動等）はどちらも「不明」として扱う。
        stepDelta = null;
      } else {
        stepDelta = toSteps - fromSteps;
      }

      final segment = _StepRawSegment(
        startTimestamp: from.timestamp,
        distanceMeters: distanceMeters,
        stepDelta: stepDelta,
      );
      window.addLast(segment);
      windowDistanceMeters += distanceMeters;
      windowStepDelta += stepDelta ?? 0;
      if (stepDelta == null) unknownStepCountInWindow++;

      while (window.length > 1 &&
          to.timestamp.difference(window.first.startTimestamp) > stepWindow) {
        final dropped = window.removeFirst();
        windowDistanceMeters -= dropped.distanceMeters;
        windowStepDelta -= dropped.stepDelta ?? 0;
        if (dropped.stepDelta == null) unknownStepCountInWindow--;
      }

      double multiplier;
      if (unknownStepCountInWindow > 0) {
        multiplier = 1.0; // 条件1・2
      } else if (windowDistanceMeters < minWindowDistanceMeters) {
        multiplier = 1.0; // 条件3
      } else {
        final explainableDistanceMeters = windowStepDelta * maxStrideMeters;
        multiplier = windowDistanceMeters <= explainableDistanceMeters
            ? 1.0
            : stepMismatchMultiplier;
      }
      results.add(multiplier);
    }

    return results;
  }
}

/// [RewardPolicy.classify] が1区間ごとに倍率を返した理由。
enum RewardSegmentReason {
  /// 不一致なし・報酬は満額（倍率1）。
  none,

  /// 端点のいずれかがモック位置の疑いあり（倍率0）。
  mockSuspected,

  /// 平滑化後の速度が閾値を超過（[SpeedFilter]・Issue #125。倍率0）。
  overSpeed,

  /// 歩数と移動距離の不一致（倍率は0より大きく1未満）。
  stepMismatch,
}

/// [RewardPolicy.classify] が返す、1区間（隣接する2つの [GeoPosition] の間）
/// 分の資材付与レート判定結果。
class RewardSegment {
  const RewardSegment({
    required this.from,
    required this.to,
    required this.multiplier,
    required this.reason,
    required this.distanceMeters,
    this.speedSegment,
  });

  /// 区間の始点。
  final GeoPosition from;

  /// 区間の終点。
  final GeoPosition to;

  /// この区間の資材付与レート倍率（0.0〜1.0）。呼び出し側（将来の資材付与処理）は
  /// この値を付与量に掛ける想定（付与処理そのものは本 Issue のスコープ外・
  /// Issue #126 本文「付与処理そのものを作らないこと」）。
  final double multiplier;

  /// [multiplier] がその値になった理由（デバッグ・テスト可読性のため）。
  final RewardSegmentReason reason;

  /// [from] から [to] までの移動距離〔m〕（Haversine公式・本ファイル末尾の
  /// [_haversineMeters]）。
  ///
  /// ## 追加した理由（Issue #143・T063）
  /// 開放ポイントの歩行距離換算（`docs/opening_points.md` §2.2・
  /// `computeOpeningPointAccrual`）は区間ごとの移動距離が必要になる。
  /// [_haversineMeters] は本ファイル（[_stepWindowMultipliers]）と
  /// `speed_filter.dart`（[SpeedFilter]）に**既に意図的に重複定義されている**
  /// （両ファイルのクラスdoc「距離計算」参照。[SpeedFilter] を書き直さない
  /// 方針のため公開APIへの昇格ではなく重複を選んだ経緯がある）。本フィールドは
  /// その**3つ目の重複を作らず**、[_classifySession] が既に構築できる値を
  /// 呼び出し側へ公開するだけの変更である（呼び出し側〔`app` の
  /// `OpeningPointAccrualCoordinator`〕が改めて距離計算を持つ必要が無くなる）。
  final double distanceMeters;

  /// この区間の [SpeedFilter] 判定結果（診断用途）。[from]/[to] のいずれかが
  /// [GeoPosition.spoofSuspected] な区間では [SpeedFilter] を呼ばないため null。
  final SpeedSegment? speedSegment;

  @override
  bool operator ==(Object other) =>
      other is RewardSegment &&
      other.from == from &&
      other.to == to &&
      other.multiplier == multiplier &&
      other.reason == reason &&
      other.distanceMeters == distanceMeters &&
      other.speedSegment == speedSegment;

  @override
  int get hashCode =>
      Object.hash(from, to, multiplier, reason, distanceMeters, speedSegment);

  @override
  String toString() => 'RewardSegment(from: $from, to: $to, multiplier: $multiplier, '
      'reason: $reason, distanceMeters: $distanceMeters)';
}

/// 歩数突合の移動窓に保持する、生の区間データ。
class _StepRawSegment {
  const _StepRawSegment({
    required this.startTimestamp,
    required this.distanceMeters,
    required this.stepDelta,
  });

  final DateTime startTimestamp;
  final double distanceMeters;

  /// null は「不明」（[RewardPolicy] クラスdoc「4条件」の1・2）。
  final int? stepDelta;
}

/// 地球を半径 [_earthRadiusMeters] の球とみなす Haversine 公式による2点間距離〔m〕。
///
/// `speed_filter.dart` の同名の private 関数と**意図的に重複させている**
/// （[SpeedFilter] は書き直さない・クラスdoc参照。Dart の private
/// 〔先頭アンダースコア〕はファイル単位＝ライブラリ単位のスコープであり、
/// 別ファイルからは参照できないため、共有するには公開APIに昇格させるか
/// 重複させるかの選択になる。既存の [SpeedFilter] の公開APIを変更したくないため
/// 重複を選んだ）。
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
