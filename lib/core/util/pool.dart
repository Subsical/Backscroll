import 'dart:async';
import 'dart:collection';

class Pool {
  Pool(this.size);

  int size;
  int _active = 0;
  final _waiting = Queue<Completer<void>>();

  int get active => _active;
  int get waiting => _waiting.length;

  Future<T> run<T>(Future<T> Function() task) async {
    await _acquire();
    try {
      return await task();
    } finally {
      _release();
    }
  }

  Future<void> _acquire() {
    if (_active < size) {
      _active++;
      return Future.value();
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    return waiter.future;
  }

  void _release() {
    if (_waiting.isNotEmpty && _active <= size) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }
}
