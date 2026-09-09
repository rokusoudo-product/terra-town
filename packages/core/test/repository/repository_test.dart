import 'package:terra_town_core/terra_town_core.dart';
import 'package:test/test.dart';

/// テスト専用の最小エンティティ。ドメインモデル（`Inventory`・`Building` 等）は
/// 別タスク（T026〜T037）の担当であり、本テストは `Repository<T, ID>` という
/// 契約そのものをオンメモリのフェイクで満たせることだけを確認する。
class _Note {
  const _Note(this.id, this.text);

  final String id;
  final String text;

  @override
  bool operator ==(Object other) => other is _Note && other.id == id && other.text == text;

  @override
  int get hashCode => Object.hash(id, text);
}

/// 将来 SQLite（`location`/`app`）やサーバ同期（Issue #16）に差し替わる想定の
/// オンメモリ実装。`Repository<T, ID>` を満たしていることの実証用フェイク。
class InMemoryRepository<T, ID> implements Repository<T, ID> {
  final Map<ID, T> _store = {};

  InMemoryRepository(ID Function(T) idOf) : _idOf = idOf;

  final ID Function(T) _idOf;

  @override
  Future<T?> findById(ID id) async => _store[id];

  @override
  Future<List<T>> findAll() async => _store.values.toList();

  @override
  Future<void> save(T entity) async => _store[_idOf(entity)] = entity;

  @override
  Future<void> delete(ID id) async => _store.remove(id);
}

void main() {
  group('Repository', () {
    test('save したエンティティを findById で取得できる', () async {
      final Repository<_Note, String> repo = InMemoryRepository<_Note, String>((n) => n.id);

      await repo.save(const _Note('1', 'hello'));

      expect(await repo.findById('1'), const _Note('1', 'hello'));
    });

    test('存在しない id では findById が null を返す', () async {
      final Repository<_Note, String> repo = InMemoryRepository<_Note, String>((n) => n.id);

      expect(await repo.findById('does-not-exist'), isNull);
    });

    test('findAll は保存済みの全エンティティを返す', () async {
      final Repository<_Note, String> repo = InMemoryRepository<_Note, String>((n) => n.id);
      await repo.save(const _Note('1', 'a'));
      await repo.save(const _Note('2', 'b'));

      final all = await repo.findAll();

      expect(all, containsAll(const [_Note('1', 'a'), _Note('2', 'b')]));
      expect(all, hasLength(2));
    });

    test('delete したエンティティは findById で取得できなくなる', () async {
      final Repository<_Note, String> repo = InMemoryRepository<_Note, String>((n) => n.id);
      await repo.save(const _Note('1', 'a'));

      await repo.delete('1');

      expect(await repo.findById('1'), isNull);
    });

    test('同一 id で save すると上書きされる', () async {
      final Repository<_Note, String> repo = InMemoryRepository<_Note, String>((n) => n.id);
      await repo.save(const _Note('1', 'old'));

      await repo.save(const _Note('1', 'new'));

      expect(await repo.findById('1'), const _Note('1', 'new'));
      expect(await repo.findAll(), hasLength(1));
    });
  });
}
