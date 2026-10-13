import 'dart:async';

typedef Sleeper = Future<void> Function(Duration duration);

Future<void> realSleep(Duration duration) => Future.delayed(duration);

class _Bucket {
  int remaining = 1;
  DateTime resetAt = DateTime.fromMillisecondsSinceEpoch(0);
}

class RateLimiter {
  RateLimiter({DateTime Function()? clock, Sleeper? sleep})
    : _clock = clock ?? DateTime.now,
      _sleep = sleep ?? realSleep;

  final DateTime Function() _clock;
  final Sleeper _sleep;
  final _routeBuckets = <String, String>{};
  final _buckets = <String, _Bucket>{};
  DateTime _globalUntil = DateTime.fromMillisecondsSinceEpoch(0);

  void Function(Duration wait)? onWait;

  String _key(String route) {
    final hash = _routeBuckets[route];
    return hash == null ? route : '$hash|$route';
  }

  Future<void> acquire(String route) async {
    while (true) {
      final now = _clock();
      var wait = _globalUntil.difference(now);
      final bucket = _buckets[_key(route)];
      if (bucket != null && bucket.remaining <= 0) {
        final untilReset = bucket.resetAt.difference(now);
        if (untilReset > wait) wait = untilReset;
        if (untilReset <= Duration.zero) bucket.remaining = 1;
      }
      if (wait <= Duration.zero) {
        if (bucket != null) bucket.remaining--;
        return;
      }
      onWait?.call(wait);
      await _sleep(wait + const Duration(milliseconds: 50));
    }
  }

  // Discord shares a bucket hash between routes with the same limit, but the
  // actual counter is per hash and major parameter, which the route key holds.
  void update(String route, Map<String, String> headers) {
    final hash = headers['x-ratelimit-bucket'];
    final remaining = int.tryParse(headers['x-ratelimit-remaining'] ?? '');
    final resetAfter = double.tryParse(
      headers['x-ratelimit-reset-after'] ?? '',
    );
    if (remaining == null || resetAfter == null) return;
    if (hash != null) _routeBuckets[route] = hash;
    final bucket = _buckets.putIfAbsent(_key(route), _Bucket.new);
    bucket.remaining = remaining;
    bucket.resetAt = _clock().add(
      Duration(milliseconds: (resetAfter * 1000).ceil()),
    );
  }

  void tooManyRequests(
    String route,
    Duration retryAfter, {
    bool global = false,
  }) {
    final until = _clock().add(retryAfter);
    if (global) {
      if (until.isAfter(_globalUntil)) _globalUntil = until;
      return;
    }
    final bucket = _buckets.putIfAbsent(_key(route), _Bucket.new);
    bucket.remaining = 0;
    if (until.isAfter(bucket.resetAt)) bucket.resetAt = until;
  }
}
