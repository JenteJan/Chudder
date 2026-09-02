import 'dart:math';

import 'package:collection/collection.dart';

extension ListExtensions<T> on List<T> {
  void reorderInPlace(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) {
      return;
    }

    final item = removeAt(oldIndex);
    final targetIndex = (oldIndex < newIndex ? newIndex - 1 : newIndex).clamp(0, length);
    insert(targetIndex, item);
  }

  List<T> reordered(int oldIndex, int newIndex) {
    final updatedList = toList();
    updatedList.reorderInPlace(oldIndex, newIndex);
    return updatedList;
  }

  List<T> replace(T entry) {
    var tempList = toList();
    final index = indexOf(entry);
    tempList.removeAt(index);
    tempList.insert(index, entry);
    return tempList;
  }

  List<T> toggle(T entry) {
    var tempList = toList();
    if (contains(entry)) {
      return tempList..remove(entry);
    } else {
      return tempList..add(entry);
    }
  }

  bool containsAny(Iterable<T> entries) {
    for (var value in entries) {
      if (contains(value)) {
        return true;
      }
    }
    return false;
  }

  List<T> toggleUnique(T entry) => toggle(entry).toSet().toList();

  /// A shuffled copy. It used to shuffle this list itself, so a model's own
  /// list changed order under whoever else was holding it.
  List<T> random() => toList()..shuffle();

  List<T> uniqueBy(dynamic Function(T value) keySelector) {
    final Map<dynamic, T> uniqueMap = {};

    for (var item in this) {
      final key = keySelector(item);
      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = item;
      }
    }

    return uniqueMap.values.toList();
  }

  List<R> mapWithLast<R>(R Function(T value, bool last) mapper) {
    return mapIndexed((index, e) => mapper(e, index == length - 1)).toList();
  }

  Iterable<List<T>> chunk(int size) sync* {
    if (size <= 0) {
      throw ArgumentError('Chunk size must be greater than zero.');
    }

    final iterator = this.iterator;
    while (iterator.moveNext()) {
      final chunk = <T>[];
      for (var i = 0; i < size; i++) {
        if (!iterator.moveNext()) {
          break;
        }
        chunk.add(iterator.current);
      }
      yield chunk;
    }
  }

  T? nextOrNull(T item) {
    final indexOf = this.indexOf(item);
    if (indexOf == -1) return null;
    final nextIndex = indexOf + 1;
    if (nextIndex >= length) return null;
    return elementAtOrNull(nextIndex);
  }

  T? previousOrNull(T item) {
    final indexOf = this.indexOf(item);
    if (indexOf == -1) return null;
    final prevIndex = indexOf - 1;
    if (prevIndex < 0) return null;
    return elementAtOrNull(prevIndex);
  }

  T? nextWhereOrNull(bool Function(T element) test) {
    final indexOf = indexWhere((element) => test(element));
    if (indexOf == -1) return null;
    final nextIndex = indexOf + 1;
    if (nextIndex >= length) return null;
    return elementAtOrNull(nextIndex);
  }

  T? previousWhereOrNull(bool Function(T element) test) {
    final indexOf = indexWhere((element) => test(element));
    if (indexOf == -1) return null;
    final prevIndex = indexOf - 1;
    if (prevIndex < 0) return null;
    return elementAtOrNull(prevIndex);
  }
}

extension AsyncIterableExtensions<T> on Iterable<T> {
  /// [Future.wait] over a mapped list, but with at most [concurrency] of them
  /// running at a time, in order.
  ///
  /// Handing a whole library to `Future.wait` fires one request per item at
  /// once: hundreds of sockets, and every response parsed in the same
  /// stampede, which is enough to hang or kill the app on a phone.
  Future<List<R>> mapConcurrent<R>(int concurrency, Future<R> Function(T item) worker) async {
    final items = toList();
    if (items.isEmpty) return <R>[];

    final results = List<R?>.filled(items.length, null);
    var next = 0;

    Future<void> runner() async {
      while (true) {
        final index = next++;
        if (index >= items.length) return;
        results[index] = await worker(items[index]);
      }
    }

    await Future.wait(List.generate(min(concurrency, items.length), (_) => runner()));
    return results.map((value) => value as R).toList();
  }
}
