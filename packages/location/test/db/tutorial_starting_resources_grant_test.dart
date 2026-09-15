// TutorialStartingResourcesGrant（Issue #188・T116）の単体テスト。
//
// docs/tutorial.md §3・§5・Issue #188 受け入れ基準に基づき、次を検証する:
//   1. 初回付与（印が無い状態で木50・石10が加算され、印が書かれる）
//   2. 既存の所持数への加算（上書きではない）
//   3. 2回目以降は付与されない
//   4. 加算と印の書き込みが同一トランザクション（片方の失敗で両方ロールバック）
//   5. セーブデータの読み込み後の挙動（印あり／印なしのファイルを読み込んだ場合）

import 'package:flutter_test/flutter_test.dart';
import 'package:terra_town_core/terra_town_core.dart';
import 'package:terra_town_location/terra_town_location.dart';

/// [InventoryRepository.add] を2回目の呼び出しから必ず失敗させるフェイク
/// （`terrain_yield_ledger_test.dart` の `_ThrowsOnSecondAddInventoryRepository`
/// と同じ考え方。`TutorialStartingResourcesGrant.grantIfNeeded` のトランザクションが
/// ロールバックされることを検証するために使う）。
class _ThrowsOnSecondAddInventoryRepository implements InventoryRepository {
  _ThrowsOnSecondAddInventoryRepository(this._delegate);

  final InventoryRepository _delegate;
  int _callCount = 0;

  @override
  Future<void> add(Resource resource, int delta) async {
    _callCount++;
    if (_callCount >= 2) {
      throw StateError('意図的な失敗（テスト用）');
    }
    await _delegate.add(resource, delta);
  }

  @override
  Future<int> amountOf(Resource resource) => _delegate.amountOf(resource);

  @override
  Future<Map<Resource, int>> readAll() => _delegate.readAll();
}

/// [LocationPointIdSource] のフェイク（`save_data_transfer_service_test.dart` と
/// 同じ方針。本テストではウォーターマーク補正の値自体は検証対象外のため常に0）。
class _FakeLocationPointIdSource implements LocationPointIdSource {
  @override
  Future<int> getMaxLocationPointId() async => 0;
}

/// [SaveDataBackupWriter] のフェイク（書き込みを記録するだけ。実ファイルには触れない）。
class _FakeBackupWriter implements SaveDataBackupWriter {
  int writeCount = 0;

  @override
  Future<String> write(String jsonContents) async {
    writeCount++;
    return '/fake/backups/pre-import-$writeCount.json';
  }
}

void main() {
  group('TutorialStartingResourcesGrant（インメモリDB）', () {
    late GameDatabase database;
    late TutorialStartingResourcesGrant grant;

    setUp(() {
      database = GameDatabase.forTesting();
      grant = TutorialStartingResourcesGrant(database);
    });

    tearDown(() async {
      await database.close();
    });

    test('初回は木50・石10が加算され、印が書かれ、trueを返す', () async {
      final granted = await grant.grantIfNeeded();

      expect(granted, isTrue);

      final inventory = InventoryRepository(database);
      expect(await inventory.amountOf(Resource.wood), startingResourceWoodAmount);
      expect(await inventory.amountOf(Resource.stone), startingResourceStoneAmount);

      final settingRow = await (database.select(database.settings)
            ..where((t) => t.key.equals(
                TutorialStartingResourcesGrant.grantedSettingsKey)))
          .getSingleOrNull();
      expect(settingRow, isNotNull);
      expect(
        settingRow!.value,
        TutorialStartingResourcesGrant.grantedSettingsValue,
      );
    });

    test('既に所持数がある場合は上書きではなく加算される', () async {
      final inventory = InventoryRepository(database);
      await inventory.add(Resource.wood, 3);
      await inventory.add(Resource.stone, 7);

      await grant.grantIfNeeded();

      expect(
        await inventory.amountOf(Resource.wood),
        3 + startingResourceWoodAmount,
      );
      expect(
        await inventory.amountOf(Resource.stone),
        7 + startingResourceStoneAmount,
      );
    });

    test('2回目以降の呼び出しでは付与されず、falseを返し所持数も変わらない', () async {
      await grant.grantIfNeeded();

      final secondGranted = await grant.grantIfNeeded();

      expect(secondGranted, isFalse);
      final inventory = InventoryRepository(database);
      expect(await inventory.amountOf(Resource.wood), startingResourceWoodAmount);
      expect(
        await inventory.amountOf(Resource.stone),
        startingResourceStoneAmount,
      );

      // 3回目も同様（何度呼んでも安全＝冪等）。
      final thirdGranted = await grant.grantIfNeeded();
      expect(thirdGranted, isFalse);
    });
  });

  group('TutorialStartingResourcesGrant（トランザクションの原子性・失敗時のロールバック）', () {
    test('2件目（石）の加算で失敗すると、1件目（木）の加算も印の書き込みも一切コミットされない', () async {
      final database = GameDatabase.forTesting();
      addTearDown(database.close);

      final throwingInventory =
          _ThrowsOnSecondAddInventoryRepository(InventoryRepository(database));
      final grant = TutorialStartingResourcesGrant(
        database,
        inventoryRepository: throwingInventory,
      );

      await expectLater(
        grant.grantIfNeeded(),
        throwsA(isA<StateError>()),
      );

      final inventory = InventoryRepository(database);
      expect(await inventory.amountOf(Resource.wood), 0, reason: '1件目もロールバックされる');
      expect(await inventory.amountOf(Resource.stone), 0);

      final settingRow = await (database.select(database.settings)
            ..where((t) => t.key.equals(
                TutorialStartingResourcesGrant.grantedSettingsKey)))
          .getSingleOrNull();
      expect(settingRow, isNull, reason: '印もロールバックされる');
    });
  });

  group('TutorialStartingResourcesGrant（セーブデータの読み込み後の挙動・docs/tutorial.md §5）', () {
    test('印を含まないセーブデータ（旧バージョンの書き出し）を読み込んだ後は1回付与される', () async {
      // 本機能より前のバージョンで書き出したファイルを模して、印を持たない
      // ソースDBをそのままエクスポートする。
      final sourceDatabase = GameDatabase.forTesting();
      addTearDown(sourceDatabase.close);
      final sourceTransferService = SaveDataTransferService(
        sourceDatabase,
        locationPointIdSource: _FakeLocationPointIdSource(),
      );
      final jsonWithoutMark = await sourceTransferService.exportToJsonString();

      // 読み込み先の端末は、読み込み前に既に付与済み（印あり）だったとする。
      // インポートは settings テーブルごと入れ替えるため、印を持たないファイルを
      // 読み込むと印は消える（docs/tutorial.md §5）。
      final targetDatabase = GameDatabase.forTesting();
      addTearDown(targetDatabase.close);
      final targetGrant = TutorialStartingResourcesGrant(targetDatabase);
      await targetGrant.grantIfNeeded();
      expect(
        await InventoryRepository(targetDatabase).amountOf(Resource.wood),
        startingResourceWoodAmount,
      );

      final targetTransferService = SaveDataTransferService(
        targetDatabase,
        locationPointIdSource: _FakeLocationPointIdSource(),
      );
      await targetTransferService.importFromJsonString(
        jsonWithoutMark,
        backupWriter: _FakeBackupWriter(),
      );

      // インポートで settings・inventory とも入れ替わり（ソースは空）、印が消えている。
      final grantedAgain = await targetGrant.grantIfNeeded();

      expect(grantedAgain, isTrue, reason: '印が無い状態になったため、もう一度付与される（許容された二重付与）');
      expect(
        await InventoryRepository(targetDatabase).amountOf(Resource.wood),
        startingResourceWoodAmount,
      );
      expect(
        await InventoryRepository(targetDatabase).amountOf(Resource.stone),
        startingResourceStoneAmount,
      );
    });

    test('印を含むセーブデータを読み込んだ後は付与されない（付与済みの状態が維持される）', () async {
      final sourceDatabase = GameDatabase.forTesting();
      addTearDown(sourceDatabase.close);
      await TutorialStartingResourcesGrant(sourceDatabase).grantIfNeeded();

      final sourceTransferService = SaveDataTransferService(
        sourceDatabase,
        locationPointIdSource: _FakeLocationPointIdSource(),
      );
      final jsonWithMark = await sourceTransferService.exportToJsonString();

      final targetDatabase = GameDatabase.forTesting();
      addTearDown(targetDatabase.close);
      final targetTransferService = SaveDataTransferService(
        targetDatabase,
        locationPointIdSource: _FakeLocationPointIdSource(),
      );
      await targetTransferService.importFromJsonString(
        jsonWithMark,
        backupWriter: _FakeBackupWriter(),
      );

      final targetGrant = TutorialStartingResourcesGrant(targetDatabase);
      final granted = await targetGrant.grantIfNeeded();

      expect(granted, isFalse, reason: '印を含むファイルを読み込んだ後は付与済みの状態が維持される');
      expect(
        await InventoryRepository(targetDatabase).amountOf(Resource.wood),
        startingResourceWoodAmount,
        reason: '二重付与されていない',
      );
      expect(
        await InventoryRepository(targetDatabase).amountOf(Resource.stone),
        startingResourceStoneAmount,
      );
    });
  });
}
