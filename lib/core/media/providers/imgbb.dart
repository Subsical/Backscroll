import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'provider.dart';

class ImgbbProvider extends UploadProvider {
  ImgbbProvider({
    required this.id,
    required this.apiKey,
    this.concurrency = 3,
    this.limit,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static final endpoint = Uri.https('api.imgbb.com', '/1/upload');
  static const sizeLimit = 32 * 1024 * 1024;
  static const imageTypes = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/bmp',
    'image/webp',
    'image/tiff',
    'image/heic',
    'image/heif',
    'image/avif',
  };

  @override
  final String id;
  final String apiKey;
  @override
  final int concurrency;
  final int? limit;
  final http.Client _client;

  @override
  String get name => 'ImgBB';

  @override
  bool get isPublic => true;

  @override
  int get maxBytes => min(limit ?? sizeLimit, sizeLimit);

  @override
  String? rejectReason(UploadFile file) {
    if (!imageTypes.contains(file.contentType.toLowerCase())) {
      return 'ImgBB only takes images';
    }
    if (file.size > maxBytes) return 'larger than the ImgBB limit';
    return null;
  }

  @override
  Future<String> upload(UploadFile file, {ProgressCallback? onProgress}) async {
    final request = http.MultipartRequest('POST', endpoint)
      ..fields['key'] = apiKey
      ..fields['name'] = file.name.contains('.')
          ? file.name.substring(0, file.name.lastIndexOf('.'))
          : file.name
      ..files.add(multipartFile('image', file, onProgress: onProgress));
    final response = await sendWithTimeout(_client, request);
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    final url = body is Map
        ? ((body['data'] as Map?)?['url'] as String?)
        : null;
    if (response.statusCode == 200 && url != null) return url;
    final message = body is Map
        ? ((body['error'] as Map?)?['message'] ?? body['status_txt'])
        : null;
    throw UploadException(
      'ImgBB: ${message ?? 'upload failed (${response.statusCode})'}',
      retryable: isRetryableStatus(response.statusCode),
      retryAfter: retryAfterHeader(response),
    );
  }

  @override
  void close() => _client.close();
}
