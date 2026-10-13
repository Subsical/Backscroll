import 'dart:async';
import 'dart:io';

import 'package:backscroll/core/media/providers/provider.dart';
import 'package:backscroll/core/media/upload_cache.dart';
import 'package:backscroll/core/media/upload_queue.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/scripted_provider.dart';

UploadTask task(
  String sha,
  List<UploadProvider> route, {
  String type = 'image/png',
}) => UploadTask(
  source: 'att:$sha',
  file: UploadFile(
    file: File('unused'),
    name: '$sha.png',
    size: 10,
    contentType: type,
    sha256: sha,
  ),
  route: route,
);

void main() {
  late UploadCache cache;
  late List<Duration> sleeps;
  late UploadQueue queue;

  setUp(() {
    cache = UploadCache.memory();
    sleeps = [];
    queue = UploadQueue(cache: cache, sleep: (d) async => sleeps.add(d));
  });

  test('retries retryable errors with growing backoff', () async {
    final flaky = ScriptedProvider(
      'flaky',
      script: (file, attempt) async {
        if (attempt < 3) throw UploadException('busy', retryable: true);
        return 'https://ok.example/a';
      },
    );
    final outcome = await queue.submit(task('a', [flaky]));
    expect(outcome.url, 'https://ok.example/a');
    expect(flaky.calls, 3);
    expect(sleeps, hasLength(2));
    expect(sleeps[1], greaterThan(sleeps[0]));
  });

  test('uses retry-after when the host sends one', () async {
    final limited = ScriptedProvider(
      'l',
      script: (file, attempt) async {
        if (attempt == 1) {
          throw UploadException(
            'slow down',
            retryable: true,
            retryAfter: const Duration(seconds: 42),
          );
        }
        return 'https://l.example/a';
      },
    );
    await queue.submit(task('a', [limited]));
    expect(sleeps.single, const Duration(seconds: 42));
  });

  test('falls through to the next provider on a hard failure', () async {
    final first = ScriptedProvider(
      'first',
      script: (_, _) async => throw UploadException('rejected'),
    );
    final second = ScriptedProvider('second');
    final outcome = await queue.submit(task('a', [first, second]));
    expect(outcome.providerId, 'second');
    expect(first.calls, 1);
    expect(queue.stats.done, 1);
  });

  test('reports failure when nobody takes the file', () async {
    final first = ScriptedProvider(
      'first',
      script: (_, _) async => throw UploadException('nope'),
    );
    final outcome = await queue.submit(task('a', [first]));
    expect(outcome.url, isNull);
    expect(outcome.error, contains('nope'));
    expect(queue.stats.failed, 1);
  });

  test('never uploads the same file twice', () async {
    final provider = ScriptedProvider('p');
    final results = await Future.wait([
      queue.submit(task('same', [provider])),
      queue.submit(task('same', [provider])),
    ]);
    expect(results.map((r) => r.url).toSet(), hasLength(1));
    await queue.submit(task('same', [provider]));
    expect(provider.calls, 1);
    expect(cache.bySource('att:same', ['p']), isNotNull);
  });

  test('keeps to the per provider concurrency limit', () async {
    final gate = Completer<void>();
    final provider = ScriptedProvider(
      'p',
      concurrency: 2,
      script: (file, _) async {
        await gate.future;
        return 'https://p.example/${file.sha256}';
      },
    );
    final futures = [
      for (var i = 0; i < 6; i++) queue.submit(task('f$i', [provider])),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(provider.running, 2);
    expect(queue.stats.waiting, 4);
    gate.complete();
    await Future.wait(futures);
    expect(provider.peak, 2);
    expect(queue.stats.done, 6);
  });
}
