import 'package:backscroll/core/media/providers/sigv4.dart';
import 'package:flutter_test/flutter_test.dart';

// examples from the aws docs on signing s3 requests
void main() {
  final signer = SigV4Signer(
    accessKey: 'AKIAIOSFODNN7EXAMPLE',
    secretKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    region: 'us-east-1',
  );
  final when = DateTime.utc(2013, 5, 24);
  const host = 'examplebucket.s3.amazonaws.com';

  String signature(Map<String, String> headers) =>
      headers['authorization']!.split('Signature=').last;

  test('get object', () {
    final headers = signer.sign(
      method: 'GET',
      host: host,
      encodedPath: '/test.txt',
      headers: {'Range': 'bytes=0-9'},
      payloadHash: emptyPayloadHash,
      now: when,
    );
    expect(
      headers['authorization'],
      contains('SignedHeaders=host;range;x-amz-content-sha256;x-amz-date'),
    );
    expect(
      signature(headers),
      'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41',
    );
  });

  test('put object', () {
    final headers = signer.sign(
      method: 'PUT',
      host: host,
      encodedPath: '/${awsEncode(r'test$file.text', keepSlash: true)}',
      headers: {
        'Date': 'Fri, 24 May 2013 00:00:00 GMT',
        'x-amz-storage-class': 'REDUCED_REDUNDANCY',
      },
      payloadHash:
          '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072',
      now: when,
    );
    expect(
      signature(headers),
      '98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd',
    );
  });

  test('list objects with a query', () {
    final headers = signer.sign(
      method: 'GET',
      host: host,
      encodedPath: '/',
      query: {'max-keys': '2', 'prefix': 'J'},
      payloadHash: emptyPayloadHash,
      now: when,
    );
    expect(
      signature(headers),
      '34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7',
    );
  });

  test('encodes like S3 expects', () {
    expect(awsEncode('a b/c~d', keepSlash: true), 'a%20b/c~d');
    expect(awsEncode('a b/c'), 'a%20b%2Fc');
    expect(awsEncode('\u{E9}'), '%C3%A9');
  });
}
