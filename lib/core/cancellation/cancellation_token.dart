class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    final listeners = List<void Function()>.from(_listeners);
    for (final listener in listeners) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw const OperationCancelledException();
    }
  }
}

class OperationCancelledException implements Exception {
  const OperationCancelledException();

  @override
  String toString() => 'OperationCancelledException';
}
