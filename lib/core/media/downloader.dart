import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../discord/rate_limiter.dart';

class DownloadResult {
  const DownloadResult(this.path, this.size, this.sha256, this.contentType);

  final String path;
  final int size;
  final String sha256;
  final String? contentType;
}

class DownloadException implements Exception {
  DownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

Future<String> hashFile(File file) async {
  final sink = _DigestSink();
  final input = sha256.startChunkedConversion(sink);
  await for (final chunk in file.openRead()) {
    input.add(chunk);
  }
  input.close();
  return sink.value.toString();
}

class MediaDownloader {
  MediaDownloader({http.Client? client, Sleeper? sleep, this.maxAttempts = 4})
    : _client = client ?? http.Client(),
      _sleep = sleep ?? realSleep;

  final http.Client _client;
  final Sleeper _sleep;
  final int maxAttempts;
  final _random = Random();

  Duration _backoff(int attempt) =>
      Duration(milliseconds: 800 * (1 << attempt) + _random.nextInt(400));

  Future<DownloadResult> download(String url, String path) async {
    final uri = Uri.parse(url);
    final temp = File('$path.download');
    await temp.parent.create(recursive: true);
    for (var attempt = 1; ; attempt++) {
      try {
        final response = await _client
            .send(http.Request('GET', uri))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode != 200) {
          await response.stream.drain<void>();
          final status = response.statusCode;
          final retry = status == 408 || status == 429 || status >= 500;
          if (!retry || attempt >= maxAttempts) {
            throw DownloadException('HTTP $status');
          }
          await _sleep(_backoff(attempt));
          continue;
        }
        final digest = _DigestSink();
        final hasher = sha256.startChunkedConversion(digest);
        final out = temp.openWrite();
        var size = 0;
        try {
          await for (final chunk in response.stream.timeout(
            const Duration(seconds: 60),
          )) {
            out.add(chunk);
            hasher.add(chunk);
            size += chunk.length;
          }
        } finally {
          await out.close();
        }
        hasher.close();
        await temp.rename(path);
        return DownloadResult(
          path,
          size,
          digest.value.toString(),
          response.headers['content-type']?.split(';').first.trim(),
        );
      } on DownloadException {
        rethrow;
      } on Exception catch (e) {
        final network =
            e is TimeoutException ||
            e is SocketException ||
            e is http.ClientException ||
            e is HandshakeException;
        if (!network || attempt >= maxAttempts) {
          if (await temp.exists()) await temp.delete();
          throw DownloadException(network ? 'Network error' : '$e');
        }
        await _sleep(_backoff(attempt));
      }
    }
  }

  void close() => _client.close();
}
