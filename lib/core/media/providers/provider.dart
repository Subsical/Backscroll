import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class UploadFile {
  const UploadFile({
    required this.file,
    required this.name,
    required this.size,
    required this.contentType,
    required this.sha256,
  });

  final File file;
  final String name;
  final int size;
  final String contentType;
  final String sha256;

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool get isImage => contentType.startsWith('image/');
}

class UploadException implements Exception {
  UploadException(this.message, {this.retryable = false, this.retryAfter});

  final String message;
  final bool retryable;
  final Duration? retryAfter;

  @override
  String toString() => message;
}

typedef ProgressCallback = void Function(int sent);

abstract class UploadProvider {
  String get id;
  String get name;
  int get concurrency;
  int? get maxBytes;
  bool get isPublic;

  String? rejectReason(UploadFile file);

  Future<String> upload(UploadFile file, {ProgressCallback? onProgress});

  void close() {}
}

Stream<List<int>> countingStream(
  Stream<List<int>> source,
  ProgressCallback? onProgress,
) {
  var sent = 0;
  return source.map((chunk) {
    sent += chunk.length;
    onProgress?.call(sent);
    return chunk;
  });
}

MediaType mediaType(String contentType) {
  try {
    return MediaType.parse(contentType);
  } on FormatException {
    return MediaType('application', 'octet-stream');
  }
}

http.MultipartFile multipartFile(
  String field,
  UploadFile file, {
  ProgressCallback? onProgress,
}) => http.MultipartFile(
  field,
  countingStream(file.file.openRead(), onProgress),
  file.size,
  filename: file.name,
  contentType: mediaType(file.contentType),
);

Duration? retryAfterHeader(http.BaseResponse response) {
  final value = int.tryParse(response.headers['retry-after'] ?? '');
  return value == null ? null : Duration(seconds: value);
}

bool isRetryableStatus(int status) =>
    status == 408 || status == 429 || status >= 500;

Future<http.Response> sendWithTimeout(
  http.Client client,
  http.BaseRequest request, {
  Duration timeout = const Duration(minutes: 30),
}) async {
  try {
    final streamed = await client.send(request).timeout(timeout);
    return await http.Response.fromStream(streamed).timeout(timeout);
  } on TimeoutException {
    throw UploadException('The upload timed out', retryable: true);
  } on SocketException catch (e) {
    throw UploadException('Network error: ${e.message}', retryable: true);
  } on http.ClientException catch (e) {
    throw UploadException('Network error: ${e.message}', retryable: true);
  } on HandshakeException catch (e) {
    throw UploadException('TLS error: ${e.message}', retryable: true);
  }
}
