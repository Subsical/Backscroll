import '../../discord/models.dart';
import '../context.dart';
import '../options.dart';
import '../part_sink.dart';

class PartInfo {
  const PartInfo({
    required this.index,
    required this.fileName,
    this.previousFileName,
  });

  final int index;
  final String fileName;
  final String? previousFileName;
}

abstract class ExportLinks {
  String? messageHref(String messageId);
  String? threadHref(Channel thread);
}

class ExportAssets {
  const ExportAssets({this.fontRegular = '', this.fontItalic = ''});

  final String fontRegular;
  final String fontItalic;
}

abstract class MessageWriter {
  MessageWriter(this.ctx, this.options);

  final ExportContext ctx;
  final ExportOptions options;
  late PartSink sink;
  String? committedId;
  int committedCount = 0;

  void begin(PartInfo part);

  void add(Message message);

  void end(PartInfo part, {String? nextFileName});

  void startPart(PartSink sink) {
    this.sink = sink;
    committedCount = 0;
  }

  Map<String, Object?> saveState() => const {};

  void restoreState(Map<String, Object?> state) {}

  void commit(Message message) {
    committedId = message.id;
    committedCount++;
  }
}
