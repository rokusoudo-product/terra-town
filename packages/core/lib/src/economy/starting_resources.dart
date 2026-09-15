import 'resource.dart';

/// チュートリアル開始時に付与する木の量（Issue #188・T116）。
///
/// 出典: `docs/tutorial.md` §2「開始時の資材」・`specs/001-mvp/spec.md` §7.1。
/// 数値の正本は `specs/001-mvp/balance.yaml` の `starting_resources.wood`
/// （Issue #36）であり、一致は `packages/core/test/balance/balance_yaml_test.dart`
/// が検証する。
const int startingResourceWoodAmount = 50;

/// チュートリアル開始時に付与する石の量（Issue #188・T116）。
///
/// 出典・正本は [startingResourceWoodAmount] と同じ（`balance.yaml` の
/// `starting_resources.stone`）。
const int startingResourceStoneAmount = 10;

/// チュートリアル開始時に付与する資材の一覧（資材種別と量の組）。
///
/// 実際の付与処理（`settings` テーブルによる1回限りの判定・`inventory` への
/// 加算）は `packages/location` の `TutorialStartingResourcesGrant` が行う
/// （`core` は GPS_ARCHITECTURE 準拠のためDB・永続化に触れない）。
const Map<Resource, int> startingResources = {
  Resource.wood: startingResourceWoodAmount,
  Resource.stone: startingResourceStoneAmount,
};
