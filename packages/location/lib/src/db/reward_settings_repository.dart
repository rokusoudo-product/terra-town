import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import 'game_database.dart';

/// 歩数判定オプトアウト設定（Issue #135）の読み書きが従うインターフェース。
///
/// `app` 側（設定画面）はこの抽象だけに依存させ、Drift・`GameDatabase` を直接
/// 知らないようにする。これにより設定画面の単体テストでは保存失敗を再現できる
/// フェイクを注入できる（実際の `settings` テーブル・インメモリDB では
/// 意図的に保存を失敗させる状況を作りにくいため）。
abstract interface class RewardSettingsStore {
  /// 「歩数による判定を使わない」がオンかどうか。既定（未保存＝行が無い）は
  /// `false`（歩数判定を使う。Issue #135 起票時の代表決定）。
  Future<bool> isStepCheckDisabled();

  /// 「歩数による判定を使わない」の値を保存する。
  Future<void> setStepCheckDisabled(bool value);
}

/// [RewardSettingsStore] の本番実装（`settings` テーブル・T034 に保存する）。
///
/// 出典: Issue #135「設定の保存」節。**スキーマ変更は行わない**
/// （既存の key-value `settings` テーブルをそのまま使う）。
///
/// ## キーと値のエンコード
/// キーは [stepCheckDisabledKey]（`reward.step_check_disabled`）に固定する。
/// `Settings.value` は TEXT 列（[GameDatabase] の `Settings` テーブルdoc「複合的な
/// 値は呼び出し側が JSON 文字列にエンコードする」）のため、本クラスは
/// `bool` を `jsonEncode`/`jsonDecode`（`"true"` / `"false"`）でエンコードする。
/// 行が存在しない場合、および値が `"true"`/`"false"` のどちらとしても解釈できない
/// 場合（データ破損等）は、いずれも「不明」として**罰しない側＝歩数判定を使う
/// （`false`）** に倒す（`RewardPolicy` クラスdoc「罰しない側に倒す」と同じ方針）。
///
/// ## Kotlin から開かないこと（Issue #131 の一般ルール）
/// 本クラスが読み書きする `game_state.sqlite` は Dart（Drift）専用であり、
/// Kotlin 側から同じファイルを開いてはならない。Kotlin の歩数記録
/// （`location_track.sqlite`・別ファイル）はこの設定と無関係に従来どおり続く。
/// 判定を外すのは `core`（[RewardPolicy.useStepCheck]）側の責務であり、
/// センサー自体の記録は止めない。
///
/// ## T068 との境界
/// 本クラスは設定値の永続化・[RewardPolicy] への橋渡し（[buildRewardPolicy]）
/// までを提供する。実際の資材付与処理（`classify` の結果を使って付与量を
/// 計算する処理）はまだ存在しない（tasks.md T068）ため、ここで用意した
/// [RewardPolicy] が実際の付与に効くのは T068 の実装後になる。
class RewardSettingsRepository implements RewardSettingsStore {
  RewardSettingsRepository(this._database);

  final GameDatabase _database;

  /// `settings.key` に保存するキー名（Issue #135）。
  static const String stepCheckDisabledKey = 'reward.step_check_disabled';

  @override
  Future<bool> isStepCheckDisabled() async {
    final row = await (_database.select(_database.settings)
          ..where((t) => t.key.equals(stepCheckDisabledKey)))
        .getSingleOrNull();
    if (row == null) return false; // 既定はオフ（歩数判定を使う）。

    try {
      final decoded = jsonDecode(row.value);
      if (decoded is bool) return decoded;
    } on FormatException {
      // 解釈不能な値は「不明」として罰しない側（false）に倒す。
    }
    return false;
  }

  @override
  Future<void> setStepCheckDisabled(bool value) async {
    await _database.into(_database.settings).insertOnConflictUpdate(
          SettingsCompanion(
            key: const Value(stepCheckDisabledKey),
            value: Value(jsonEncode(value)),
            updatedAt: Value(DateTime.now()),
          ),
        );
  }

  /// 保存済みの設定値を読み、[RewardPolicy] に渡せる状態にして返す
  /// （Issue #135「配線」節）。実際に資材付与へ反映するのは T068 側の責務。
  Future<RewardPolicy> buildRewardPolicy() async {
    final disabled = await isStepCheckDisabled();
    return rewardPolicyFor(stepCheckDisabled: disabled);
  }
}

/// 「歩数判定を使わない」設定値（bool）から [RewardPolicy] を組み立てる純粋関数。
///
/// [RewardSettingsRepository.buildRewardPolicy] から使うほか、テストや将来の
/// 呼び出し側が非同期のDB読み出しを経由せず組み立てたい場合にも使える。
RewardPolicy rewardPolicyFor({required bool stepCheckDisabled}) {
  return RewardPolicy(useStepCheck: !stepCheckDisabled);
}
