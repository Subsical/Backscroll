import 'dart:math';

import 'package:http/http.dart' as http;

import 'provider.dart';

class CatboxProvider extends UploadProvider {
  CatboxProvider({
    required this.id,
    this.userhash = '',
    this.concurrency = 2,
    this.limit,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static final endpoint = Uri.https('catbox.moe', '/user/api.php');
  static const sizeLimit = 200 * 1024 * 1024;
  static const gifLimit = 20 * 1024 * 1024;
  static const blockedExtensions = {'exe', 'scr', 'cpl', 'jar'};

  @override
  final String id;
  final String userhash;
  @override
  final int concurrency;
  final int? limit;
  final http.Client _client;

  @override
  String get name => 'Catbox';

  @override
  bool get isPublic => true;

  @override
  int get maxBytes => min(limit ?? sizeLimit, sizeLimit);

  @override
  String? rejectReason(UploadFile file) {
    final ext = file.extension;
    if (file.size > maxBytes) return 'larger than the Catbox limit';
    if (blockedExtensions.contains(ext) || ext.startsWith('doc')) {
      return 'Catbox does not take .$ext files';
    }
    if (ext == 'gif' && file.size > gifLimit) {
      return 'Catbox rejects GIFs over 20 MB';
    }
    return null;
  }

  @override
  Future<String> upload(UploadFile file, {ProgressCallback? onProgress}) async {
    final request = http.MultipartRequest('POST', endpoint)
      ..fields['reqtype'] = 'fileupload'
      ..fields['userhash'] = userhash
      ..files.add(multipartFile('fileToUpload', file, onProgress: onProgress));
    final response = await sendWithTimeout(_client, request);
    final body = response.body.trim();
    if (response.statusCode == 200 && body.startsWith('https://')) return body;
    throw UploadException(
      body.isEmpty ? 'Catbox returned ${response.statusCode}' : 'Catbox: $body',
      retryable: isRetryableStatus(response.statusCode),
      retryAfter: retryAfterHeader(response),
    );
  }

  @override
  void close() => _client.close();
}
