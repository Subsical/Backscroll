import 'dart:convert';
import 'dart:io';

import 'package:backscroll/core/media/downloader.dart';
import 'package:backscroll/core/media/providers/catbox.dart';
import 'package:backscroll/core/media/providers/imgbb.dart';
import 'package:backscroll/core/media/providers/provider.dart';
import 'package:backscroll/core/media/providers/s3.dart';
import 'package:backscroll/core/media/providers/sharex.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

late Directory temp;

Future<UploadFile> makeFile(String name, List<int> bytes, String type) async {
  final file = File('${temp.path}/$name')..writeAsBytesSync(bytes);
  return UploadFile(
    file: file,
    name: name,
    size: bytes.length,
    contentType: type,
    sha256: await hashFile(file),
  );
}

UploadFile fakeFile(String name, int size, String type) => UploadFile(
  file: File('missing'),
  name: name,
  size: size,
  contentType: type,
  sha256: 'x' * 64,
);

String body(http.Request request) =>
    utf8.decode(request.bodyBytes, allowMalformed: true);

void main() {
  setUp(() => temp = Directory.systemTemp.createTempSync('providers'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('catbox', () {
    final catbox = CatboxProvider(
      id: 'c',
      client: MockClient((_) async => http.Response('', 500)),
    );

    test('applies the host rules', () {
      expect(catbox.rejectReason(fakeFile('a.png', 1000, 'image/png')), isNull);
      expect(
        catbox.rejectReason(
          fakeFile('setup.exe', 10, 'application/x-msdownload'),
        ),
        isNotNull,
      );
      expect(
        catbox.rejectReason(fakeFile('notes.docx', 10, 'application/msword')),
        isNotNull,
      );
      expect(
        catbox.rejectReason(
          fakeFile('tool.jar', 10, 'application/java-archive'),
        ),
        isNotNull,
      );
      expect(
        catbox.rejectReason(fakeFile('big.gif', 21 << 20, 'image/gif')),
        isNotNull,
      );
      expect(
        catbox.rejectReason(fakeFile('small.gif', 19 << 20, 'image/gif')),
        isNull,
      );
      expect(
        catbox.rejectReason(fakeFile('huge.zip', 201 << 20, 'application/zip')),
        isNotNull,
      );
    });

    test('posts the documented form fields', () async {
      late http.Request seen;
      final provider = CatboxProvider(
        id: 'c',
        userhash: 'hash123',
        client: MockClient((request) async {
          seen = request;
          return http.Response('https://files.catbox.moe/abc123.png', 200);
        }),
      );
      final file = await makeFile('pic.png', [1, 2, 3], 'image/png');
      expect(
        await provider.upload(file),
        'https://files.catbox.moe/abc123.png',
      );
      expect(seen.url.toString(), 'https://catbox.moe/user/api.php');
      final form = body(seen);
      expect(form, contains('name="reqtype"\r\n\r\nfileupload'));
      expect(form, contains('name="userhash"\r\n\r\nhash123'));
      expect(form, contains('name="fileToUpload"; filename="pic.png"'));
    });

    test('server errors are retryable, rejections are not', () async {
      final file = await makeFile('a.txt', [1], 'text/plain');
      final busy = CatboxProvider(
        id: 'c',
        client: MockClient((_) async => http.Response('down', 503)),
      );
      final refused = CatboxProvider(
        id: 'c',
        client: MockClient(
          (_) async => http.Response('File type not allowed', 412),
        ),
      );
      await expectLater(
        busy.upload(file),
        throwsA(predicate((e) => e is UploadException && e.retryable)),
      );
      await expectLater(
        refused.upload(file),
        throwsA(predicate((e) => e is UploadException && !e.retryable)),
      );
    });
  });

  group('imgbb', () {
    test('only takes images up to 32 MB', () {
      final imgbb = ImgbbProvider(id: 'i', apiKey: 'k');
      expect(imgbb.rejectReason(fakeFile('a.jpg', 1000, 'image/jpeg')), isNull);
      expect(
        imgbb.rejectReason(fakeFile('a.mp4', 1000, 'video/mp4')),
        isNotNull,
      );
      expect(
        imgbb.rejectReason(fakeFile('a.png', 33 << 20, 'image/png')),
        isNotNull,
      );
    });

    test('returns data.url and surfaces api errors', () async {
      late http.Request seen;
      final ok = ImgbbProvider(
        id: 'i',
        apiKey: 'secret',
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'data': {'url': 'https://i.ibb.co/x/pic.png'},
              'success': true,
            }),
            200,
          );
        }),
      );
      final file = await makeFile('pic.png', [1, 2], 'image/png');
      expect(await ok.upload(file), 'https://i.ibb.co/x/pic.png');
      expect(seen.url.toString(), 'https://api.imgbb.com/1/upload');
      expect(body(seen), contains('name="key"\r\n\r\nsecret'));
      expect(body(seen), contains('name="image"; filename="pic.png"'));

      final bad = ImgbbProvider(
        id: 'i',
        apiKey: 'k',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'Invalid API v1 key.'},
            }),
            400,
          ),
        ),
      );
      await expectLater(
        bad.upload(file),
        throwsA(predicate((e) => '$e'.contains('Invalid API v1 key'))),
      );
    });
  });

  group('sharex', () {
    const sxcu = '''
{
  "Version": "15.0.0",
  "Name": "files.example",
  "DestinationType": "ImageUploader, FileUploader",
  "RequestMethod": "POST",
  "RequestURL": "https://files.example/api/upload",
  "Parameters": {"expires": "never"},
  "Headers": {"Authorization": "Bearer abc"},
  "Body": "MultipartFormData",
  "Arguments": {"name": "{filename}"},
  "FileFormName": "upload",
  "URL": "{json:files[0].url}",
  "ErrorMessage": "{json:error.message}"
}''';

    test('parses a config and uploads with it', () async {
      final config = ShareXConfig.parse(sxcu);
      expect(config.name, 'files.example');
      expect(config.imagesOnly, isFalse);
      late http.Request seen;
      final provider = ShareXProvider(
        id: 's',
        config: config,
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'files': [
                {'url': 'https://files.example/u/a.png'},
              ],
            }),
            200,
          );
        }),
      );
      final file = await makeFile('a.png', [9, 9], 'image/png');
      expect(await provider.upload(file), 'https://files.example/u/a.png');
      expect(seen.url.queryParameters['expires'], 'never');
      expect(seen.headers['Authorization'], 'Bearer abc');
      expect(body(seen), contains('name="name"\r\n\r\na.png'));
      expect(body(seen), contains('name="upload"; filename="a.png"'));
    });

    test('uses the error message template', () async {
      final provider = ShareXProvider(
        id: 's',
        config: ShareXConfig.parse(sxcu),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {'message': 'quota exceeded'},
            }),
            403,
          ),
        ),
      );
      final file = await makeFile('a.png', [1], 'image/png');
      await expectLater(
        provider.upload(file),
        throwsA(predicate((e) => '$e'.contains('quota exceeded'))),
      );
    });

    test('rejects uploaders that cannot take files', () {
      expect(
        () => ShareXConfig.parse(
          '{"RequestURL": "https://x.dev", "DestinationType": "TextUploader"}',
        ),
        throwsFormatException,
      );
      expect(
        () => ShareXConfig.parse(
          '{"RequestURL": "https://x.dev", "Body": "JSON"}',
        ),
        throwsFormatException,
      );
      expect(() => ShareXConfig.parse('not json'), throwsFormatException);
    });

    test('expands templates from the response', () {
      final response = ShareXResponse(
        '{"data": {"link": "https://a.dev/1"}, "list": [{"id": 7}]}',
        {'location': 'https://a.dev/loc'},
      );
      String expand(String t) => expandShareX(
        t,
        fileName: 'f.png',
        response: response,
        regexList: [r'link": "([^"]+)"'],
      );
      expect(expand('{json:data.link}'), 'https://a.dev/1');
      expect(expand(r'$json:data.link$'), 'https://a.dev/1');
      expect(expand('{json:list[0].id}'), '7');
      expect(expand('{regex:link": "([^"]+)"|1}'), 'https://a.dev/1');
      expect(expand(r'$regex:1,1$'), 'https://a.dev/1');
      expect(expand('{header:Location}'), 'https://a.dev/loc');
      expect(expand(r'name=\{x\} {filename}'), 'name={x} f.png');
      expect(expand('{random:a|a}'), 'a');
      final xml = ShareXResponse(
        '<r><file><url>https://a.dev/x</url></file></r>',
        const {},
      );
      expect(
        expandShareX('{xml:/r/file/url}', fileName: '', response: xml),
        'https://a.dev/x',
      );
    });

    test('images only uploaders refuse other files', () {
      final config = ShareXConfig.parse(
        '{"RequestURL": "https://x.dev", "DestinationType": "ImageUploader", "FileFormName": "f"}',
      );
      final provider = ShareXProvider(id: 's', config: config);
      expect(
        provider.rejectReason(fakeFile('a.zip', 1, 'application/zip')),
        isNotNull,
      );
      expect(provider.rejectReason(fakeFile('a.png', 1, 'image/png')), isNull);
    });
  });

  group('s3', () {
    const settings = S3Settings(
      endpoint: 'https://acc.r2.cloudflarestorage.com',
      bucket: 'archive',
      accessKey: 'AK',
      secretKey: 'SK',
      publicBaseUrl: 'https://media.example.com/',
      prefix: 'discord',
    );

    test('guesses the region from the endpoint', () {
      expect(
        S3Settings.guessRegion('https://acc.r2.cloudflarestorage.com'),
        'auto',
      );
      expect(
        S3Settings.guessRegion('https://s3.us-west-004.backblazeb2.com'),
        'us-west-004',
      );
      expect(
        S3Settings.guessRegion('https://s3.eu-central-1.amazonaws.com'),
        'eu-central-1',
      );
      expect(S3Settings.guessRegion('https://minio.local:9000'), 'us-east-1');
    });

    test('puts small files in one request', () async {
      final requests = <http.Request>[];
      final provider = S3Provider(
        id: 'b',
        settings: settings,
        client: MockClient((request) async {
          requests.add(request);
          return request.method == 'HEAD'
              ? http.Response('', 404)
              : http.Response('', 200);
        }),
      );
      final file = await makeFile(
        'cat photo.png',
        List.filled(1000, 7),
        'image/png',
      );
      final url = await provider.upload(file);
      expect(
        url,
        'https://media.example.com/discord/${file.sha256.substring(0, 16)}/cat_photo.png',
      );
      final put = requests.last;
      expect(put.method, 'PUT');
      expect(
        put.url.path,
        '/archive/discord/${file.sha256.substring(0, 16)}/cat_photo.png',
      );
      expect(put.headers['x-amz-content-sha256'], file.sha256);
      expect(
        put.headers['authorization'],
        startsWith('AWS4-HMAC-SHA256 Credential=AK/'),
      );
      expect(put.headers['authorization'], contains('/auto/s3/aws4_request'));
      expect(put.bodyBytes, hasLength(1000));
    });

    test('skips files that are already in the bucket', () async {
      var puts = 0;
      final provider = S3Provider(
        id: 'b',
        settings: settings,
        client: MockClient((request) async {
          if (request.method == 'PUT') puts++;
          return http.Response('', 200, headers: {'content-length': '5'});
        }),
      );
      final file = await makeFile('a.txt', [1, 2, 3, 4, 5], 'text/plain');
      await provider.upload(file);
      expect(puts, 0);
    });

    test('uses multipart uploads for big files', () async {
      final parts = <int>[];
      String? completeBody;
      final provider = S3Provider(
        id: 'b',
        settings: settings,
        multipartThreshold: 1000,
        partSize: 400,
        client: MockClient((request) async {
          final q = request.url.queryParameters;
          if (request.method == 'HEAD') return http.Response('', 404);
          if (request.method == 'POST' && q.containsKey('uploads')) {
            return http.Response(
              '<InitiateMultipartUploadResult><UploadId>up-1</UploadId></InitiateMultipartUploadResult>',
              200,
            );
          }
          if (request.method == 'PUT') {
            expect(q['uploadId'], 'up-1');
            parts.add(int.parse(q['partNumber']!));
            return http.Response(
              '',
              200,
              headers: {'etag': '"etag-${q['partNumber']}"'},
            );
          }
          if (request.method == 'POST' && q['uploadId'] == 'up-1') {
            completeBody = request.body;
            return http.Response('<CompleteMultipartUploadResult/>', 200);
          }
          return http.Response('unexpected', 500);
        }),
      );
      final file = await makeFile(
        'video.mp4',
        List.filled(1100, 1),
        'video/mp4',
      );
      await provider.upload(file);
      expect(parts..sort(), [1, 2, 3]);
      expect(
        completeBody,
        contains('<PartNumber>3</PartNumber><ETag>"etag-3"</ETag>'),
      );
    });

    test('aborts a multipart upload that fails', () async {
      var aborted = false;
      final provider = S3Provider(
        id: 'b',
        settings: settings,
        multipartThreshold: 10,
        partSize: 10,
        client: MockClient((request) async {
          final q = request.url.queryParameters;
          if (request.method == 'HEAD') return http.Response('', 404);
          if (q.containsKey('uploads')) {
            return http.Response('<r><UploadId>u</UploadId></r>', 200);
          }
          if (request.method == 'DELETE') {
            aborted = true;
            return http.Response('', 204);
          }
          return http.Response(
            '<Error><Code>AccessDenied</Code><Message>nope</Message></Error>',
            403,
          );
        }),
      );
      final file = await makeFile(
        'big.bin',
        List.filled(25, 1),
        'application/octet-stream',
      );
      await expectLater(
        provider.upload(file),
        throwsA(predicate((e) => '$e'.contains('AccessDenied'))),
      );
      expect(aborted, isTrue);
    });
  });
}
