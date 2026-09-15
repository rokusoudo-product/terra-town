import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:terra_town_core/terra_town_core.dart';

import '../db/game_database.dart';
import 'save_data_exceptions.dart';

/// セーブデータのファイル形式（Issue #180 決定事項1）の JSON エンコード/デコード。
///
/// ## `hex_id` 等の巨大整数を10進文字列で書く理由
/// H3 の解像度11セルインデックス（`docs/terrain.md` §4.2）は実機で
/// `6` × `10^17` 程度の値になる（`disclosed_hex.hex_id`・`building.hex_id`。
/// `docs/terrain.md` §4.4 の地物 ID の丸め問題と同種）。**MVP で実際に
/// 使われるヘクスIDはほぼ確実に IEEE754 倍精度浮動小数点数の安全な整数範囲（2^53 =
/// 9007199254740992）を超える**ため、これは理論上の縁ケースではなく通常運転で
/// 毎回踏む値である。`dart:convert` の `jsonEncode`/`jsonDecode` は数値を
/// double 経由で扱うため、これらの列は常に10進文字列としてエンコードし、
/// 読み込み時に [int.parse] で復元する。
///
/// ## フォーマットバージョン
/// [kSaveDataFormatVersion] は「JSON の入れ物の形」自体のバージョン
/// （`tables` の構造・巨大整数の文字列化ルール等）を表し、`schema_version`
/// （`GameDatabase.schemaVersion`・DBスキーマのバージョン）とは独立した値。
const int kSaveDataFormatVersion = 1;

/// 現行の `tables` の7キー（Issue #180 決定事項1・2）。
const List<String> kSaveDataTableNames = [
  'disclosed_hex',
  'inventory',
  'building',
  'district_progress',
  'collection',
  'quest_daily',
  'settings',
];

/// [parseSaveDataDocument]/[SaveDataTransferService.exportToJsonString] の
/// 双方が扱う、パース済み・型付けされたセーブデータ1件分。
class SaveDataDocument {
  const SaveDataDocument({
    required this.formatVersion,
    required this.schemaVersion,
    required this.packVersion,
    required this.appVersion,
    required this.exportedAt,
    required this.disclosedHexes,
    required this.inventories,
    required this.buildings,
    required this.districtProgresses,
    required this.collections,
    required this.questDailies,
    required this.settings,
  });

  final int formatVersion;
  final int schemaVersion;
  final String packVersion;
  final String appVersion;
  final DateTime exportedAt;

  final List<DisclosedHexesCompanion> disclosedHexes;
  final List<InventoriesCompanion> inventories;
  final List<BuildingsCompanion> buildings;
  final List<DistrictProgressesCompanion> districtProgresses;
  final List<CollectionsCompanion> collections;
  final List<QuestDailiesCompanion> questDailies;
  final List<SettingsCompanion> settings;
}

/// [jsonString] を検証・パースして [SaveDataDocument] を返す（Issue #180
/// 決定事項4「検証内容: JSON として正しいか、`format_version`・`schema_version`・
/// 必須キーがそろっているか」）。
///
/// **この関数は DB に一切触れない**（純粋な構造検証・変換のみ）。呼び出し側
/// （`SaveDataTransferService`）は、この関数が例外を投げずに戻ってきた場合にのみ
/// 実際の読み込み（トランザクション）に進む。
///
/// 投げうる例外:
/// - [SaveDataFormatException]: JSON として不正・必須キーの欠落・値の型不正・
///   未知の `format_version`／enum値。
/// - [SaveDataSchemaTooNewException]: `schema_version` が [currentSchemaVersion]
///   より新しい。
/// - [SaveDataSchemaMigrationUnsupportedException]: `schema_version` が
///   [currentSchemaVersion] より古い（読み替えの入口はあるが未実装。クラスdoc
///   `SaveDataSchemaMigrationUnsupportedException` 参照）。
SaveDataDocument parseSaveDataDocument(
  String jsonString, {
  required int currentSchemaVersion,
}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(jsonString);
  } on FormatException catch (error) {
    throw SaveDataFormatException('JSON として解釈できません: $error');
  }

  if (decoded is! Map<String, dynamic>) {
    throw const SaveDataFormatException('セーブデータのトップレベルはオブジェクトである必要があります');
  }

  final formatVersion = _requireInt(decoded, 'format_version');
  if (formatVersion != kSaveDataFormatVersion) {
    throw SaveDataFormatException(
      '未知の format_version です: $formatVersion（対応: $kSaveDataFormatVersion）',
    );
  }

  final schemaVersion = _requireInt(decoded, 'schema_version');
  if (schemaVersion > currentSchemaVersion) {
    throw SaveDataSchemaTooNewException(
      foundVersion: schemaVersion,
      supportedVersion: currentSchemaVersion,
    );
  }
  if (schemaVersion < currentSchemaVersion) {
    throw SaveDataSchemaMigrationUnsupportedException(
      foundVersion: schemaVersion,
      supportedVersion: currentSchemaVersion,
    );
  }

  final packVersion = _requireString(decoded, 'pack_version');
  final appVersion = _requireString(decoded, 'app_version');
  final exportedAt = _decodeDateTime(
    _requireField(decoded, 'exported_at'),
    'exported_at',
  );

  final tablesField = _requireField(decoded, 'tables');
  if (tablesField is! Map<String, dynamic>) {
    throw const SaveDataFormatException('tables はオブジェクトである必要があります');
  }
  for (final name in kSaveDataTableNames) {
    if (tablesField[name] is! List) {
      throw SaveDataFormatException('tables.$name が存在しないか配列ではありません');
    }
  }

  return SaveDataDocument(
    formatVersion: formatVersion,
    schemaVersion: schemaVersion,
    packVersion: packVersion,
    appVersion: appVersion,
    exportedAt: exportedAt,
    disclosedHexes: (tablesField['disclosed_hex'] as List)
        .map((row) => _decodeDisclosedHex(_asRow(row, 'disclosed_hex')))
        .toList(growable: false),
    inventories: (tablesField['inventory'] as List)
        .map((row) => _decodeInventory(_asRow(row, 'inventory')))
        .toList(growable: false),
    buildings: (tablesField['building'] as List)
        .map((row) => _decodeBuilding(_asRow(row, 'building')))
        .toList(growable: false),
    districtProgresses: (tablesField['district_progress'] as List)
        .map((row) => _decodeDistrictProgress(_asRow(row, 'district_progress')))
        .toList(growable: false),
    collections: (tablesField['collection'] as List)
        .map((row) => _decodeCollection(_asRow(row, 'collection')))
        .toList(growable: false),
    questDailies: (tablesField['quest_daily'] as List)
        .map((row) => _decodeQuestDaily(_asRow(row, 'quest_daily')))
        .toList(growable: false),
    settings: (tablesField['settings'] as List)
        .map((row) => _decodeSetting(_asRow(row, 'settings')))
        .toList(growable: false),
  );
}

/// [rows]・[appVersion]・[packVersion]・[exportedAt] から書き出し用の JSON
/// 文字列を組み立てる（[GameDatabase] の現在の内容を渡す想定。
/// `SaveDataTransferService.exportToJsonString` から呼ぶ）。
String encodeSaveDataDocument({
  required String appVersion,
  required String packVersion,
  required DateTime exportedAt,
  required int schemaVersion,
  required List<DisclosedHexRow> disclosedHexes,
  required List<InventoryRow> inventories,
  required List<BuildingRow> buildings,
  required List<DistrictProgressRow> districtProgresses,
  required List<CollectionRow> collections,
  required List<QuestDailyRow> questDailies,
  required List<SettingRow> settings,
}) {
  final map = <String, dynamic>{
    'format_version': kSaveDataFormatVersion,
    'schema_version': schemaVersion,
    'pack_version': packVersion,
    'app_version': appVersion,
    'exported_at': _encodeDateTime(exportedAt),
    'tables': {
      'disclosed_hex': disclosedHexes.map(_encodeDisclosedHex).toList(),
      'inventory': inventories.map(_encodeInventory).toList(),
      'building': buildings.map(_encodeBuilding).toList(),
      'district_progress': districtProgresses
          .map(_encodeDistrictProgress)
          .toList(),
      'collection': collections.map(_encodeCollection).toList(),
      'quest_daily': questDailies.map(_encodeQuestDaily).toList(),
      'settings': settings.map(_encodeSetting).toList(),
    },
  };
  return const JsonEncoder.withIndent('  ').convert(map);
}

// --- disclosed_hex ---------------------------------------------------------

Map<String, dynamic> _encodeDisclosedHex(DisclosedHexRow row) => {
  'hex_id': _encodeBigInt(row.hexId),
  'terrain_type': row.terrainType.name,
  'pack_version': row.packVersion,
  'discovered_at': _encodeDateTime(row.discoveredAt),
};

DisclosedHexesCompanion _decodeDisclosedHex(Map<String, dynamic> json) {
  const table = 'disclosed_hex';
  return DisclosedHexesCompanion(
    hexId: Value(_decodeBigInt(_requireField(json, 'hex_id'), '$table.hex_id')),
    terrainType: Value(
      _decodeEnum(
        TerrainType.values,
        _requireString(json, 'terrain_type'),
        '$table.terrain_type',
      ),
    ),
    packVersion: Value(_requireString(json, 'pack_version')),
    discoveredAt: Value(
      _decodeDateTime(
        _requireField(json, 'discovered_at'),
        '$table.discovered_at',
      ),
    ),
  );
}

// --- inventory ---------------------------------------------------------

Map<String, dynamic> _encodeInventory(InventoryRow row) => {
  'resource_key': row.resourceKey,
  'amount': row.amount,
  'updated_at': _encodeDateTime(row.updatedAt),
};

InventoriesCompanion _decodeInventory(Map<String, dynamic> json) {
  const table = 'inventory';
  return InventoriesCompanion(
    resourceKey: Value(_requireString(json, 'resource_key')),
    amount: Value(_requireInt(json, 'amount')),
    updatedAt: Value(
      _decodeDateTime(_requireField(json, 'updated_at'), '$table.updated_at'),
    ),
  );
}

// --- building ---------------------------------------------------------

Map<String, dynamic> _encodeBuilding(BuildingRow row) => {
  'id': row.id,
  'hex_id': _encodeBigInt(row.hexId),
  'building_type': row.buildingType.name,
  'level': row.level,
  'construction_state': row.constructionState.name,
  'district_id': row.districtId,
  'built_at': _encodeDateTime(row.builtAt),
};

BuildingsCompanion _decodeBuilding(Map<String, dynamic> json) {
  const table = 'building';
  return BuildingsCompanion(
    id: Value(_requireInt(json, 'id')),
    hexId: Value(_decodeBigInt(_requireField(json, 'hex_id'), '$table.hex_id')),
    buildingType: Value(
      _decodeEnum(
        BuildingType.values,
        _requireString(json, 'building_type'),
        '$table.building_type',
      ),
    ),
    level: Value(_requireInt(json, 'level')),
    constructionState: Value(
      _decodeEnum(
        BuildingConstructionState.values,
        _requireString(json, 'construction_state'),
        '$table.construction_state',
      ),
    ),
    districtId: Value(_optionalString(json, 'district_id')),
    builtAt: Value(
      _decodeDateTime(_requireField(json, 'built_at'), '$table.built_at'),
    ),
  );
}

// --- district_progress ---------------------------------------------------------

Map<String, dynamic> _encodeDistrictProgress(DistrictProgressRow row) => {
  'district_id': row.districtId,
  'conquest_rate': row.conquestRate,
  'development_score': row.developmentScore,
  'updated_at': _encodeDateTime(row.updatedAt),
};

DistrictProgressesCompanion _decodeDistrictProgress(Map<String, dynamic> json) {
  const table = 'district_progress';
  return DistrictProgressesCompanion(
    districtId: Value(_requireString(json, 'district_id')),
    conquestRate: Value(_requireDouble(json, 'conquest_rate')),
    developmentScore: Value(_requireDouble(json, 'development_score')),
    updatedAt: Value(
      _decodeDateTime(_requireField(json, 'updated_at'), '$table.updated_at'),
    ),
  );
}

// --- collection ---------------------------------------------------------

Map<String, dynamic> _encodeCollection(CollectionRow row) => {
  'poi_id': row.poiId,
  'kind': row.kind,
  'name': row.name,
  'is_bonus': row.isBonus,
  'collect_method': row.collectMethod?.name,
  'bonus_granted': row.bonusGranted,
  'discovered_at': _encodeDateTime(row.discoveredAt),
};

CollectionsCompanion _decodeCollection(Map<String, dynamic> json) {
  const table = 'collection';
  final collectMethodName = _optionalString(json, 'collect_method');
  return CollectionsCompanion(
    poiId: Value(_requireString(json, 'poi_id')),
    kind: Value(_optionalString(json, 'kind')),
    name: Value(_optionalString(json, 'name')),
    isBonus: Value(_requireBool(json, 'is_bonus')),
    collectMethod: Value(
      collectMethodName == null
          ? null
          : _decodeEnum(
              CollectMethod.values,
              collectMethodName,
              '$table.collect_method',
            ),
    ),
    bonusGranted: Value(_optionalInt(json, 'bonus_granted')),
    discoveredAt: Value(
      _decodeDateTime(
        _requireField(json, 'discovered_at'),
        '$table.discovered_at',
      ),
    ),
  );
}

// --- quest_daily ---------------------------------------------------------

Map<String, dynamic> _encodeQuestDaily(QuestDailyRow row) => {
  'id': row.id,
  'quest_date': _encodeDateTime(row.questDate),
  'quest_key': row.questKey,
  'progress': row.progress,
  'goal': row.goal,
  'completed': row.completed,
  'completed_at': row.completedAt == null
      ? null
      : _encodeDateTime(row.completedAt!),
};

QuestDailiesCompanion _decodeQuestDaily(Map<String, dynamic> json) {
  const table = 'quest_daily';
  final completedAtRaw = json['completed_at'];
  return QuestDailiesCompanion(
    id: Value(_requireInt(json, 'id')),
    questDate: Value(
      _decodeDateTime(_requireField(json, 'quest_date'), '$table.quest_date'),
    ),
    questKey: Value(_requireString(json, 'quest_key')),
    progress: Value(_requireInt(json, 'progress')),
    goal: Value(_requireInt(json, 'goal')),
    completed: Value(_requireBool(json, 'completed')),
    completedAt: Value(
      completedAtRaw == null
          ? null
          : _decodeDateTime(completedAtRaw, '$table.completed_at'),
    ),
  );
}

// --- settings ---------------------------------------------------------

Map<String, dynamic> _encodeSetting(SettingRow row) => {
  'key': row.key,
  'value': row.value,
  'updated_at': _encodeDateTime(row.updatedAt),
};

SettingsCompanion _decodeSetting(Map<String, dynamic> json) {
  const table = 'settings';
  return SettingsCompanion(
    key: Value(_requireString(json, 'key')),
    value: Value(_requireString(json, 'value')),
    updatedAt: Value(
      _decodeDateTime(_requireField(json, 'updated_at'), '$table.updated_at'),
    ),
  );
}

// --- 共通ヘルパー ---------------------------------------------------------

/// `hex_id` 等の巨大整数を10進文字列にエンコードする（クラスdoc参照）。
String _encodeBigInt(int value) => value.toString();

int _decodeBigInt(Object? value, String field) {
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  // テスト用フィクスチャ等が生の数値で書いていても寛容に受け付ける
  // （2^53 以下の値であれば JSON の数値としても安全に運べるため）。
  if (value is int) return value;
  throw SaveDataFormatException('$field は10進文字列である必要があります: $value');
}

String _encodeDateTime(DateTime value) => value.toUtc().toIso8601String();

DateTime _decodeDateTime(Object? value, String field) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.toUtc();
  }
  throw SaveDataFormatException('$field はISO8601の日時文字列である必要があります: $value');
}

T _decodeEnum<T extends Enum>(List<T> values, String name, String field) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  throw SaveDataFormatException('$field の値が不正です: $name');
}

Object? _requireField(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key)) {
    throw SaveDataFormatException('必須キーが欠けています: $key');
  }
  return json[key];
}

int _requireInt(Map<String, dynamic> json, String key) {
  final value = _requireField(json, key);
  if (value is int) return value;
  throw SaveDataFormatException('$key は整数である必要があります: $value');
}

double _requireDouble(Map<String, dynamic> json, String key) {
  final value = _requireField(json, key);
  if (value is num) return value.toDouble();
  throw SaveDataFormatException('$key は数値である必要があります: $value');
}

bool _requireBool(Map<String, dynamic> json, String key) {
  final value = _requireField(json, key);
  if (value is bool) return value;
  throw SaveDataFormatException('$key は真偽値である必要があります: $value');
}

String _requireString(Map<String, dynamic> json, String key) {
  final value = _requireField(json, key);
  if (value is String) return value;
  throw SaveDataFormatException('$key は文字列である必要があります: $value');
}

String? _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw SaveDataFormatException('$key は文字列またはnullである必要があります: $value');
}

int? _optionalInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  throw SaveDataFormatException('$key は整数またはnullである必要があります: $value');
}

Map<String, dynamic> _asRow(Object? value, String table) {
  if (value is Map<String, dynamic>) return value;
  throw SaveDataFormatException('tables.$table の各要素はオブジェクトである必要があります');
}
