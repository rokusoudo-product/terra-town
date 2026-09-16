import 'dart:async';

import 'package:flutter/material.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

import '../../design/spacing.dart';
import '../inventory/inventory_screen.dart';

/// 建設タブ本体（Issue #192・T089）。
///
/// DESIGN.md「画面一覧と状態」の建設行（目的=開示ヘクス〔空き地〕に建物を
/// 建てる／主要アクション=建物を建設／空=建設可能地なし／エラー=資材不足を明示）
/// に沿って、8種の建物をカードで並べ、それぞれに建設コスト（木・石・鉄）と、
/// 所持資材で足りるかを表示する（Issue #192 本文「1. 建設タブ」）。
///
/// ## 今の [InventoryScreen]（所持資材の表示）は残す（Issue #192 本文）
/// Issue #150（T076）で建設タブに置かれた [InventoryScreen] は削除せず、
/// 本ウィジェットの下半分にそのまま埋め込む。新しい Repository・表示ロジックは
/// 作らず、[InventoryScreen] を渡された [inventoryRepository] でそのまま使う
/// （`InventoryScreen` クラスdoc「読み取りは既存の `InventoryRepository` のみ」と
/// 同じ方針をここでも踏襲する）。
///
/// ## 建物カードの資材読み取りは独立したポーリング（[InventoryScreen] とは別経路）
/// 建物カードの「所持資材で足りるか」の判定にも所持資材が要るが、
/// [InventoryScreen] は自分の State に閉じた非公開のポーリングであり、外部から
/// 参照できない（`inventory_screen.dart` クラスdoc「更新方式」参照）。
/// そのため本ウィジェットは同じ [InventoryRepository.readAll] を**別途**
/// 定期ポーリングする（2重読み取りにはなるが、`readAll` は軽量なSQLite
/// クエリであり、MVPの規模では実害がない）。
///
/// ## 建物を選ぶと地図タブへの遷移を呼び出し側に委ねる
/// 本ウィジェットはタブ切り替え自体を行わない（`RootScaffold` の責務）。
/// [onSelectBuildingToPlace] を呼ぶだけで、実際の
/// `BuildSelectionController.select` 呼び出し・タブ切り替えは
/// `main.dart` の `RootScaffold` が行う（`build_selection_controller.dart`
/// クラスdoc「タブ切り替えをまたいで状態を持ち回す理由」参照）。
class BuildScreen extends StatefulWidget {
  const BuildScreen({
    super.key,
    required this.inventoryRepository,
    required this.onSelectBuildingToPlace,
    this.refreshInterval = const Duration(seconds: 2),
  });

  /// 資材の所持数の読み取り先（本番では `InventoryRepository(gameDatabase)`）。
  final InventoryRepository inventoryRepository;

  /// 建てられる建物のカードをタップした際に呼ぶ。
  final ValueChanged<BuildingType> onSelectBuildingToPlace;

  /// 建物カードの資材表示を更新する定期ポーリングの間隔。
  final Duration refreshInterval;

  @override
  State<BuildScreen> createState() => _BuildScreenState();
}

class _BuildScreenState extends State<BuildScreen> {
  Map<Resource, int> _inventory = const {};
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    _refreshTimer = Timer.periodic(widget.refreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final inventory = await widget.inventoryRepository.readAll();
      if (!mounted) return;
      setState(() => _inventory = inventory);
    } catch (_) {
      // InventoryScreen 側で読み込みエラー表示を担うため、本ウィジェット側は
      // 握りつぶして次回のポーリングに委ねる（`InventoryScreen._refreshSilently`
      // と同じ方針）。
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          flex: 3,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              Text('建物を選ぶ', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '建てたい建物を選ぶと、地図で建てる場所を選べます。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.md),
              for (final spec in buildingSpecs)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _BuildingCard(
                    spec: spec,
                    inventory: _inventory,
                    onTap: () =>
                        widget.onSelectBuildingToPlace(spec.buildingType),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          flex: 2,
          child: InventoryScreen(
            inventoryRepository: widget.inventoryRepository,
          ),
        ),
      ],
    );
  }
}

/// 建物カード1件ぶんの表示情報（`docs/buildings.md` §2 の3系統8種）。
class BuildingSpec {
  const BuildingSpec({
    required this.buildingType,
    required this.label,
    required this.icon,
  });

  final BuildingType buildingType;
  final String label;
  final IconData icon;
}

/// `docs/buildings.md` §2 の掲載順（住宅系→生産系→娯楽系）と同じ順で並べる。
const buildingSpecs = <BuildingSpec>[
  BuildingSpec(
    buildingType: BuildingType.house,
    label: '住宅',
    icon: Icons.home_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.apartment,
    label: 'マンション',
    icon: Icons.apartment_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.cropField,
    label: '畑',
    icon: Icons.agriculture_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.livestockFarm,
    label: '農場',
    icon: Icons.pets_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.factoryBuilding,
    label: '工場',
    icon: Icons.factory_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.quarry,
    label: '採石場',
    icon: Icons.landscape_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.resort,
    label: 'リゾート',
    icon: Icons.beach_access_outlined,
  ),
  BuildingSpec(
    buildingType: BuildingType.museum,
    label: 'ミュージアム',
    icon: Icons.museum_outlined,
  ),
];

class _BuildingCard extends StatelessWidget {
  const _BuildingCard({
    required this.spec,
    required this.inventory,
    required this.onTap,
  });

  final BuildingSpec spec;
  final Map<Resource, int> inventory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cost = buildingConstructionCostLv1[spec.buildingType]!;

    // 資材の過不足判定は core の missingResourcesFor をそのまま使う
    // （UI側で判定ロジックを再実装しない。`BuildableHexEvaluator`・
    // `BuildingConstructionService` と同じ考え方の判定を共有する）。
    final heldInventory = Inventory();
    for (final entry in inventory.entries) {
      heldInventory.add(entry.key, entry.value);
    }
    final missing = missingResourcesFor(cost, heldInventory);
    final canAfford = missing.isEmpty;

    final iconColor = canAfford
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      child: InkWell(
        onTap: canAfford ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Icon(spec.icon, color: iconColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(spec.label, style: theme.textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(_costLabel(cost), style: theme.textTheme.bodySmall),
                    if (!canAfford) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _missingLabel(missing),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (canAfford)
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 建設系資材の日本語ラベル（`inventory_screen.dart` の `_labelFor` と同じ
/// 対応表だが、あちらは private のため共有できず個別に持つ。同ファイルの
/// コメントと同じ理由）。建設コストは建設系資材（木・石・鉄）のみを使うため
/// （`docs/buildings.md` §4.1）、本関数は3種のみを扱う。
String _resourceLabel(Resource resource) => switch (resource) {
  Resource.wood => '木',
  Resource.stone => '石',
  Resource.iron => '鉄',
  _ => resource.name,
};

/// 建設コストの表示（例: 「必要: 木20 / 石10」）。0の資材は表示しない。
/// 常に「必要: 」を前置した1つの [Text] にまとめる——数値を裸の文字列
/// （例えば "20" だけの [Text]）にすると、`app/test/widget_test.dart`
/// 「建設タブに切り替えると資材インベントリ画面が表示される」の
/// `find.text('10')`/`find.text('50')` 等（完全一致）と偶然衝突しうるため
/// （本ウィジェットの導入で既存テストを壊さないための意図的な設計判断）。
String _costLabel(BuildingCost cost) {
  final parts = <String>[
    if (cost.wood > 0) '木${cost.wood}',
    if (cost.stone > 0) '石${cost.stone}',
    if (cost.iron > 0) '鉄${cost.iron}',
  ];
  return '必要: ${parts.join(' / ')}';
}

/// 不足資材の表示（例: 「不足: 木15 / 石10」）。[_costLabel] と同じ理由で
/// 常に1つの [Text] にまとめる。
String _missingLabel(Map<Resource, int> missing) {
  final parts = <String>[
    for (final resource in const [Resource.wood, Resource.stone, Resource.iron])
      if (missing[resource] != null)
        '${_resourceLabel(resource)}${missing[resource]}',
  ];
  return '不足: ${parts.join(' / ')}';
}
