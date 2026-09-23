import 'package:omnia_ui/core/data/repository_exception.dart';

/// Synchronous storage behind asynchronous repository contracts.
/// Models must be immutable; returned lists cannot mutate this store.
class InMemoryDataSource<T> {
  InMemoryDataSource(Iterable<T> seed, {required this.idOf}) {
    for (final item in seed) {
      create(item);
    }
  }
  final String Function(T) idOf;
  final Map<String, T> _items = {};

  List<T> getAll() => List.unmodifiable(_items.values);

  T get(String id) {
    final item = _items[id];
    if (item == null) throw RepositoryException(RepositoryError.notFound, id);
    return item;
  }

  T create(T item) {
    final id = idOf(item);
    if (id.trim().isEmpty) throw ArgumentError.value(id, 'id');
    if (_items.containsKey(id)) {
      throw RepositoryException(RepositoryError.duplicateId, id);
    }
    _items[id] = item;
    return item;
  }

  T update(T item) {
    final id = idOf(item);
    get(id);
    _items[id] = item;
    return item;
  }

  void delete(String id) {
    get(id);
    _items.remove(id);
  }
}
