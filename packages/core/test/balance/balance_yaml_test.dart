import 'dart:io';

import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// `specs/001-mvp/balance.yaml`（数値パラメータの正本・Issue #36）の照合テスト。
///
/// **`packages/core/lib` 本体はファイル読み込みを行わない**（GPS_ARCHITECTURE・
/// core は純粋ロジックのみという方針を維持する）。本テストだけが `dev_dependencies`
/// の `yaml` パッケージを使って balance.yaml を読み込み、`code` を持つ項目について
/// コードの定数と値が一致することを確認する（2026-09-15 代表決定コメント §2）。
///
/// `dart test` は `packages/core` をカレントディレクトリとして実行される
/// （`.github/workflows/ci.yml` の `working-directory: packages/core` 参照）ため、
/// balance.yaml へは相対パス `../../specs/001-mvp/balance.yaml` で到達する。
const _balanceYamlPath = '../../specs/001-mvp/balance.yaml';

void main() {
  late YamlMap balance;

  setUpAll(() {
    final file = File(_balanceYamlPath);
    if (!file.existsSync()) {
      fail(
        'balance.yaml が見つかりません（探索パス: $_balanceYamlPath、'
        'cwd: ${Directory.current.path}）。dart test は packages/core を'
        'カレントディレクトリとして実行すること。',
      );
    }
    balance = loadYaml(file.readAsStringSync()) as YamlMap;
  });

  group('balance.yaml の構造', () {
    test('code・status を持つ項目を1件以上収集できる', () {
      expect(_collectLeaves(balance), isNotEmpty);
    });

    test('すべての項目の status は 確定 か 仮 のいずれか', () {
      for (final leaf in _collectLeaves(balance)) {
        expect(
          leaf.status,
          anyOf('確定', '仮'),
          reason: '${leaf.path}.status が不正な値: ${leaf.status}',
        );
      }
    });

    test('unit は文字列の "null" ではない（YAMLのnull直書きの取り違え検出）', () {
      // `unit: null` は Dart の null になるべきで、うっかり `unit: "null"` と
      // 文字列で書いてしまうと _collectLeaves は気づけない（どちらも非nullの
      // 値として通ってしまう）ため、ここで明示的に弾く。
      for (final leaf in _collectLeaves(balance)) {
        expect(
          leaf.unit,
          isNot(equals('null')),
          reason:
              '${leaf.path}.unit が文字列 "null" になっている（YAMLの null を'
              '意図しているなら quote を外すこと）。',
        );
      }
    });

    test('葉（statusを持つYamlMap）の子はスカラー値のみで、YamlMap/YamlListを含まない', () {
      // _collectLeaves は「status を持つ YamlMap」を1パラメータの葉として扱い、
      // それ以上は再帰しない。もし葉の中にさらに YamlMap/YamlList が
      // 紛れ込んだ場合、その子は黙って無視され、照合漏れになる。将来
      // balance.yaml の構造を広げたときに気づけるよう、ここで検出する。
      for (final leaf in _collectLeaves(balance)) {
        final node = _findNodeByPath(balance, leaf.path);
        for (final childValue in node.values) {
          expect(
            childValue,
            isNot(isA<YamlMap>()),
            reason:
                '${leaf.path} の子に YamlMap が含まれている。'
                '_collectLeaves は葉の中を再帰しないため照合漏れになる可能性がある。',
          );
          expect(
            childValue,
            isNot(isA<YamlList>()),
            reason: '${leaf.path} の子に YamlList が含まれている（同上）。',
          );
        }
      }
    });
  });

  group('code とコードの定数の照合（2026-09-15 代表決定コメント §2）', () {
    // 建物の建設コスト（buildings.construction_cost）は8建物×3資材=24項目と
    // 数が多いため、buildingConstructionCostLv1（BuildingType -> BuildingCost）
    // から code文字列（`buildingConstructionCostLv1.<enum名>.<資材>`）と
    // 実際の値を機械的に生成する。balance.yaml 側は個別に code を手書きしている
    // （typo検出のため）が、コード側は本物の定数マップを直接読むことで
    // 二重管理を避ける（Issue #191）。
    final buildingCostActuals = <String, num>{
      for (final entry in buildingConstructionCostLv1.entries) ...{
        'buildingConstructionCostLv1.${entry.key.name}.wood': entry.value.wood,
        'buildingConstructionCostLv1.${entry.key.name}.stone':
            entry.value.stone,
        'buildingConstructionCostLv1.${entry.key.name}.iron': entry.value.iron,
      },
    };

    // code文字列 -> balance.yaml の value を、コード側の定数と同じ単位の
    // num に変換する関数。km/mm のような単位換算はここで行う。
    final conversions = <String, num Function(_BalanceLeaf leaf)>{
      'terrainYieldAmountPerHexPerUnit': (leaf) => leaf.value as num,
      'openingPointDistanceMillimetersPerPoint': (leaf) =>
          ((leaf.value as num) * 1000000).round(), // km -> mm
      'openingPointStockCap': (leaf) => leaf.value as num,
      'openingPointCostPerHex': (leaf) => leaf.value as num,
      'Inventory.defaultCap': (leaf) => leaf.value as num,
      'SpeedFilter.defaultThresholdKmh': (leaf) => leaf.value as num,
      'startingResourceWoodAmount': (leaf) => leaf.value as num,
      'startingResourceStoneAmount': (leaf) => leaf.value as num,
      'buildingUpgradeCostMultiplierLv2': (leaf) => leaf.value as num,
      'buildingUpgradeCostMultiplierLv3': (leaf) => leaf.value as num,
      for (final code in buildingCostActuals.keys)
        code: (leaf) => leaf.value as num,
    };

    // コード側の実際の値（テスト対象の定数そのものを直接参照する）。
    final actualValues = <String, num>{
      'terrainYieldAmountPerHexPerUnit': terrainYieldAmountPerHexPerUnit,
      'openingPointDistanceMillimetersPerPoint':
          openingPointDistanceMillimetersPerPoint,
      'openingPointStockCap': openingPointStockCap,
      'openingPointCostPerHex': openingPointCostPerHex,
      'Inventory.defaultCap': Inventory.defaultCap,
      'SpeedFilter.defaultThresholdKmh': SpeedFilter.defaultThresholdKmh,
      'startingResourceWoodAmount': startingResourceWoodAmount,
      'startingResourceStoneAmount': startingResourceStoneAmount,
      'buildingUpgradeCostMultiplierLv2': buildingUpgradeCostMultiplierLv2,
      'buildingUpgradeCostMultiplierLv3': buildingUpgradeCostMultiplierLv3,
      ...buildingCostActuals,
    };

    test('balance.yaml の code はすべて既知の定数に対応する（typo・更新漏れ検出）', () {
      final codesInYaml = _collectLeaves(
        balance,
      ).where((leaf) => leaf.code != null).toList();
      expect(codesInYaml, isNotEmpty);
      for (final leaf in codesInYaml) {
        expect(
          conversions.containsKey(leaf.code),
          isTrue,
          reason:
              '${leaf.path}.code = "${leaf.code}" に対応するコードの定数が本テストの'
              'conversions/actualValues に登録されていません。'
              'balance.yaml の code の typo か、本テストの更新漏れの可能性があります。',
        );
      }
    });

    test('conversions に登録した定数は、balance.yaml のいずれかの項目から参照されている', () {
      final codesInYaml = _collectLeaves(
        balance,
      ).map((leaf) => leaf.code).whereType<String>().toSet();
      for (final code in conversions.keys) {
        expect(
          codesInYaml.contains(code),
          isTrue,
          reason: '$code を参照する balance.yaml の項目が見つかりません。',
        );
      }
    });

    for (final code in [
      'terrainYieldAmountPerHexPerUnit',
      'openingPointDistanceMillimetersPerPoint',
      'openingPointStockCap',
      'openingPointCostPerHex',
      'Inventory.defaultCap',
      'SpeedFilter.defaultThresholdKmh',
      'startingResourceWoodAmount',
      'startingResourceStoneAmount',
      'buildingUpgradeCostMultiplierLv2',
      'buildingUpgradeCostMultiplierLv3',
      ...buildingCostActuals.keys,
    ]) {
      test('$code は balance.yaml の値と一致する', () {
        final leaf = _findLeafByCode(balance, code);
        expect(
          leaf,
          isNotNull,
          reason: 'code = "$code" を持つ項目が balance.yaml に見つかりません。',
        );
        final expected = conversions[code]!(leaf!);
        final actual = actualValues[code]!;
        expect(
          actual,
          expected,
          reason:
              '$code（コード側の値: $actual）と balance.yaml「${leaf.path}」'
              '（value: ${leaf.value} ${leaf.unit}）が一致しません。',
        );
      });
    }

    test(
      'terrainYieldMicrosecondsPerUnit は1時間（Duration.microsecondsPerHour）と一致する',
      () {
        // terrain_yield.amount_per_hex_per_hour の unit「個/時間/ヘクス」の
        // 「時間」がコード側でも1時間として扱われていることを確認する
        // （分子側の定数だけを balance.yaml と照合しても、分母（時間の単位）が
        // ずれていれば「1時間に1個」という主張自体が崩れるため）。
        expect(terrainYieldMicrosecondsPerUnit, Duration.microsecondsPerHour);
      },
    );
  });
}

/// balance.yaml の1パラメータ（`status` を持つ YamlMap ノード）を表す。
class _BalanceLeaf {
  _BalanceLeaf({
    required this.path,
    required this.value,
    required this.unit,
    required this.status,
    required this.code,
    required this.source,
  });

  /// ルートからのドット区切りパス（例: `opening_point.stock_cap`）。
  final String path;
  final dynamic value;
  final dynamic unit;
  final String status;
  final String? code;
  final dynamic source;
}

/// [node] 以下を再帰的に走査し、`status` キーを持つ YamlMap を1パラメータの
/// 「葉」として収集する（`status` を持たない YamlMap は中間ノードとして再帰する）。
List<_BalanceLeaf> _collectLeaves(YamlMap node, [String prefix = '']) {
  final leaves = <_BalanceLeaf>[];
  for (final entry in node.entries) {
    final key = entry.key.toString();
    final path = prefix.isEmpty ? key : '$prefix.$key';
    final value = entry.value;
    if (value is YamlMap) {
      if (value.containsKey('status')) {
        leaves.add(
          _BalanceLeaf(
            path: path,
            value: value['value'],
            unit: value['unit'],
            status: value['status'] as String,
            code: value['code'] as String?,
            source: value['source'],
          ),
        );
      } else {
        leaves.addAll(_collectLeaves(value, path));
      }
    }
  }
  return leaves;
}

/// [code] を持つ最初の [_BalanceLeaf] を返す（見つからなければ null）。
_BalanceLeaf? _findLeafByCode(YamlMap balance, String code) {
  for (final leaf in _collectLeaves(balance)) {
    if (leaf.code == code) {
      return leaf;
    }
  }
  return null;
}

/// [_BalanceLeaf.path]（ドット区切り）をたどり、[balance] からその YamlMap
/// ノードそのものを返す。`_collectLeaves` が返す path は必ず存在する
/// YamlMap を指すため、途中でスカラーに当たった場合は呼び出し側のバグ。
YamlMap _findNodeByPath(YamlMap balance, String path) {
  dynamic node = balance;
  for (final key in path.split('.')) {
    node = (node as YamlMap)[key];
  }
  return node as YamlMap;
}
