// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'game_database.dart';

// ignore_for_file: type=lint
class $DisclosedHexesTable extends DisclosedHexes
    with TableInfo<$DisclosedHexesTable, DisclosedHexRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DisclosedHexesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _hexIdMeta = const VerificationMeta('hexId');
  @override
  late final GeneratedColumn<int> hexId = GeneratedColumn<int>(
    'hex_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packVersionMeta = const VerificationMeta(
    'packVersion',
  );
  @override
  late final GeneratedColumn<String> packVersion = GeneratedColumn<String>(
    'pack_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discoveredAtMeta = const VerificationMeta(
    'discoveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> discoveredAt = GeneratedColumn<DateTime>(
    'discovered_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [hexId, packVersion, discoveredAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'disclosed_hex';
  @override
  VerificationContext validateIntegrity(
    Insertable<DisclosedHexRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('hex_id')) {
      context.handle(
        _hexIdMeta,
        hexId.isAcceptableOrUnknown(data['hex_id']!, _hexIdMeta),
      );
    }
    if (data.containsKey('pack_version')) {
      context.handle(
        _packVersionMeta,
        packVersion.isAcceptableOrUnknown(
          data['pack_version']!,
          _packVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packVersionMeta);
    }
    if (data.containsKey('discovered_at')) {
      context.handle(
        _discoveredAtMeta,
        discoveredAt.isAcceptableOrUnknown(
          data['discovered_at']!,
          _discoveredAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {hexId};
  @override
  DisclosedHexRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DisclosedHexRow(
      hexId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hex_id'],
      )!,
      packVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_version'],
      )!,
      discoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}discovered_at'],
      )!,
    );
  }

  @override
  $DisclosedHexesTable createAlias(String alias) {
    return $DisclosedHexesTable(attachedDatabase, alias);
  }
}

class DisclosedHexRow extends DataClass implements Insertable<DisclosedHexRow> {
  /// H3 セルインデックス（`docs/terrain.md` §4.2）。`core` の `HexId.value` と対応する
  /// 非負整数。Dart の `int`（64bit 符号付き）でそのまま表現できる
  /// （H3 index は上位ビットにモード情報を含むが実質63bit以内に収まる）。
  final int hexId;

  /// このヘクスを開示した時点の地域パックバージョン（`PackVersion.value` と対応）。
  final String packVersion;

  /// 開示した日時（端末のウォールクロック。位置記録自体の時刻は
  /// `elapsedRealtime` を使うが〔plan.md §7〕、これは記録の正ではなく
  /// UI 表示・デバッグ用のタイムスタンプ）。
  final DateTime discoveredAt;
  const DisclosedHexRow({
    required this.hexId,
    required this.packVersion,
    required this.discoveredAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['hex_id'] = Variable<int>(hexId);
    map['pack_version'] = Variable<String>(packVersion);
    map['discovered_at'] = Variable<DateTime>(discoveredAt);
    return map;
  }

  DisclosedHexesCompanion toCompanion(bool nullToAbsent) {
    return DisclosedHexesCompanion(
      hexId: Value(hexId),
      packVersion: Value(packVersion),
      discoveredAt: Value(discoveredAt),
    );
  }

  factory DisclosedHexRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DisclosedHexRow(
      hexId: serializer.fromJson<int>(json['hexId']),
      packVersion: serializer.fromJson<String>(json['packVersion']),
      discoveredAt: serializer.fromJson<DateTime>(json['discoveredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'hexId': serializer.toJson<int>(hexId),
      'packVersion': serializer.toJson<String>(packVersion),
      'discoveredAt': serializer.toJson<DateTime>(discoveredAt),
    };
  }

  DisclosedHexRow copyWith({
    int? hexId,
    String? packVersion,
    DateTime? discoveredAt,
  }) => DisclosedHexRow(
    hexId: hexId ?? this.hexId,
    packVersion: packVersion ?? this.packVersion,
    discoveredAt: discoveredAt ?? this.discoveredAt,
  );
  DisclosedHexRow copyWithCompanion(DisclosedHexesCompanion data) {
    return DisclosedHexRow(
      hexId: data.hexId.present ? data.hexId.value : this.hexId,
      packVersion: data.packVersion.present
          ? data.packVersion.value
          : this.packVersion,
      discoveredAt: data.discoveredAt.present
          ? data.discoveredAt.value
          : this.discoveredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DisclosedHexRow(')
          ..write('hexId: $hexId, ')
          ..write('packVersion: $packVersion, ')
          ..write('discoveredAt: $discoveredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(hexId, packVersion, discoveredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DisclosedHexRow &&
          other.hexId == this.hexId &&
          other.packVersion == this.packVersion &&
          other.discoveredAt == this.discoveredAt);
}

class DisclosedHexesCompanion extends UpdateCompanion<DisclosedHexRow> {
  final Value<int> hexId;
  final Value<String> packVersion;
  final Value<DateTime> discoveredAt;
  const DisclosedHexesCompanion({
    this.hexId = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.discoveredAt = const Value.absent(),
  });
  DisclosedHexesCompanion.insert({
    this.hexId = const Value.absent(),
    required String packVersion,
    this.discoveredAt = const Value.absent(),
  }) : packVersion = Value(packVersion);
  static Insertable<DisclosedHexRow> custom({
    Expression<int>? hexId,
    Expression<String>? packVersion,
    Expression<DateTime>? discoveredAt,
  }) {
    return RawValuesInsertable({
      if (hexId != null) 'hex_id': hexId,
      if (packVersion != null) 'pack_version': packVersion,
      if (discoveredAt != null) 'discovered_at': discoveredAt,
    });
  }

  DisclosedHexesCompanion copyWith({
    Value<int>? hexId,
    Value<String>? packVersion,
    Value<DateTime>? discoveredAt,
  }) {
    return DisclosedHexesCompanion(
      hexId: hexId ?? this.hexId,
      packVersion: packVersion ?? this.packVersion,
      discoveredAt: discoveredAt ?? this.discoveredAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (hexId.present) {
      map['hex_id'] = Variable<int>(hexId.value);
    }
    if (packVersion.present) {
      map['pack_version'] = Variable<String>(packVersion.value);
    }
    if (discoveredAt.present) {
      map['discovered_at'] = Variable<DateTime>(discoveredAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DisclosedHexesCompanion(')
          ..write('hexId: $hexId, ')
          ..write('packVersion: $packVersion, ')
          ..write('discoveredAt: $discoveredAt')
          ..write(')'))
        .toString();
  }
}

class $InventoriesTable extends Inventories
    with TableInfo<$InventoriesTable, InventoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $InventoriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _resourceKeyMeta = const VerificationMeta(
    'resourceKey',
  );
  @override
  late final GeneratedColumn<String> resourceKey = GeneratedColumn<String>(
    'resource_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [resourceKey, amount, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'inventory';
  @override
  VerificationContext validateIntegrity(
    Insertable<InventoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('resource_key')) {
      context.handle(
        _resourceKeyMeta,
        resourceKey.isAcceptableOrUnknown(
          data['resource_key']!,
          _resourceKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_resourceKeyMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {resourceKey};
  @override
  InventoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return InventoryRow(
      resourceKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}resource_key'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $InventoriesTable createAlias(String alias) {
    return $InventoriesTable(attachedDatabase, alias);
  }
}

class InventoryRow extends DataClass implements Insertable<InventoryRow> {
  /// 資材種別を表す生の文字列キー（上記のとおり `core` の enum には未依存）。
  final String resourceKey;

  /// 所持数。負値は取らない想定だが、制約の強制は上位層（`core`）の責務とし、
  /// スキーマ上は素直な整数列とする。
  final int amount;
  final DateTime updatedAt;
  const InventoryRow({
    required this.resourceKey,
    required this.amount,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['resource_key'] = Variable<String>(resourceKey);
    map['amount'] = Variable<int>(amount);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  InventoriesCompanion toCompanion(bool nullToAbsent) {
    return InventoriesCompanion(
      resourceKey: Value(resourceKey),
      amount: Value(amount),
      updatedAt: Value(updatedAt),
    );
  }

  factory InventoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return InventoryRow(
      resourceKey: serializer.fromJson<String>(json['resourceKey']),
      amount: serializer.fromJson<int>(json['amount']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'resourceKey': serializer.toJson<String>(resourceKey),
      'amount': serializer.toJson<int>(amount),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  InventoryRow copyWith({
    String? resourceKey,
    int? amount,
    DateTime? updatedAt,
  }) => InventoryRow(
    resourceKey: resourceKey ?? this.resourceKey,
    amount: amount ?? this.amount,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  InventoryRow copyWithCompanion(InventoriesCompanion data) {
    return InventoryRow(
      resourceKey: data.resourceKey.present
          ? data.resourceKey.value
          : this.resourceKey,
      amount: data.amount.present ? data.amount.value : this.amount,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('InventoryRow(')
          ..write('resourceKey: $resourceKey, ')
          ..write('amount: $amount, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(resourceKey, amount, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is InventoryRow &&
          other.resourceKey == this.resourceKey &&
          other.amount == this.amount &&
          other.updatedAt == this.updatedAt);
}

class InventoriesCompanion extends UpdateCompanion<InventoryRow> {
  final Value<String> resourceKey;
  final Value<int> amount;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const InventoriesCompanion({
    this.resourceKey = const Value.absent(),
    this.amount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  InventoriesCompanion.insert({
    required String resourceKey,
    this.amount = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : resourceKey = Value(resourceKey);
  static Insertable<InventoryRow> custom({
    Expression<String>? resourceKey,
    Expression<int>? amount,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (resourceKey != null) 'resource_key': resourceKey,
      if (amount != null) 'amount': amount,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  InventoriesCompanion copyWith({
    Value<String>? resourceKey,
    Value<int>? amount,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return InventoriesCompanion(
      resourceKey: resourceKey ?? this.resourceKey,
      amount: amount ?? this.amount,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (resourceKey.present) {
      map['resource_key'] = Variable<String>(resourceKey.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('InventoriesCompanion(')
          ..write('resourceKey: $resourceKey, ')
          ..write('amount: $amount, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BuildingsTable extends Buildings
    with TableInfo<$BuildingsTable, BuildingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BuildingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _hexIdMeta = const VerificationMeta('hexId');
  @override
  late final GeneratedColumn<int> hexId = GeneratedColumn<int>(
    'hex_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<BuildingType, String>
  buildingType = GeneratedColumn<String>(
    'building_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  ).withConverter<BuildingType>($BuildingsTable.$converterbuildingType);
  static const VerificationMeta _levelMeta = const VerificationMeta('level');
  @override
  late final GeneratedColumn<int> level = GeneratedColumn<int>(
    'level',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  late final GeneratedColumnWithTypeConverter<BuildingConstructionState, String>
  constructionState =
      GeneratedColumn<String>(
        'construction_state',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: Constant(BuildingConstructionState.built.name),
      ).withConverter<BuildingConstructionState>(
        $BuildingsTable.$converterconstructionState,
      );
  static const VerificationMeta _districtIdMeta = const VerificationMeta(
    'districtId',
  );
  @override
  late final GeneratedColumn<String> districtId = GeneratedColumn<String>(
    'district_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _builtAtMeta = const VerificationMeta(
    'builtAt',
  );
  @override
  late final GeneratedColumn<DateTime> builtAt = GeneratedColumn<DateTime>(
    'built_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    hexId,
    buildingType,
    level,
    constructionState,
    districtId,
    builtAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'building';
  @override
  VerificationContext validateIntegrity(
    Insertable<BuildingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('hex_id')) {
      context.handle(
        _hexIdMeta,
        hexId.isAcceptableOrUnknown(data['hex_id']!, _hexIdMeta),
      );
    } else if (isInserting) {
      context.missing(_hexIdMeta);
    }
    if (data.containsKey('level')) {
      context.handle(
        _levelMeta,
        level.isAcceptableOrUnknown(data['level']!, _levelMeta),
      );
    }
    if (data.containsKey('district_id')) {
      context.handle(
        _districtIdMeta,
        districtId.isAcceptableOrUnknown(data['district_id']!, _districtIdMeta),
      );
    }
    if (data.containsKey('built_at')) {
      context.handle(
        _builtAtMeta,
        builtAt.isAcceptableOrUnknown(data['built_at']!, _builtAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {hexId},
  ];
  @override
  BuildingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BuildingRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      hexId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}hex_id'],
      )!,
      buildingType: $BuildingsTable.$converterbuildingType.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}building_type'],
        )!,
      ),
      level: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}level'],
      )!,
      constructionState: $BuildingsTable.$converterconstructionState.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}construction_state'],
        )!,
      ),
      districtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}district_id'],
      ),
      builtAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}built_at'],
      )!,
    );
  }

  @override
  $BuildingsTable createAlias(String alias) {
    return $BuildingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<BuildingType, String, String>
  $converterbuildingType = const EnumNameConverter<BuildingType>(
    BuildingType.values,
  );
  static JsonTypeConverter2<BuildingConstructionState, String, String>
  $converterconstructionState =
      const EnumNameConverter<BuildingConstructionState>(
        BuildingConstructionState.values,
      );
}

class BuildingRow extends DataClass implements Insertable<BuildingRow> {
  final int id;

  /// このマス（ヘクス）の H3 セルインデックス。`disclosed_hex.hexId` と同じ体系。
  /// 「開示済みかつ空き地」のマスにのみ建築できる（buildings.md §3）という制約自体は
  /// `core`（判定ロジック）側の責務であり、本テーブルは結果だけを保持する。
  final int hexId;

  /// 建物種別（buildings.md §2 の8種）。列挙値の並べ替え・追加に強い
  /// `textEnum`（`.name` を文字列として永続化）で保存する。
  final BuildingType buildingType;

  /// アップグレード段階（Lv.1〜Lv.3・仮。buildings.md §4.2）。初期建築は Lv.1。
  final int level;

  /// 建築状態軸（terrain.md §1.1）。本テーブルに行がある時点で常に [built]
  /// だが、明示的な列として保持する理由は [BuildingConstructionState] のドキュメント参照。
  final BuildingConstructionState constructionState;

  /// このマスが属する行政区画（`DistrictId.value` と対応）。パック範囲外・
  /// 未帰属の場合は null（`core` の `RegionPack.districtOf` が null を返す場合に対応）。
  final String? districtId;
  final DateTime builtAt;
  const BuildingRow({
    required this.id,
    required this.hexId,
    required this.buildingType,
    required this.level,
    required this.constructionState,
    this.districtId,
    required this.builtAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['hex_id'] = Variable<int>(hexId);
    {
      map['building_type'] = Variable<String>(
        $BuildingsTable.$converterbuildingType.toSql(buildingType),
      );
    }
    map['level'] = Variable<int>(level);
    {
      map['construction_state'] = Variable<String>(
        $BuildingsTable.$converterconstructionState.toSql(constructionState),
      );
    }
    if (!nullToAbsent || districtId != null) {
      map['district_id'] = Variable<String>(districtId);
    }
    map['built_at'] = Variable<DateTime>(builtAt);
    return map;
  }

  BuildingsCompanion toCompanion(bool nullToAbsent) {
    return BuildingsCompanion(
      id: Value(id),
      hexId: Value(hexId),
      buildingType: Value(buildingType),
      level: Value(level),
      constructionState: Value(constructionState),
      districtId: districtId == null && nullToAbsent
          ? const Value.absent()
          : Value(districtId),
      builtAt: Value(builtAt),
    );
  }

  factory BuildingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BuildingRow(
      id: serializer.fromJson<int>(json['id']),
      hexId: serializer.fromJson<int>(json['hexId']),
      buildingType: $BuildingsTable.$converterbuildingType.fromJson(
        serializer.fromJson<String>(json['buildingType']),
      ),
      level: serializer.fromJson<int>(json['level']),
      constructionState: $BuildingsTable.$converterconstructionState.fromJson(
        serializer.fromJson<String>(json['constructionState']),
      ),
      districtId: serializer.fromJson<String?>(json['districtId']),
      builtAt: serializer.fromJson<DateTime>(json['builtAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'hexId': serializer.toJson<int>(hexId),
      'buildingType': serializer.toJson<String>(
        $BuildingsTable.$converterbuildingType.toJson(buildingType),
      ),
      'level': serializer.toJson<int>(level),
      'constructionState': serializer.toJson<String>(
        $BuildingsTable.$converterconstructionState.toJson(constructionState),
      ),
      'districtId': serializer.toJson<String?>(districtId),
      'builtAt': serializer.toJson<DateTime>(builtAt),
    };
  }

  BuildingRow copyWith({
    int? id,
    int? hexId,
    BuildingType? buildingType,
    int? level,
    BuildingConstructionState? constructionState,
    Value<String?> districtId = const Value.absent(),
    DateTime? builtAt,
  }) => BuildingRow(
    id: id ?? this.id,
    hexId: hexId ?? this.hexId,
    buildingType: buildingType ?? this.buildingType,
    level: level ?? this.level,
    constructionState: constructionState ?? this.constructionState,
    districtId: districtId.present ? districtId.value : this.districtId,
    builtAt: builtAt ?? this.builtAt,
  );
  BuildingRow copyWithCompanion(BuildingsCompanion data) {
    return BuildingRow(
      id: data.id.present ? data.id.value : this.id,
      hexId: data.hexId.present ? data.hexId.value : this.hexId,
      buildingType: data.buildingType.present
          ? data.buildingType.value
          : this.buildingType,
      level: data.level.present ? data.level.value : this.level,
      constructionState: data.constructionState.present
          ? data.constructionState.value
          : this.constructionState,
      districtId: data.districtId.present
          ? data.districtId.value
          : this.districtId,
      builtAt: data.builtAt.present ? data.builtAt.value : this.builtAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BuildingRow(')
          ..write('id: $id, ')
          ..write('hexId: $hexId, ')
          ..write('buildingType: $buildingType, ')
          ..write('level: $level, ')
          ..write('constructionState: $constructionState, ')
          ..write('districtId: $districtId, ')
          ..write('builtAt: $builtAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    hexId,
    buildingType,
    level,
    constructionState,
    districtId,
    builtAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BuildingRow &&
          other.id == this.id &&
          other.hexId == this.hexId &&
          other.buildingType == this.buildingType &&
          other.level == this.level &&
          other.constructionState == this.constructionState &&
          other.districtId == this.districtId &&
          other.builtAt == this.builtAt);
}

class BuildingsCompanion extends UpdateCompanion<BuildingRow> {
  final Value<int> id;
  final Value<int> hexId;
  final Value<BuildingType> buildingType;
  final Value<int> level;
  final Value<BuildingConstructionState> constructionState;
  final Value<String?> districtId;
  final Value<DateTime> builtAt;
  const BuildingsCompanion({
    this.id = const Value.absent(),
    this.hexId = const Value.absent(),
    this.buildingType = const Value.absent(),
    this.level = const Value.absent(),
    this.constructionState = const Value.absent(),
    this.districtId = const Value.absent(),
    this.builtAt = const Value.absent(),
  });
  BuildingsCompanion.insert({
    this.id = const Value.absent(),
    required int hexId,
    required BuildingType buildingType,
    this.level = const Value.absent(),
    this.constructionState = const Value.absent(),
    this.districtId = const Value.absent(),
    this.builtAt = const Value.absent(),
  }) : hexId = Value(hexId),
       buildingType = Value(buildingType);
  static Insertable<BuildingRow> custom({
    Expression<int>? id,
    Expression<int>? hexId,
    Expression<String>? buildingType,
    Expression<int>? level,
    Expression<String>? constructionState,
    Expression<String>? districtId,
    Expression<DateTime>? builtAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (hexId != null) 'hex_id': hexId,
      if (buildingType != null) 'building_type': buildingType,
      if (level != null) 'level': level,
      if (constructionState != null) 'construction_state': constructionState,
      if (districtId != null) 'district_id': districtId,
      if (builtAt != null) 'built_at': builtAt,
    });
  }

  BuildingsCompanion copyWith({
    Value<int>? id,
    Value<int>? hexId,
    Value<BuildingType>? buildingType,
    Value<int>? level,
    Value<BuildingConstructionState>? constructionState,
    Value<String?>? districtId,
    Value<DateTime>? builtAt,
  }) {
    return BuildingsCompanion(
      id: id ?? this.id,
      hexId: hexId ?? this.hexId,
      buildingType: buildingType ?? this.buildingType,
      level: level ?? this.level,
      constructionState: constructionState ?? this.constructionState,
      districtId: districtId ?? this.districtId,
      builtAt: builtAt ?? this.builtAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (hexId.present) {
      map['hex_id'] = Variable<int>(hexId.value);
    }
    if (buildingType.present) {
      map['building_type'] = Variable<String>(
        $BuildingsTable.$converterbuildingType.toSql(buildingType.value),
      );
    }
    if (level.present) {
      map['level'] = Variable<int>(level.value);
    }
    if (constructionState.present) {
      map['construction_state'] = Variable<String>(
        $BuildingsTable.$converterconstructionState.toSql(
          constructionState.value,
        ),
      );
    }
    if (districtId.present) {
      map['district_id'] = Variable<String>(districtId.value);
    }
    if (builtAt.present) {
      map['built_at'] = Variable<DateTime>(builtAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BuildingsCompanion(')
          ..write('id: $id, ')
          ..write('hexId: $hexId, ')
          ..write('buildingType: $buildingType, ')
          ..write('level: $level, ')
          ..write('constructionState: $constructionState, ')
          ..write('districtId: $districtId, ')
          ..write('builtAt: $builtAt')
          ..write(')'))
        .toString();
  }
}

class $DistrictProgressesTable extends DistrictProgresses
    with TableInfo<$DistrictProgressesTable, DistrictProgressRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DistrictProgressesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _districtIdMeta = const VerificationMeta(
    'districtId',
  );
  @override
  late final GeneratedColumn<String> districtId = GeneratedColumn<String>(
    'district_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _conquestRateMeta = const VerificationMeta(
    'conquestRate',
  );
  @override
  late final GeneratedColumn<double> conquestRate = GeneratedColumn<double>(
    'conquest_rate',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _developmentScoreMeta = const VerificationMeta(
    'developmentScore',
  );
  @override
  late final GeneratedColumn<double> developmentScore = GeneratedColumn<double>(
    'development_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [
    districtId,
    conquestRate,
    developmentScore,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'district_progress';
  @override
  VerificationContext validateIntegrity(
    Insertable<DistrictProgressRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('district_id')) {
      context.handle(
        _districtIdMeta,
        districtId.isAcceptableOrUnknown(data['district_id']!, _districtIdMeta),
      );
    } else if (isInserting) {
      context.missing(_districtIdMeta);
    }
    if (data.containsKey('conquest_rate')) {
      context.handle(
        _conquestRateMeta,
        conquestRate.isAcceptableOrUnknown(
          data['conquest_rate']!,
          _conquestRateMeta,
        ),
      );
    }
    if (data.containsKey('development_score')) {
      context.handle(
        _developmentScoreMeta,
        developmentScore.isAcceptableOrUnknown(
          data['development_score']!,
          _developmentScoreMeta,
        ),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {districtId};
  @override
  DistrictProgressRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DistrictProgressRow(
      districtId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}district_id'],
      )!,
      conquestRate: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}conquest_rate'],
      )!,
      developmentScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}development_score'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DistrictProgressesTable createAlias(String alias) {
    return $DistrictProgressesTable(attachedDatabase, alias);
  }
}

class DistrictProgressRow extends DataClass
    implements Insertable<DistrictProgressRow> {
  /// 区画識別子（`DistrictId.value` と対応）。
  final String districtId;

  /// 制覇率。0.0〜1.0 を想定するが、範囲の強制は上位層の責務とする
  /// （分母は「区画内の到達可能ヘクス」— plan.md §5 代表回答）。
  final double conquestRate;

  /// 発展度。具体的な算出式は balance 検討で確定する仮の実数値。
  final double developmentScore;
  final DateTime updatedAt;
  const DistrictProgressRow({
    required this.districtId,
    required this.conquestRate,
    required this.developmentScore,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['district_id'] = Variable<String>(districtId);
    map['conquest_rate'] = Variable<double>(conquestRate);
    map['development_score'] = Variable<double>(developmentScore);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  DistrictProgressesCompanion toCompanion(bool nullToAbsent) {
    return DistrictProgressesCompanion(
      districtId: Value(districtId),
      conquestRate: Value(conquestRate),
      developmentScore: Value(developmentScore),
      updatedAt: Value(updatedAt),
    );
  }

  factory DistrictProgressRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DistrictProgressRow(
      districtId: serializer.fromJson<String>(json['districtId']),
      conquestRate: serializer.fromJson<double>(json['conquestRate']),
      developmentScore: serializer.fromJson<double>(json['developmentScore']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'districtId': serializer.toJson<String>(districtId),
      'conquestRate': serializer.toJson<double>(conquestRate),
      'developmentScore': serializer.toJson<double>(developmentScore),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  DistrictProgressRow copyWith({
    String? districtId,
    double? conquestRate,
    double? developmentScore,
    DateTime? updatedAt,
  }) => DistrictProgressRow(
    districtId: districtId ?? this.districtId,
    conquestRate: conquestRate ?? this.conquestRate,
    developmentScore: developmentScore ?? this.developmentScore,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DistrictProgressRow copyWithCompanion(DistrictProgressesCompanion data) {
    return DistrictProgressRow(
      districtId: data.districtId.present
          ? data.districtId.value
          : this.districtId,
      conquestRate: data.conquestRate.present
          ? data.conquestRate.value
          : this.conquestRate,
      developmentScore: data.developmentScore.present
          ? data.developmentScore.value
          : this.developmentScore,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DistrictProgressRow(')
          ..write('districtId: $districtId, ')
          ..write('conquestRate: $conquestRate, ')
          ..write('developmentScore: $developmentScore, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(districtId, conquestRate, developmentScore, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DistrictProgressRow &&
          other.districtId == this.districtId &&
          other.conquestRate == this.conquestRate &&
          other.developmentScore == this.developmentScore &&
          other.updatedAt == this.updatedAt);
}

class DistrictProgressesCompanion extends UpdateCompanion<DistrictProgressRow> {
  final Value<String> districtId;
  final Value<double> conquestRate;
  final Value<double> developmentScore;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const DistrictProgressesCompanion({
    this.districtId = const Value.absent(),
    this.conquestRate = const Value.absent(),
    this.developmentScore = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DistrictProgressesCompanion.insert({
    required String districtId,
    this.conquestRate = const Value.absent(),
    this.developmentScore = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : districtId = Value(districtId);
  static Insertable<DistrictProgressRow> custom({
    Expression<String>? districtId,
    Expression<double>? conquestRate,
    Expression<double>? developmentScore,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (districtId != null) 'district_id': districtId,
      if (conquestRate != null) 'conquest_rate': conquestRate,
      if (developmentScore != null) 'development_score': developmentScore,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DistrictProgressesCompanion copyWith({
    Value<String>? districtId,
    Value<double>? conquestRate,
    Value<double>? developmentScore,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return DistrictProgressesCompanion(
      districtId: districtId ?? this.districtId,
      conquestRate: conquestRate ?? this.conquestRate,
      developmentScore: developmentScore ?? this.developmentScore,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (districtId.present) {
      map['district_id'] = Variable<String>(districtId.value);
    }
    if (conquestRate.present) {
      map['conquest_rate'] = Variable<double>(conquestRate.value);
    }
    if (developmentScore.present) {
      map['development_score'] = Variable<double>(developmentScore.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DistrictProgressesCompanion(')
          ..write('districtId: $districtId, ')
          ..write('conquestRate: $conquestRate, ')
          ..write('developmentScore: $developmentScore, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CollectionsTable extends Collections
    with TableInfo<$CollectionsTable, CollectionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CollectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _poiIdMeta = const VerificationMeta('poiId');
  @override
  late final GeneratedColumn<String> poiId = GeneratedColumn<String>(
    'poi_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _discoveredAtMeta = const VerificationMeta(
    'discoveredAt',
  );
  @override
  late final GeneratedColumn<DateTime> discoveredAt = GeneratedColumn<DateTime>(
    'discovered_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [poiId, discoveredAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'collection';
  @override
  VerificationContext validateIntegrity(
    Insertable<CollectionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('poi_id')) {
      context.handle(
        _poiIdMeta,
        poiId.isAcceptableOrUnknown(data['poi_id']!, _poiIdMeta),
      );
    } else if (isInserting) {
      context.missing(_poiIdMeta);
    }
    if (data.containsKey('discovered_at')) {
      context.handle(
        _discoveredAtMeta,
        discoveredAt.isAcceptableOrUnknown(
          data['discovered_at']!,
          _discoveredAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {poiId};
  @override
  CollectionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CollectionRow(
      poiId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}poi_id'],
      )!,
      discoveredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}discovered_at'],
      )!,
    );
  }

  @override
  $CollectionsTable createAlias(String alias) {
    return $CollectionsTable(attachedDatabase, alias);
  }
}

class CollectionRow extends DataClass implements Insertable<CollectionRow> {
  /// `PointOfInterestId.value` と対応。
  final String poiId;
  final DateTime discoveredAt;
  const CollectionRow({required this.poiId, required this.discoveredAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['poi_id'] = Variable<String>(poiId);
    map['discovered_at'] = Variable<DateTime>(discoveredAt);
    return map;
  }

  CollectionsCompanion toCompanion(bool nullToAbsent) {
    return CollectionsCompanion(
      poiId: Value(poiId),
      discoveredAt: Value(discoveredAt),
    );
  }

  factory CollectionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CollectionRow(
      poiId: serializer.fromJson<String>(json['poiId']),
      discoveredAt: serializer.fromJson<DateTime>(json['discoveredAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'poiId': serializer.toJson<String>(poiId),
      'discoveredAt': serializer.toJson<DateTime>(discoveredAt),
    };
  }

  CollectionRow copyWith({String? poiId, DateTime? discoveredAt}) =>
      CollectionRow(
        poiId: poiId ?? this.poiId,
        discoveredAt: discoveredAt ?? this.discoveredAt,
      );
  CollectionRow copyWithCompanion(CollectionsCompanion data) {
    return CollectionRow(
      poiId: data.poiId.present ? data.poiId.value : this.poiId,
      discoveredAt: data.discoveredAt.present
          ? data.discoveredAt.value
          : this.discoveredAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CollectionRow(')
          ..write('poiId: $poiId, ')
          ..write('discoveredAt: $discoveredAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(poiId, discoveredAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionRow &&
          other.poiId == this.poiId &&
          other.discoveredAt == this.discoveredAt);
}

class CollectionsCompanion extends UpdateCompanion<CollectionRow> {
  final Value<String> poiId;
  final Value<DateTime> discoveredAt;
  final Value<int> rowid;
  const CollectionsCompanion({
    this.poiId = const Value.absent(),
    this.discoveredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CollectionsCompanion.insert({
    required String poiId,
    this.discoveredAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : poiId = Value(poiId);
  static Insertable<CollectionRow> custom({
    Expression<String>? poiId,
    Expression<DateTime>? discoveredAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (poiId != null) 'poi_id': poiId,
      if (discoveredAt != null) 'discovered_at': discoveredAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CollectionsCompanion copyWith({
    Value<String>? poiId,
    Value<DateTime>? discoveredAt,
    Value<int>? rowid,
  }) {
    return CollectionsCompanion(
      poiId: poiId ?? this.poiId,
      discoveredAt: discoveredAt ?? this.discoveredAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (poiId.present) {
      map['poi_id'] = Variable<String>(poiId.value);
    }
    if (discoveredAt.present) {
      map['discovered_at'] = Variable<DateTime>(discoveredAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CollectionsCompanion(')
          ..write('poiId: $poiId, ')
          ..write('discoveredAt: $discoveredAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $QuestDailiesTable extends QuestDailies
    with TableInfo<$QuestDailiesTable, QuestDailyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QuestDailiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _questDateMeta = const VerificationMeta(
    'questDate',
  );
  @override
  late final GeneratedColumn<DateTime> questDate = GeneratedColumn<DateTime>(
    'quest_date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _questKeyMeta = const VerificationMeta(
    'questKey',
  );
  @override
  late final GeneratedColumn<String> questKey = GeneratedColumn<String>(
    'quest_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<int> progress = GeneratedColumn<int>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _goalMeta = const VerificationMeta('goal');
  @override
  late final GeneratedColumn<int> goal = GeneratedColumn<int>(
    'goal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _completedMeta = const VerificationMeta(
    'completed',
  );
  @override
  late final GeneratedColumn<bool> completed = GeneratedColumn<bool>(
    'completed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("completed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _completedAtMeta = const VerificationMeta(
    'completedAt',
  );
  @override
  late final GeneratedColumn<DateTime> completedAt = GeneratedColumn<DateTime>(
    'completed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    questDate,
    questKey,
    progress,
    goal,
    completed,
    completedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'quest_daily';
  @override
  VerificationContext validateIntegrity(
    Insertable<QuestDailyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('quest_date')) {
      context.handle(
        _questDateMeta,
        questDate.isAcceptableOrUnknown(data['quest_date']!, _questDateMeta),
      );
    } else if (isInserting) {
      context.missing(_questDateMeta);
    }
    if (data.containsKey('quest_key')) {
      context.handle(
        _questKeyMeta,
        questKey.isAcceptableOrUnknown(data['quest_key']!, _questKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_questKeyMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('goal')) {
      context.handle(
        _goalMeta,
        goal.isAcceptableOrUnknown(data['goal']!, _goalMeta),
      );
    } else if (isInserting) {
      context.missing(_goalMeta);
    }
    if (data.containsKey('completed')) {
      context.handle(
        _completedMeta,
        completed.isAcceptableOrUnknown(data['completed']!, _completedMeta),
      );
    }
    if (data.containsKey('completed_at')) {
      context.handle(
        _completedAtMeta,
        completedAt.isAcceptableOrUnknown(
          data['completed_at']!,
          _completedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {questDate, questKey},
  ];
  @override
  QuestDailyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QuestDailyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      questDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}quest_date'],
      )!,
      questKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}quest_key'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}progress'],
      )!,
      goal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}goal'],
      )!,
      completed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}completed'],
      )!,
      completedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}completed_at'],
      ),
    );
  }

  @override
  $QuestDailiesTable createAlias(String alias) {
    return $QuestDailiesTable(attachedDatabase, alias);
  }
}

class QuestDailyRow extends DataClass implements Insertable<QuestDailyRow> {
  final int id;

  /// このクエストが属する日（端末のローカル日付の 00:00 を想定。タイムゾーン等の
  /// 扱いは生成ロジック側〔#11〕の責務）。
  final DateTime questDate;

  /// クエスト種別を表す生の文字列キー（生成ロジックは #11 側の責務）。
  final String questKey;
  final int progress;
  final int goal;
  final bool completed;
  final DateTime? completedAt;
  const QuestDailyRow({
    required this.id,
    required this.questDate,
    required this.questKey,
    required this.progress,
    required this.goal,
    required this.completed,
    this.completedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['quest_date'] = Variable<DateTime>(questDate);
    map['quest_key'] = Variable<String>(questKey);
    map['progress'] = Variable<int>(progress);
    map['goal'] = Variable<int>(goal);
    map['completed'] = Variable<bool>(completed);
    if (!nullToAbsent || completedAt != null) {
      map['completed_at'] = Variable<DateTime>(completedAt);
    }
    return map;
  }

  QuestDailiesCompanion toCompanion(bool nullToAbsent) {
    return QuestDailiesCompanion(
      id: Value(id),
      questDate: Value(questDate),
      questKey: Value(questKey),
      progress: Value(progress),
      goal: Value(goal),
      completed: Value(completed),
      completedAt: completedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(completedAt),
    );
  }

  factory QuestDailyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QuestDailyRow(
      id: serializer.fromJson<int>(json['id']),
      questDate: serializer.fromJson<DateTime>(json['questDate']),
      questKey: serializer.fromJson<String>(json['questKey']),
      progress: serializer.fromJson<int>(json['progress']),
      goal: serializer.fromJson<int>(json['goal']),
      completed: serializer.fromJson<bool>(json['completed']),
      completedAt: serializer.fromJson<DateTime?>(json['completedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'questDate': serializer.toJson<DateTime>(questDate),
      'questKey': serializer.toJson<String>(questKey),
      'progress': serializer.toJson<int>(progress),
      'goal': serializer.toJson<int>(goal),
      'completed': serializer.toJson<bool>(completed),
      'completedAt': serializer.toJson<DateTime?>(completedAt),
    };
  }

  QuestDailyRow copyWith({
    int? id,
    DateTime? questDate,
    String? questKey,
    int? progress,
    int? goal,
    bool? completed,
    Value<DateTime?> completedAt = const Value.absent(),
  }) => QuestDailyRow(
    id: id ?? this.id,
    questDate: questDate ?? this.questDate,
    questKey: questKey ?? this.questKey,
    progress: progress ?? this.progress,
    goal: goal ?? this.goal,
    completed: completed ?? this.completed,
    completedAt: completedAt.present ? completedAt.value : this.completedAt,
  );
  QuestDailyRow copyWithCompanion(QuestDailiesCompanion data) {
    return QuestDailyRow(
      id: data.id.present ? data.id.value : this.id,
      questDate: data.questDate.present ? data.questDate.value : this.questDate,
      questKey: data.questKey.present ? data.questKey.value : this.questKey,
      progress: data.progress.present ? data.progress.value : this.progress,
      goal: data.goal.present ? data.goal.value : this.goal,
      completed: data.completed.present ? data.completed.value : this.completed,
      completedAt: data.completedAt.present
          ? data.completedAt.value
          : this.completedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QuestDailyRow(')
          ..write('id: $id, ')
          ..write('questDate: $questDate, ')
          ..write('questKey: $questKey, ')
          ..write('progress: $progress, ')
          ..write('goal: $goal, ')
          ..write('completed: $completed, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    questDate,
    questKey,
    progress,
    goal,
    completed,
    completedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QuestDailyRow &&
          other.id == this.id &&
          other.questDate == this.questDate &&
          other.questKey == this.questKey &&
          other.progress == this.progress &&
          other.goal == this.goal &&
          other.completed == this.completed &&
          other.completedAt == this.completedAt);
}

class QuestDailiesCompanion extends UpdateCompanion<QuestDailyRow> {
  final Value<int> id;
  final Value<DateTime> questDate;
  final Value<String> questKey;
  final Value<int> progress;
  final Value<int> goal;
  final Value<bool> completed;
  final Value<DateTime?> completedAt;
  const QuestDailiesCompanion({
    this.id = const Value.absent(),
    this.questDate = const Value.absent(),
    this.questKey = const Value.absent(),
    this.progress = const Value.absent(),
    this.goal = const Value.absent(),
    this.completed = const Value.absent(),
    this.completedAt = const Value.absent(),
  });
  QuestDailiesCompanion.insert({
    this.id = const Value.absent(),
    required DateTime questDate,
    required String questKey,
    this.progress = const Value.absent(),
    required int goal,
    this.completed = const Value.absent(),
    this.completedAt = const Value.absent(),
  }) : questDate = Value(questDate),
       questKey = Value(questKey),
       goal = Value(goal);
  static Insertable<QuestDailyRow> custom({
    Expression<int>? id,
    Expression<DateTime>? questDate,
    Expression<String>? questKey,
    Expression<int>? progress,
    Expression<int>? goal,
    Expression<bool>? completed,
    Expression<DateTime>? completedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (questDate != null) 'quest_date': questDate,
      if (questKey != null) 'quest_key': questKey,
      if (progress != null) 'progress': progress,
      if (goal != null) 'goal': goal,
      if (completed != null) 'completed': completed,
      if (completedAt != null) 'completed_at': completedAt,
    });
  }

  QuestDailiesCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? questDate,
    Value<String>? questKey,
    Value<int>? progress,
    Value<int>? goal,
    Value<bool>? completed,
    Value<DateTime?>? completedAt,
  }) {
    return QuestDailiesCompanion(
      id: id ?? this.id,
      questDate: questDate ?? this.questDate,
      questKey: questKey ?? this.questKey,
      progress: progress ?? this.progress,
      goal: goal ?? this.goal,
      completed: completed ?? this.completed,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (questDate.present) {
      map['quest_date'] = Variable<DateTime>(questDate.value);
    }
    if (questKey.present) {
      map['quest_key'] = Variable<String>(questKey.value);
    }
    if (progress.present) {
      map['progress'] = Variable<int>(progress.value);
    }
    if (goal.present) {
      map['goal'] = Variable<int>(goal.value);
    }
    if (completed.present) {
      map['completed'] = Variable<bool>(completed.value);
    }
    if (completedAt.present) {
      map['completed_at'] = Variable<DateTime>(completedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QuestDailiesCompanion(')
          ..write('id: $id, ')
          ..write('questDate: $questDate, ')
          ..write('questKey: $questKey, ')
          ..write('progress: $progress, ')
          ..write('goal: $goal, ')
          ..write('completed: $completed, ')
          ..write('completedAt: $completedAt')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    defaultValue: currentDateAndTime,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;

  /// 設定値。複合的な値（例: プライバシーゾーンのリスト）は呼び出し側が
  /// JSON 文字列にエンコードして保持する想定。
  final String value;
  final DateTime updatedAt;
  const SettingRow({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SettingRow copyWith({String? key, String? value, DateTime? updatedAt}) =>
      SettingRow(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$GameDatabase extends GeneratedDatabase {
  _$GameDatabase(QueryExecutor e) : super(e);
  $GameDatabaseManager get managers => $GameDatabaseManager(this);
  late final $DisclosedHexesTable disclosedHexes = $DisclosedHexesTable(this);
  late final $InventoriesTable inventories = $InventoriesTable(this);
  late final $BuildingsTable buildings = $BuildingsTable(this);
  late final $DistrictProgressesTable districtProgresses =
      $DistrictProgressesTable(this);
  late final $CollectionsTable collections = $CollectionsTable(this);
  late final $QuestDailiesTable questDailies = $QuestDailiesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    disclosedHexes,
    inventories,
    buildings,
    districtProgresses,
    collections,
    questDailies,
    settings,
  ];
}

typedef $$DisclosedHexesTableCreateCompanionBuilder =
    DisclosedHexesCompanion Function({
      Value<int> hexId,
      required String packVersion,
      Value<DateTime> discoveredAt,
    });
typedef $$DisclosedHexesTableUpdateCompanionBuilder =
    DisclosedHexesCompanion Function({
      Value<int> hexId,
      Value<String> packVersion,
      Value<DateTime> discoveredAt,
    });

class $$DisclosedHexesTableFilterComposer
    extends Composer<_$GameDatabase, $DisclosedHexesTable> {
  $$DisclosedHexesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get hexId => $composableBuilder(
    column: $table.hexId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DisclosedHexesTableOrderingComposer
    extends Composer<_$GameDatabase, $DisclosedHexesTable> {
  $$DisclosedHexesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get hexId => $composableBuilder(
    column: $table.hexId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DisclosedHexesTableAnnotationComposer
    extends Composer<_$GameDatabase, $DisclosedHexesTable> {
  $$DisclosedHexesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get hexId =>
      $composableBuilder(column: $table.hexId, builder: (column) => column);

  GeneratedColumn<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => column,
  );
}

class $$DisclosedHexesTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $DisclosedHexesTable,
          DisclosedHexRow,
          $$DisclosedHexesTableFilterComposer,
          $$DisclosedHexesTableOrderingComposer,
          $$DisclosedHexesTableAnnotationComposer,
          $$DisclosedHexesTableCreateCompanionBuilder,
          $$DisclosedHexesTableUpdateCompanionBuilder,
          (
            DisclosedHexRow,
            BaseReferences<
              _$GameDatabase,
              $DisclosedHexesTable,
              DisclosedHexRow
            >,
          ),
          DisclosedHexRow,
          PrefetchHooks Function()
        > {
  $$DisclosedHexesTableTableManager(
    _$GameDatabase db,
    $DisclosedHexesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DisclosedHexesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DisclosedHexesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DisclosedHexesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> hexId = const Value.absent(),
                Value<String> packVersion = const Value.absent(),
                Value<DateTime> discoveredAt = const Value.absent(),
              }) => DisclosedHexesCompanion(
                hexId: hexId,
                packVersion: packVersion,
                discoveredAt: discoveredAt,
              ),
          createCompanionCallback:
              ({
                Value<int> hexId = const Value.absent(),
                required String packVersion,
                Value<DateTime> discoveredAt = const Value.absent(),
              }) => DisclosedHexesCompanion.insert(
                hexId: hexId,
                packVersion: packVersion,
                discoveredAt: discoveredAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DisclosedHexesTable, DisclosedHexRow>(table),
                  BaseReferences<
                    _$GameDatabase,
                    $DisclosedHexesTable,
                    DisclosedHexRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DisclosedHexesTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $DisclosedHexesTable,
      DisclosedHexRow,
      $$DisclosedHexesTableFilterComposer,
      $$DisclosedHexesTableOrderingComposer,
      $$DisclosedHexesTableAnnotationComposer,
      $$DisclosedHexesTableCreateCompanionBuilder,
      $$DisclosedHexesTableUpdateCompanionBuilder,
      (
        DisclosedHexRow,
        BaseReferences<_$GameDatabase, $DisclosedHexesTable, DisclosedHexRow>,
      ),
      DisclosedHexRow,
      PrefetchHooks Function()
    >;
typedef $$InventoriesTableCreateCompanionBuilder =
    InventoriesCompanion Function({
      required String resourceKey,
      Value<int> amount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$InventoriesTableUpdateCompanionBuilder =
    InventoriesCompanion Function({
      Value<String> resourceKey,
      Value<int> amount,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$InventoriesTableFilterComposer
    extends Composer<_$GameDatabase, $InventoriesTable> {
  $$InventoriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get resourceKey => $composableBuilder(
    column: $table.resourceKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$InventoriesTableOrderingComposer
    extends Composer<_$GameDatabase, $InventoriesTable> {
  $$InventoriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get resourceKey => $composableBuilder(
    column: $table.resourceKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$InventoriesTableAnnotationComposer
    extends Composer<_$GameDatabase, $InventoriesTable> {
  $$InventoriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get resourceKey => $composableBuilder(
    column: $table.resourceKey,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$InventoriesTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $InventoriesTable,
          InventoryRow,
          $$InventoriesTableFilterComposer,
          $$InventoriesTableOrderingComposer,
          $$InventoriesTableAnnotationComposer,
          $$InventoriesTableCreateCompanionBuilder,
          $$InventoriesTableUpdateCompanionBuilder,
          (
            InventoryRow,
            BaseReferences<_$GameDatabase, $InventoriesTable, InventoryRow>,
          ),
          InventoryRow,
          PrefetchHooks Function()
        > {
  $$InventoriesTableTableManager(_$GameDatabase db, $InventoriesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$InventoriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$InventoriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$InventoriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> resourceKey = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoriesCompanion(
                resourceKey: resourceKey,
                amount: amount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String resourceKey,
                Value<int> amount = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => InventoriesCompanion.insert(
                resourceKey: resourceKey,
                amount: amount,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$InventoriesTable, InventoryRow>(table),
                  BaseReferences<
                    _$GameDatabase,
                    $InventoriesTable,
                    InventoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$InventoriesTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $InventoriesTable,
      InventoryRow,
      $$InventoriesTableFilterComposer,
      $$InventoriesTableOrderingComposer,
      $$InventoriesTableAnnotationComposer,
      $$InventoriesTableCreateCompanionBuilder,
      $$InventoriesTableUpdateCompanionBuilder,
      (
        InventoryRow,
        BaseReferences<_$GameDatabase, $InventoriesTable, InventoryRow>,
      ),
      InventoryRow,
      PrefetchHooks Function()
    >;
typedef $$BuildingsTableCreateCompanionBuilder =
    BuildingsCompanion Function({
      Value<int> id,
      required int hexId,
      required BuildingType buildingType,
      Value<int> level,
      Value<BuildingConstructionState> constructionState,
      Value<String?> districtId,
      Value<DateTime> builtAt,
    });
typedef $$BuildingsTableUpdateCompanionBuilder =
    BuildingsCompanion Function({
      Value<int> id,
      Value<int> hexId,
      Value<BuildingType> buildingType,
      Value<int> level,
      Value<BuildingConstructionState> constructionState,
      Value<String?> districtId,
      Value<DateTime> builtAt,
    });

class $$BuildingsTableFilterComposer
    extends Composer<_$GameDatabase, $BuildingsTable> {
  $$BuildingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get hexId => $composableBuilder(
    column: $table.hexId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<BuildingType, BuildingType, String>
  get buildingType => $composableBuilder(
    column: $table.buildingType,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<
    BuildingConstructionState,
    BuildingConstructionState,
    String
  >
  get constructionState => $composableBuilder(
    column: $table.constructionState,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get districtId => $composableBuilder(
    column: $table.districtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get builtAt => $composableBuilder(
    column: $table.builtAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BuildingsTableOrderingComposer
    extends Composer<_$GameDatabase, $BuildingsTable> {
  $$BuildingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get hexId => $composableBuilder(
    column: $table.hexId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get buildingType => $composableBuilder(
    column: $table.buildingType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get level => $composableBuilder(
    column: $table.level,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get constructionState => $composableBuilder(
    column: $table.constructionState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get districtId => $composableBuilder(
    column: $table.districtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get builtAt => $composableBuilder(
    column: $table.builtAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BuildingsTableAnnotationComposer
    extends Composer<_$GameDatabase, $BuildingsTable> {
  $$BuildingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get hexId =>
      $composableBuilder(column: $table.hexId, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BuildingType, String> get buildingType =>
      $composableBuilder(
        column: $table.buildingType,
        builder: (column) => column,
      );

  GeneratedColumn<int> get level =>
      $composableBuilder(column: $table.level, builder: (column) => column);

  GeneratedColumnWithTypeConverter<BuildingConstructionState, String>
  get constructionState => $composableBuilder(
    column: $table.constructionState,
    builder: (column) => column,
  );

  GeneratedColumn<String> get districtId => $composableBuilder(
    column: $table.districtId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get builtAt =>
      $composableBuilder(column: $table.builtAt, builder: (column) => column);
}

class $$BuildingsTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $BuildingsTable,
          BuildingRow,
          $$BuildingsTableFilterComposer,
          $$BuildingsTableOrderingComposer,
          $$BuildingsTableAnnotationComposer,
          $$BuildingsTableCreateCompanionBuilder,
          $$BuildingsTableUpdateCompanionBuilder,
          (
            BuildingRow,
            BaseReferences<_$GameDatabase, $BuildingsTable, BuildingRow>,
          ),
          BuildingRow,
          PrefetchHooks Function()
        > {
  $$BuildingsTableTableManager(_$GameDatabase db, $BuildingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BuildingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BuildingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BuildingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> hexId = const Value.absent(),
                Value<BuildingType> buildingType = const Value.absent(),
                Value<int> level = const Value.absent(),
                Value<BuildingConstructionState> constructionState =
                    const Value.absent(),
                Value<String?> districtId = const Value.absent(),
                Value<DateTime> builtAt = const Value.absent(),
              }) => BuildingsCompanion(
                id: id,
                hexId: hexId,
                buildingType: buildingType,
                level: level,
                constructionState: constructionState,
                districtId: districtId,
                builtAt: builtAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int hexId,
                required BuildingType buildingType,
                Value<int> level = const Value.absent(),
                Value<BuildingConstructionState> constructionState =
                    const Value.absent(),
                Value<String?> districtId = const Value.absent(),
                Value<DateTime> builtAt = const Value.absent(),
              }) => BuildingsCompanion.insert(
                id: id,
                hexId: hexId,
                buildingType: buildingType,
                level: level,
                constructionState: constructionState,
                districtId: districtId,
                builtAt: builtAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BuildingsTable, BuildingRow>(table),
                  BaseReferences<_$GameDatabase, $BuildingsTable, BuildingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BuildingsTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $BuildingsTable,
      BuildingRow,
      $$BuildingsTableFilterComposer,
      $$BuildingsTableOrderingComposer,
      $$BuildingsTableAnnotationComposer,
      $$BuildingsTableCreateCompanionBuilder,
      $$BuildingsTableUpdateCompanionBuilder,
      (
        BuildingRow,
        BaseReferences<_$GameDatabase, $BuildingsTable, BuildingRow>,
      ),
      BuildingRow,
      PrefetchHooks Function()
    >;
typedef $$DistrictProgressesTableCreateCompanionBuilder =
    DistrictProgressesCompanion Function({
      required String districtId,
      Value<double> conquestRate,
      Value<double> developmentScore,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$DistrictProgressesTableUpdateCompanionBuilder =
    DistrictProgressesCompanion Function({
      Value<String> districtId,
      Value<double> conquestRate,
      Value<double> developmentScore,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$DistrictProgressesTableFilterComposer
    extends Composer<_$GameDatabase, $DistrictProgressesTable> {
  $$DistrictProgressesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get districtId => $composableBuilder(
    column: $table.districtId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get conquestRate => $composableBuilder(
    column: $table.conquestRate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get developmentScore => $composableBuilder(
    column: $table.developmentScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DistrictProgressesTableOrderingComposer
    extends Composer<_$GameDatabase, $DistrictProgressesTable> {
  $$DistrictProgressesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get districtId => $composableBuilder(
    column: $table.districtId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get conquestRate => $composableBuilder(
    column: $table.conquestRate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get developmentScore => $composableBuilder(
    column: $table.developmentScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DistrictProgressesTableAnnotationComposer
    extends Composer<_$GameDatabase, $DistrictProgressesTable> {
  $$DistrictProgressesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get districtId => $composableBuilder(
    column: $table.districtId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get conquestRate => $composableBuilder(
    column: $table.conquestRate,
    builder: (column) => column,
  );

  GeneratedColumn<double> get developmentScore => $composableBuilder(
    column: $table.developmentScore,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$DistrictProgressesTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $DistrictProgressesTable,
          DistrictProgressRow,
          $$DistrictProgressesTableFilterComposer,
          $$DistrictProgressesTableOrderingComposer,
          $$DistrictProgressesTableAnnotationComposer,
          $$DistrictProgressesTableCreateCompanionBuilder,
          $$DistrictProgressesTableUpdateCompanionBuilder,
          (
            DistrictProgressRow,
            BaseReferences<
              _$GameDatabase,
              $DistrictProgressesTable,
              DistrictProgressRow
            >,
          ),
          DistrictProgressRow,
          PrefetchHooks Function()
        > {
  $$DistrictProgressesTableTableManager(
    _$GameDatabase db,
    $DistrictProgressesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DistrictProgressesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DistrictProgressesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DistrictProgressesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> districtId = const Value.absent(),
                Value<double> conquestRate = const Value.absent(),
                Value<double> developmentScore = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DistrictProgressesCompanion(
                districtId: districtId,
                conquestRate: conquestRate,
                developmentScore: developmentScore,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String districtId,
                Value<double> conquestRate = const Value.absent(),
                Value<double> developmentScore = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DistrictProgressesCompanion.insert(
                districtId: districtId,
                conquestRate: conquestRate,
                developmentScore: developmentScore,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DistrictProgressesTable, DistrictProgressRow>(
                    table,
                  ),
                  BaseReferences<
                    _$GameDatabase,
                    $DistrictProgressesTable,
                    DistrictProgressRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DistrictProgressesTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $DistrictProgressesTable,
      DistrictProgressRow,
      $$DistrictProgressesTableFilterComposer,
      $$DistrictProgressesTableOrderingComposer,
      $$DistrictProgressesTableAnnotationComposer,
      $$DistrictProgressesTableCreateCompanionBuilder,
      $$DistrictProgressesTableUpdateCompanionBuilder,
      (
        DistrictProgressRow,
        BaseReferences<
          _$GameDatabase,
          $DistrictProgressesTable,
          DistrictProgressRow
        >,
      ),
      DistrictProgressRow,
      PrefetchHooks Function()
    >;
typedef $$CollectionsTableCreateCompanionBuilder =
    CollectionsCompanion Function({
      required String poiId,
      Value<DateTime> discoveredAt,
      Value<int> rowid,
    });
typedef $$CollectionsTableUpdateCompanionBuilder =
    CollectionsCompanion Function({
      Value<String> poiId,
      Value<DateTime> discoveredAt,
      Value<int> rowid,
    });

class $$CollectionsTableFilterComposer
    extends Composer<_$GameDatabase, $CollectionsTable> {
  $$CollectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get poiId => $composableBuilder(
    column: $table.poiId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CollectionsTableOrderingComposer
    extends Composer<_$GameDatabase, $CollectionsTable> {
  $$CollectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get poiId => $composableBuilder(
    column: $table.poiId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CollectionsTableAnnotationComposer
    extends Composer<_$GameDatabase, $CollectionsTable> {
  $$CollectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get poiId =>
      $composableBuilder(column: $table.poiId, builder: (column) => column);

  GeneratedColumn<DateTime> get discoveredAt => $composableBuilder(
    column: $table.discoveredAt,
    builder: (column) => column,
  );
}

class $$CollectionsTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $CollectionsTable,
          CollectionRow,
          $$CollectionsTableFilterComposer,
          $$CollectionsTableOrderingComposer,
          $$CollectionsTableAnnotationComposer,
          $$CollectionsTableCreateCompanionBuilder,
          $$CollectionsTableUpdateCompanionBuilder,
          (
            CollectionRow,
            BaseReferences<_$GameDatabase, $CollectionsTable, CollectionRow>,
          ),
          CollectionRow,
          PrefetchHooks Function()
        > {
  $$CollectionsTableTableManager(_$GameDatabase db, $CollectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CollectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CollectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CollectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> poiId = const Value.absent(),
                Value<DateTime> discoveredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion(
                poiId: poiId,
                discoveredAt: discoveredAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String poiId,
                Value<DateTime> discoveredAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CollectionsCompanion.insert(
                poiId: poiId,
                discoveredAt: discoveredAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CollectionsTable, CollectionRow>(table),
                  BaseReferences<
                    _$GameDatabase,
                    $CollectionsTable,
                    CollectionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$CollectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $CollectionsTable,
      CollectionRow,
      $$CollectionsTableFilterComposer,
      $$CollectionsTableOrderingComposer,
      $$CollectionsTableAnnotationComposer,
      $$CollectionsTableCreateCompanionBuilder,
      $$CollectionsTableUpdateCompanionBuilder,
      (
        CollectionRow,
        BaseReferences<_$GameDatabase, $CollectionsTable, CollectionRow>,
      ),
      CollectionRow,
      PrefetchHooks Function()
    >;
typedef $$QuestDailiesTableCreateCompanionBuilder =
    QuestDailiesCompanion Function({
      Value<int> id,
      required DateTime questDate,
      required String questKey,
      Value<int> progress,
      required int goal,
      Value<bool> completed,
      Value<DateTime?> completedAt,
    });
typedef $$QuestDailiesTableUpdateCompanionBuilder =
    QuestDailiesCompanion Function({
      Value<int> id,
      Value<DateTime> questDate,
      Value<String> questKey,
      Value<int> progress,
      Value<int> goal,
      Value<bool> completed,
      Value<DateTime?> completedAt,
    });

class $$QuestDailiesTableFilterComposer
    extends Composer<_$GameDatabase, $QuestDailiesTable> {
  $$QuestDailiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get questDate => $composableBuilder(
    column: $table.questDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get questKey => $composableBuilder(
    column: $table.questKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QuestDailiesTableOrderingComposer
    extends Composer<_$GameDatabase, $QuestDailiesTable> {
  $$QuestDailiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get questDate => $composableBuilder(
    column: $table.questDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get questKey => $composableBuilder(
    column: $table.questKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get goal => $composableBuilder(
    column: $table.goal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get completed => $composableBuilder(
    column: $table.completed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QuestDailiesTableAnnotationComposer
    extends Composer<_$GameDatabase, $QuestDailiesTable> {
  $$QuestDailiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get questDate =>
      $composableBuilder(column: $table.questDate, builder: (column) => column);

  GeneratedColumn<String> get questKey =>
      $composableBuilder(column: $table.questKey, builder: (column) => column);

  GeneratedColumn<int> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<int> get goal =>
      $composableBuilder(column: $table.goal, builder: (column) => column);

  GeneratedColumn<bool> get completed =>
      $composableBuilder(column: $table.completed, builder: (column) => column);

  GeneratedColumn<DateTime> get completedAt => $composableBuilder(
    column: $table.completedAt,
    builder: (column) => column,
  );
}

class $$QuestDailiesTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $QuestDailiesTable,
          QuestDailyRow,
          $$QuestDailiesTableFilterComposer,
          $$QuestDailiesTableOrderingComposer,
          $$QuestDailiesTableAnnotationComposer,
          $$QuestDailiesTableCreateCompanionBuilder,
          $$QuestDailiesTableUpdateCompanionBuilder,
          (
            QuestDailyRow,
            BaseReferences<_$GameDatabase, $QuestDailiesTable, QuestDailyRow>,
          ),
          QuestDailyRow,
          PrefetchHooks Function()
        > {
  $$QuestDailiesTableTableManager(_$GameDatabase db, $QuestDailiesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QuestDailiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QuestDailiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QuestDailiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> questDate = const Value.absent(),
                Value<String> questKey = const Value.absent(),
                Value<int> progress = const Value.absent(),
                Value<int> goal = const Value.absent(),
                Value<bool> completed = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
              }) => QuestDailiesCompanion(
                id: id,
                questDate: questDate,
                questKey: questKey,
                progress: progress,
                goal: goal,
                completed: completed,
                completedAt: completedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime questDate,
                required String questKey,
                Value<int> progress = const Value.absent(),
                required int goal,
                Value<bool> completed = const Value.absent(),
                Value<DateTime?> completedAt = const Value.absent(),
              }) => QuestDailiesCompanion.insert(
                id: id,
                questDate: questDate,
                questKey: questKey,
                progress: progress,
                goal: goal,
                completed: completed,
                completedAt: completedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$QuestDailiesTable, QuestDailyRow>(table),
                  BaseReferences<
                    _$GameDatabase,
                    $QuestDailiesTable,
                    QuestDailyRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QuestDailiesTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $QuestDailiesTable,
      QuestDailyRow,
      $$QuestDailiesTableFilterComposer,
      $$QuestDailiesTableOrderingComposer,
      $$QuestDailiesTableAnnotationComposer,
      $$QuestDailiesTableCreateCompanionBuilder,
      $$QuestDailiesTableUpdateCompanionBuilder,
      (
        QuestDailyRow,
        BaseReferences<_$GameDatabase, $QuestDailiesTable, QuestDailyRow>,
      ),
      QuestDailyRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$GameDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$GameDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$GameDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$GameDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$GameDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$GameDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$GameDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$GameDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$GameDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $GameDatabaseManager {
  final _$GameDatabase _db;
  $GameDatabaseManager(this._db);
  $$DisclosedHexesTableTableManager get disclosedHexes =>
      $$DisclosedHexesTableTableManager(_db, _db.disclosedHexes);
  $$InventoriesTableTableManager get inventories =>
      $$InventoriesTableTableManager(_db, _db.inventories);
  $$BuildingsTableTableManager get buildings =>
      $$BuildingsTableTableManager(_db, _db.buildings);
  $$DistrictProgressesTableTableManager get districtProgresses =>
      $$DistrictProgressesTableTableManager(_db, _db.districtProgresses);
  $$CollectionsTableTableManager get collections =>
      $$CollectionsTableTableManager(_db, _db.collections);
  $$QuestDailiesTableTableManager get questDailies =>
      $$QuestDailiesTableTableManager(_db, _db.questDailies);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
