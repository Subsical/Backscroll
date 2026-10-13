import 'dart:convert';

import 'package:crypto/crypto.dart';

const emptyPayloadHash =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

String hexSha256(List<int> bytes) => sha256.convert(bytes).toString();

String awsEncode(String value, {bool keepSlash = false}) {
  final out = StringBuffer();
  for (final byte in utf8.encode(value)) {
    final unreserved =
        (byte >= 0x41 && byte <= 0x5A) ||
        (byte >= 0x61 && byte <= 0x7A) ||
        (byte >= 0x30 && byte <= 0x39) ||
        byte == 0x2D ||
        byte == 0x2E ||
        byte == 0x5F ||
        byte == 0x7E ||
        (keepSlash && byte == 0x2F);
    if (unreserved) {
      out.writeCharCode(byte);
    } else {
      out.write('%${byte.toRadixString(16).toUpperCase().padLeft(2, '0')}');
    }
  }
  return out.toString();
}

String _two(int v) => v.toString().padLeft(2, '0');

class SigV4Signer {
  SigV4Signer({
    required this.accessKey,
    required this.secretKey,
    required this.region,
    this.service = 's3',
  });

  final String accessKey;
  final String secretKey;
  final String region;
  final String service;

  static String amzDate(DateTime time) {
    final t = time.toUtc();
    return '${t.year}${_two(t.month)}${_two(t.day)}T'
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}Z';
  }

  // path must already be encoded, query values are passed raw
  Map<String, String> sign({
    required String method,
    required String host,
    required String encodedPath,
    Map<String, String> query = const {},
    Map<String, String> headers = const {},
    required String payloadHash,
    DateTime? now,
  }) {
    final date = amzDate(now ?? DateTime.now());
    final day = date.substring(0, 8);
    final all = <String, String>{
      for (final e in headers.entries) e.key.toLowerCase(): e.value.trim(),
      'host': host,
      'x-amz-content-sha256': payloadHash,
      'x-amz-date': date,
    };
    final names = all.keys.toList()..sort();
    final canonicalHeaders = names.map((n) => '$n:${all[n]}\n').join();
    final signedHeaders = names.join(';');
    final queryKeys = query.keys.toList()..sort();
    final canonicalQuery = queryKeys
        .map((k) => '${awsEncode(k)}=${awsEncode(query[k]!)}')
        .join('&');
    final canonicalRequest = [
      method,
      encodedPath.isEmpty ? '/' : encodedPath,
      canonicalQuery,
      canonicalHeaders,
      signedHeaders,
      payloadHash,
    ].join('\n');
    final scope = '$day/$region/$service/aws4_request';
    final stringToSign = [
      'AWS4-HMAC-SHA256',
      date,
      scope,
      hexSha256(utf8.encode(canonicalRequest)),
    ].join('\n');
    List<int> hmacBytes(List<int> key, String data) =>
        Hmac(sha256, key).convert(utf8.encode(data)).bytes;
    var key = hmacBytes(utf8.encode('AWS4$secretKey'), day);
    key = hmacBytes(key, region);
    key = hmacBytes(key, service);
    key = hmacBytes(key, 'aws4_request');
    final signature = Hmac(
      sha256,
      key,
    ).convert(utf8.encode(stringToSign)).toString();
    return {
      for (final e in all.entries)
        if (e.key != 'host') e.key: e.value,
      'authorization':
          'AWS4-HMAC-SHA256 Credential=$accessKey/$scope, '
          'SignedHeaders=$signedHeaders, Signature=$signature',
    };
  }
}
