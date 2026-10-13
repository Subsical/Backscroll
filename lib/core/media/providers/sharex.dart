import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import 'package:xml/xpath.dart';

import 'provider.dart';

class ShareXConfig {
  ShareXConfig({
    required this.name,
    required this.requestUrl,
    required this.method,
    required this.body,
    required this.fileFormName,
    required this.imagesOnly,
    this.parameters = const {},
    this.headers = const {},
    this.arguments = const {},
    this.url = '',
    this.errorMessage = '',
    this.regexList = const [],
    this.locationHeader = false,
  });

  static ShareXConfig parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('This is not a valid .sxcu file');
    }
    if (decoded is! Map) {
      throw const FormatException('This is not a valid .sxcu file');
    }
    Map<String, String> strings(Object? value) => value is Map
        ? {for (final e in value.entries) '${e.key}': '${e.value ?? ''}'}
        : const {};

    final requestUrl = (decoded['RequestURL'] as String? ?? '').trim();
    final uri = Uri.tryParse(requestUrl);
    if (uri == null || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      throw const FormatException('The uploader has no usable RequestURL');
    }
    final destinations = '${decoded['DestinationType'] ?? 'FileUploader'}'
        .split(',')
        .map((d) => d.trim())
        .toSet();
    final takesFiles = destinations.contains('FileUploader');
    if (!takesFiles && !destinations.contains('ImageUploader')) {
      throw const FormatException(
        'The uploader is not an image or file uploader',
      );
    }
    final fileFormName = decoded['FileFormName'] as String?;
    var body = decoded['Body'] as String?;
    if (body == null || body.isEmpty) {
      body = fileFormName == null ? 'Binary' : 'MultipartFormData';
    }
    if (body != 'MultipartFormData' && body != 'Binary') {
      throw FormatException(
        'Uploading files with a "$body" body is not supported',
      );
    }
    final method =
        '${decoded['RequestMethod'] ?? decoded['RequestType'] ?? 'POST'}'
            .toUpperCase();
    return ShareXConfig(
      name: (decoded['Name'] as String?)?.trim().isNotEmpty == true
          ? (decoded['Name'] as String).trim()
          : uri.host,
      requestUrl: requestUrl,
      method: method,
      body: body,
      fileFormName: fileFormName ?? 'file',
      imagesOnly: !takesFiles,
      parameters: strings(decoded['Parameters']),
      headers: strings(decoded['Headers']),
      arguments: strings(decoded['Arguments']),
      url: '${decoded['URL'] ?? ''}',
      errorMessage: '${decoded['ErrorMessage'] ?? ''}',
      regexList: decoded['RegexList'] is List
          ? (decoded['RegexList'] as List).map((e) => '$e').toList()
          : const [],
      locationHeader: decoded['ResponseType'] == 'LocationHeader',
    );
  }

  final String name;
  final String requestUrl;
  final String method;
  final String body;
  final String fileFormName;
  final bool imagesOnly;
  final Map<String, String> parameters;
  final Map<String, String> headers;
  final Map<String, String> arguments;
  final String url;
  final String errorMessage;
  final List<String> regexList;
  final bool locationHeader;

  String get host => Uri.parse(requestUrl).host;
}

class ShareXResponse {
  ShareXResponse(this.body, this.headers);

  final String body;
  final Map<String, String> headers;
  Object? _json;
  bool _jsonParsed = false;
  XmlDocument? _xml;

  Object? get json {
    if (!_jsonParsed) {
      _jsonParsed = true;
      try {
        _json = jsonDecode(body);
      } on FormatException {
        _json = null;
      }
    }
    return _json;
  }

  XmlDocument? get xml {
    if (_xml == null) {
      try {
        _xml = XmlDocument.parse(body);
      } on XmlException {
        return null;
      }
    }
    return _xml;
  }
}

String _stringify(Object? value) => switch (value) {
  null => '',
  String s => s,
  num _ || bool _ => '$value',
  _ => jsonEncode(value),
};

Object? jsonPath(Object? root, String path) {
  var p = path.trim();
  if (p.startsWith(r'$')) p = p.substring(1);
  Object? current = root;
  for (final token in RegExp(r'\[(\d+)\]|[^.\[\]]+').allMatches(p)) {
    final index = token[1];
    if (index != null) {
      if (current is! List) return null;
      final i = int.parse(index);
      current = i < current.length ? current[i] : null;
    } else {
      if (current is! Map) return null;
      current = current[token[0]];
    }
  }
  return current;
}

final _random = Random();
const _legacyNames = {
  'json',
  'xml',
  'regex',
  'response',
  'responseurl',
  'header',
  'filename',
  'random',
  'input',
};

String expandShareX(
  String template, {
  required String fileName,
  ShareXResponse? response,
  List<String> regexList = const [],
}) {
  final out = StringBuffer();
  var i = 0;
  while (i < template.length) {
    final c = template[i];
    if (c == r'\' && i + 1 < template.length) {
      out.write(template[i + 1]);
      i += 2;
      continue;
    }
    if (c == '{') {
      final end = _closing(template, i);
      if (end > i) {
        final inner = expandShareX(
          template.substring(i + 1, end),
          fileName: fileName,
          response: response,
          regexList: regexList,
        );
        out.write(
          _evaluate(inner, fileName, response, regexList, legacy: false),
        );
        i = end + 1;
        continue;
      }
    }
    if (c == r'$') {
      final end = template.indexOf(r'$', i + 1);
      if (end > i) {
        final inner = template.substring(i + 1, end);
        final name = inner.split(':').first.toLowerCase();
        if (_legacyNames.contains(name)) {
          out.write(
            _evaluate(inner, fileName, response, regexList, legacy: true),
          );
          i = end + 1;
          continue;
        }
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}

int _closing(String text, int open) {
  var depth = 0;
  for (var i = open; i < text.length; i++) {
    final c = text[i];
    if (c == r'\') {
      i++;
    } else if (c == '{') {
      depth++;
    } else if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

String _evaluate(
  String syntax,
  String fileName,
  ShareXResponse? response,
  List<String> regexList, {
  required bool legacy,
}) {
  final colon = syntax.indexOf(':');
  final name = (colon < 0 ? syntax : syntax.substring(0, colon)).toLowerCase();
  final argument = colon < 0 ? '' : syntax.substring(colon + 1);
  final args = argument.split('|');
  switch (name) {
    case 'filename':
      return fileName;
    case 'random':
      return args[_random.nextInt(args.length)];
    case 'select':
      return args.first;
    case 'prompt':
      return args.length > 1 ? args[1] : '';
    case 'base64':
      return base64.encode(utf8.encode(argument));
    case 'input' || 'inputbox' || 'outputbox':
      return '';
    case 'response':
      return response?.body ?? '';
    case 'responseurl':
      return '';
    case 'header':
      return response?.headers[argument.toLowerCase()] ?? '';
    case 'json':
      return _stringify(jsonPath(response?.json, argument));
    case 'xml':
      final doc = response?.xml;
      if (doc == null) return '';
      try {
        return doc.xpath(argument).firstOrNull?.innerText ?? '';
      } on Exception {
        return '';
      }
    case 'regex':
      final body = response?.body ?? '';
      String pattern;
      String group;
      if (legacy) {
        final parts = argument.split(',');
        final index = int.tryParse(parts.first) ?? 1;
        if (index < 1 || index > regexList.length) return '';
        pattern = regexList[index - 1];
        group = parts.length > 1 ? parts[1] : '0';
      } else {
        final split = argument.lastIndexOf('|');
        pattern = split < 0 ? argument : argument.substring(0, split);
        group = split < 0 ? '0' : argument.substring(split + 1);
      }
      final RegExpMatch? match;
      try {
        match = RegExp(pattern).firstMatch(body);
      } on FormatException {
        return '';
      }
      if (match == null) return '';
      final index = int.tryParse(group);
      if (index != null) {
        return index <= match.groupCount ? match[index] ?? '' : '';
      }
      return match.groupNames.contains(group)
          ? match.namedGroup(group) ?? ''
          : '';
  }
  return legacy ? '\$$syntax\$' : '{$syntax}';
}

class ShareXProvider extends UploadProvider {
  ShareXProvider({
    required this.id,
    required this.config,
    this.concurrency = 2,
    this.limit,
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  final String id;
  final ShareXConfig config;
  @override
  final int concurrency;
  final int? limit;
  final http.Client _client;

  @override
  String get name => config.name;

  @override
  bool get isPublic => true;

  @override
  int? get maxBytes => limit;

  @override
  String? rejectReason(UploadFile file) {
    if (config.imagesOnly && !file.isImage) {
      return '${config.name} only takes images';
    }
    final max = limit;
    if (max != null && file.size > max) {
      return 'larger than the limit for ${config.name}';
    }
    return null;
  }

  @override
  Future<String> upload(UploadFile file, {ProgressCallback? onProgress}) async {
    String expand(String value) => expandShareX(value, fileName: file.name);
    var uri = Uri.parse(expand(config.requestUrl));
    if (config.parameters.isNotEmpty) {
      uri = uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          for (final e in config.parameters.entries) e.key: expand(e.value),
        },
      );
    }
    final headers = {
      for (final e in config.headers.entries) e.key: expand(e.value),
    };
    final http.Response response;
    if (config.body == 'Binary') {
      final request = http.StreamedRequest(config.method, uri)
        ..contentLength = file.size
        ..headers.addAll(headers);
      request.headers.putIfAbsent('content-type', () => file.contentType);
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
      response = await sending;
    } else {
      final request = http.MultipartRequest(config.method, uri)
        ..headers.addAll(headers)
        ..fields.addAll({
          for (final e in config.arguments.entries) e.key: expand(e.value),
        })
        ..files.add(
          multipartFile(config.fileFormName, file, onProgress: onProgress),
        );
      response = await sendWithTimeout(_client, request);
    }

    final context = ShareXResponse(response.body, response.headers);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final url =
          (config.locationHeader
                  ? response.headers['location'] ?? ''
                  : config.url.trim().isEmpty
                  ? response.body
                  : expandShareX(
                      config.url,
                      fileName: file.name,
                      response: context,
                      regexList: config.regexList,
                    ))
              .trim();
      if (url.startsWith('https://') || url.startsWith('http://')) return url;
      throw UploadException('${config.name} did not return a link');
    }
    final detail = config.errorMessage.trim().isEmpty
        ? ''
        : expandShareX(
            config.errorMessage,
            fileName: file.name,
            response: context,
            regexList: config.regexList,
          ).trim();
    throw UploadException(
      '${config.name}: ${detail.isEmpty ? 'HTTP ${response.statusCode}' : detail}',
      retryable: isRetryableStatus(response.statusCode),
      retryAfter: retryAfterHeader(response),
    );
  }

  @override
  void close() => _client.close();
}
