class EtaEstimator {
  EtaEstimator({this.window = const Duration(seconds: 60)});

  final Duration window;
  final _samples = <(int, double)>[];

  void reset() => _samples.clear();

  Duration? update(double fraction, {DateTime? now}) {
    final t = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _samples.add((t, fraction));
    while (_samples.length > 2 &&
        t - _samples.first.$1 > window.inMilliseconds) {
      _samples.removeAt(0);
    }
    if (_samples.length < 2) return null;
    final (t0, f0) = _samples.first;
    final elapsed = t - t0;
    final done = fraction - f0;
    if (elapsed <= 0 || done <= 0) return null;
    return Duration(milliseconds: ((1 - fraction) * elapsed / done).round());
  }
}
