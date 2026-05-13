import 'dart:async';

class AutoLockService {
  AutoLockService({required this.timeout, required void Function() onLock})
    : _onLock = onLock;

  final Duration timeout;
  final void Function() _onLock;
  Timer? _timer;
  bool _disposed = false;

  void recordActivity() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();
    _timer = Timer(timeout, lockNow);
  }

  void lockNow() {
    if (_disposed) {
      return;
    }

    _timer?.cancel();
    _timer = null;
    _onLock();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
