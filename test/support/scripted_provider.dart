import 'package:backscroll/core/media/providers/provider.dart';

class ScriptedProvider extends UploadProvider {
  ScriptedProvider(
    this.id, {
    this.concurrency = 2,
    this.script,
    this.imagesOnly = false,
  });

  @override
  final String id;
  @override
  final int concurrency;
  final bool imagesOnly;
  final Future<String> Function(UploadFile file, int attempt)? script;
  int calls = 0;
  int running = 0;
  int peak = 0;

  @override
  String get name => id;
  @override
  bool get isPublic => true;
  @override
  int? get maxBytes => null;

  @override
  String? rejectReason(UploadFile file) =>
      imagesOnly && !file.isImage ? 'images only' : null;

  @override
  Future<String> upload(UploadFile file, {ProgressCallback? onProgress}) async {
    calls++;
    running++;
    if (running > peak) peak = running;
    try {
      onProgress?.call(file.size);
      return await (script?.call(file, calls) ??
          Future.value('https://$id.example/${file.sha256}'));
    } finally {
      running--;
    }
  }
}
