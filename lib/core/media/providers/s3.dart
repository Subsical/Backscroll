import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../../util/pool.dart';
import 'provider.dart';
import 'sigv4.dart';

class S3Settings {
  const S3Settings({
    required this.endpoint,
    required this.bucket,
    required this.accessKey,
    required this.secretKey,
    required this.publicBaseUrl,
    this.region = '',
    this.prefix = '',
    this.pathStyle = true,
  });

  final String endpoint;
  final String bucket;
  final String accessKey;
  final String secretKey;
  final String publicBaseUrl;
  final String region;
  final String prefix;
  final bool pathStyle;

  static String guessRegion(String endpoint) {
    final host = Uri.tryParse(endpoint)?.host ?? '';
    if (host.endsWith('.r2.cloudflarestorage.com')) return 'auto';
    final match = RegExp(
      r'^s3[.-]([a-z0-9-]+)\.(?:amazonaws\.com|backblazeb2\.com|wasabisys\.com)$',
    ).firstMatch(host);
    return match?[1] ?? 'us-east-1';
  }

  String get effectiveRegion =>
      region.trim().isEmpty ? guessRegion(endpoint) : region.trim();

  String? problem() {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return 'The endpoint must be an https:// URL';
    }
    if (bucket.trim().isEmpty) return 'Enter a bucket name';
    if (accessKey.trim().isEmpty || secretKey.trim().isEmpty) {
      return 'Enter the access key and secret';
    }
    final public = Uri.tryParse(publicBaseUrl.trim());
    if (public == null || !public.hasScheme || public.host.isEmpty) {
      return 'Enter the public base URL files are served from';
    }
    return null;
  }
}

class S3Provider extends UploadProvider {
  S3Provider({
    required this.id,
    required this.settings,
    this.concurrency = 4,
    this.partConcurrency = 3,
    this.multipartThreshold = 32 * 1024 * 1024,
    this.partSize = 16 * 1024 * 1024,
    this.limit,
    http.Client? client,
    this.label = 'S3',
  }) : _client = client ?? http.Client(),
       _signer = SigV4Signer(
         accessKey: settings.accessKey.trim(),
         secretKey: settings.secretKey.trim(),
         region: settings.effectiveRegion,
       );

  static const maxParts = 10000;

  @override
  final String id;
  final S3Settings settings;
  @override
  final int concurrency;
  final int partConcurrency;
  final int multipartThreshold;
  final int partSize;
  final int? limit;
  final http.Client _client;
  final SigV4Signer _signer;
  final String label;

  @override
  String get name => label;

  @override
  bool get isPublic => false;

  @override
  int? get maxBytes => limit;

  Uri get _endpoint => Uri.parse(settings.endpoint.trim());

  String get _host => settings.pathStyle
      ? _endpoint.host
      : '${settings.bucket.trim()}.${_endpoint.host}';

  String get _hostHeader =>
      _endpoint.hasPort ? '$_host:${_endpoint.port}' : _host;

  String objectKey(UploadFile file) {
    final safe = file.name
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    var prefix = settings.prefix.trim();
    if (prefix.isNotEmpty && !prefix.endsWith('/')) prefix = '$prefix/';
    if (prefix.startsWith('/')) prefix = prefix.substring(1);
    return '$prefix${file.sha256.substring(0, 16)}/${safe.isEmpty ? 'file' : safe}';
  }

  String publicUrl(String key) {
    var base = settings.publicBaseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return '$base/${awsEncode(key, keepSlash: true)}';
  }

  String _path(String key) {
    final encodedKey = awsEncode(key, keepSlash: true);
    final basePath = _endpoint.path.replaceAll(RegExp(r'/+$'), '');
    return settings.pathStyle
        ? '$basePath/${awsEncode(settings.bucket.trim())}/$encodedKey'
        : '$basePath/$encodedKey';
  }

  Uri _uri(String encodedPath, [Map<String, String> query = const {}]) {
    final queryString = (query.keys.toList()..sort())
        .map(
          (k) => query[k]!.isEmpty
              ? awsEncode(k)
              : '${awsEncode(k)}=${awsEncode(query[k]!)}',
        )
        .join('&');
    return Uri.parse(
      'https://$_hostHeader$encodedPath'
      '${queryString.isEmpty ? '' : '?$queryString'}',
    );
  }

  Map<String, String> _signed(
    String method,
    String path, {
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    String payloadHash = emptyPayloadHash,
  }) => _signer.sign(
    method: method,
    host: _hostHeader,
    encodedPath: path,
    query: query,
    headers: headers,
    payloadHash: payloadHash,
  );

  @override
  String? rejectReason(UploadFile file) {
    final max = maxBytes;
    if (max != null && file.size > max) {
      return 'larger than the limit for $name';
    }
    return null;
  }

  UploadException _error(http.Response response, String action) {
    var detail = 'HTTP ${response.statusCode}';
    try {
      final doc = XmlDocument.parse(response.body);
      final code = doc.findAllElements('Code').firstOrNull?.innerText;
      final message = doc.findAllElements('Message').firstOrNull?.innerText;
      if (code != null) detail = message == null ? code : '$code: $message';
    } on XmlException {
      if (response.body.trim().isNotEmpty && response.body.length < 200) {
        detail = response.body.trim();
      }
    }
    return UploadException(
      '$name could not $action ($detail)',
      retryable: isRetryableStatus(response.statusCode),
      retryAfter: retryAfterHeader(response),
    );
  }

  Future<bool> _exists(String key, int size) async {
    final path = _path(key);
    final request = http.Request('HEAD', _uri(path))
      ..headers.addAll(_signed('HEAD', path));
    try {
      final response = await sendWithTimeout(
        _client,
        request,
        timeout: const Duration(seconds: 30),
      );
      return response.statusCode == 200 &&
          int.tryParse(response.headers['content-length'] ?? '') == size;
    } on UploadException {
      return false;
    }
  }

  @override
  Future<String> upload(UploadFile file, {ProgressCallback? onProgress}) async {
    final key = objectKey(file);
    if (await _exists(key, file.size)) {
      onProgress?.call(file.size);
      return publicUrl(key);
    }
    if (file.size > multipartThreshold) {
      await _multipart(file, key, onProgress);
    } else {
      await _put(file, key, onProgress);
    }
    return publicUrl(key);
  }

  Map<String, String> get _objectHeaders => const {
    'cache-control': 'public, max-age=31536000, immutable',
  };

  Future<void> _put(
    UploadFile file,
    String key,
    ProgressCallback? onProgress,
  ) async {
    final path = _path(key);
    final request = http.StreamedRequest('PUT', _uri(path))
      ..contentLength = file.size
      ..headers.addAll(
        _signed('PUT', path, headers: _objectHeaders, payloadHash: file.sha256),
      )
      ..headers['content-type'] = file.contentType;
    final sending = sendWithTimeout(_client, request);
    try {
      await request.sink.addStream(
        countingStream(file.file.openRead(), onProgress),
      );
    } on Exception {
      // the response says why
    } finally {
      await request.sink.close();
    }
    final response = await sending;
    if (response.statusCode != 200) throw _error(response, 'store the file');
  }

  Future<void> _multipart(
    UploadFile file,
    String key,
    ProgressCallback? onProgress,
  ) async {
    final path = _path(key);
    final start = await sendWithTimeout(
      _client,
      http.Request('POST', _uri(path, {'uploads': ''}))
        ..headers.addAll(
          _signed(
            'POST',
            path,
            query: {'uploads': ''},
            headers: _objectHeaders,
          ),
        )
        ..headers['content-type'] = file.contentType,
    );
    if (start.statusCode != 200) throw _error(start, 'start the upload');
    final uploadId = XmlDocument.parse(start.body)
        .findAllElements('UploadId')
        .firstOrNull
        ?.innerText;
    if (uploadId == null) {
      throw UploadException('$name did not return an upload id');
    }

    final size = max(partSize, (file.size / (maxParts - 1)).ceil());
    final count = (file.size / size).ceil();
    final etags = List<String?>.filled(count, null);
    final sent = List<int>.filled(count, 0);
    final pool = Pool(partConcurrency);
    final reader = await file.file.open();
    try {
      await Future.wait([
        for (var i = 0; i < count; i++)
          pool.run(() async {
            final offset = i * size;
            final length = min(size, file.size - offset);
            final bytes = await _readRange(reader, offset, length);
            final query = {'partNumber': '${i + 1}', 'uploadId': uploadId};
            final request = http.Request('PUT', _uri(path, query))
              ..headers.addAll(
                _signed(
                  'PUT',
                  path,
                  query: query,
                  payloadHash: hexSha256(bytes),
                ),
              )
              ..bodyBytes = bytes;
            final response = await sendWithTimeout(_client, request);
            if (response.statusCode != 200) {
              throw _error(response, 'store part ${i + 1}');
            }
            etags[i] = response.headers['etag'];
            sent[i] = length;
            onProgress?.call(sent.fold(0, (a, b) => a + b));
          }),
      ]);
      final body = XmlBuilder();
      body.element(
        'CompleteMultipartUpload',
        nest: () {
          for (var i = 0; i < count; i++) {
            body.element(
              'Part',
              nest: () {
                body.element('PartNumber', nest: '${i + 1}');
                body.element('ETag', nest: etags[i] ?? '');
              },
            );
          }
        },
      );
      final xml = body.buildDocument().toXmlString();
      final query = {'uploadId': uploadId};
      final done = await sendWithTimeout(
        _client,
        http.Request('POST', _uri(path, query))
          ..headers.addAll(
            _signed(
              'POST',
              path,
              query: query,
              payloadHash: hexSha256(utf8.encode(xml)),
            ),
          )
          ..headers['content-type'] = 'application/xml'
          ..body = xml,
      );
      // s3 can return 200 with an error in the body
      if (done.statusCode != 200 || done.body.contains('<Error>')) {
        throw _error(done, 'finish the upload');
      }
    } catch (_) {
      final query = {'uploadId': uploadId};
      final abort = http.Request('DELETE', _uri(path, query))
        ..headers.addAll(_signed('DELETE', path, query: query));
      try {
        await sendWithTimeout(
          _client,
          abort,
          timeout: const Duration(seconds: 30),
        );
      } on UploadException {
        // the bucket's lifecycle rules clean these up
      }
      rethrow;
    } finally {
      await reader.close();
    }
  }

  Future<List<int>> _readRange(
    RandomAccessFile reader,
    int offset,
    int length,
  ) async {
    // parts are read from one shared file handle
    return _readLock = _readLock.then((_) async {
      await reader.setPosition(offset);
      return reader.read(length);
    });
  }

  Future<List<int>> _readLock = Future.value(const []);

  @override
  void close() => _client.close();
}
