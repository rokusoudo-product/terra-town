import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

void main() {
  group('Inventory', () {
    test('初期状態では所持数0', () {
      final inventory = Inventory();
      expect(inventory.amountOf(Resource.wood), 0);
    });

    test('add で加算できる', () {
      final inventory = Inventory();
      final added = inventory.add(Resource.wood, 10);
      expect(added, 10);
      expect(inventory.amountOf(Resource.wood), 10);
    });

    test('add は複数回呼ぶと積み上がる', () {
      final inventory = Inventory();
      inventory.add(Resource.wood, 10);
      inventory.add(Resource.wood, 5);
      expect(inventory.amountOf(Resource.wood), 15);
    });

    test('consume で消費できる', () {
      final inventory = Inventory();
      inventory.add(Resource.wood, 10);
      final consumed = inventory.consume(Resource.wood, 4);
      expect(consumed, isTrue);
      expect(inventory.amountOf(Resource.wood), 6);
    });

    test('所持数が足りない場合 consume は false を返し、所持数を変更しない', () {
      final inventory = Inventory();
      inventory.add(Resource.wood, 3);
      final consumed = inventory.consume(Resource.wood, 4);
      expect(consumed, isFalse);
      expect(inventory.amountOf(Resource.wood), 3);
    });

    test('負の量の add・consume はエラーになる', () {
      final inventory = Inventory();
      expect(() => inventory.add(Resource.wood, -1), throwsArgumentError);
      expect(() => inventory.consume(Resource.wood, -1), throwsArgumentError);
    });

    group('上限（仮置き。正本は balance.csv・Issue #36）', () {
      test('指定なしの資材は defaultCap を上限として扱う', () {
        final inventory = Inventory();
        expect(inventory.capOf(Resource.wood), Inventory.defaultCap);
      });

      test('上限を超える加算は上限でクランプされる', () {
        final inventory = Inventory(caps: {Resource.wood: 10});
        final added = inventory.add(Resource.wood, 15);
        expect(added, 10);
        expect(inventory.amountOf(Resource.wood), 10);
      });

      test('既に上限に達している場合、追加の加算量は0', () {
        final inventory = Inventory(caps: {Resource.wood: 10});
        inventory.add(Resource.wood, 10);
        final added = inventory.add(Resource.wood, 5);
        expect(added, 0);
        expect(inventory.amountOf(Resource.wood), 10);
      });

      test('資材ごとに個別の上限を指定できる', () {
        final inventory = Inventory(
          caps: {Resource.wood: 10, Resource.stone: 20},
        );
        expect(inventory.capOf(Resource.wood), 10);
        expect(inventory.capOf(Resource.stone), 20);
        expect(inventory.capOf(Resource.iron), Inventory.defaultCap);
      });
    });
  });
}
