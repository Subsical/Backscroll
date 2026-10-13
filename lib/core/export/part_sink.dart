import 'dart:convert';
import 'dart:io';

class PartSink {
  PartSink._(this.path, this._file, this.offset);

  factory PartSink.open(String path, {int? resumeAt}) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final raf = file.openSync(mode: FileMode.append);
    final start = resumeAt ?? 0;
    if (raf.lengthSync() < start) {
      raf.closeSync();
      throw StateError('Partial file is shorter than its checkpoint');
    }
    raf.truncateSync(start);
    raf.setPositionSync(start);
    return PartSink._(path, raf, start);
  }

  final String path;
  final RandomAccessFile _file;
  final _buffer = StringBuffer();
  int offset;
  bool _closed = false;

  void write(String text) {
    _buffer.write(text);
    if (_buffer.length > 1 << 16) flush();
  }

  void writeBytes(List<int> bytes) {
    flush();
    _file.writeFromSync(bytes);
    offset += bytes.length;
  }

  void flush() {
    if (_buffer.isEmpty) return;
    final bytes = utf8.encode(_buffer.toString());
    _buffer.clear();
    _file.writeFromSync(bytes);
    offset += bytes.length;
  }

  void sync() {
    flush();
    _file.flushSync();
  }

  void close() {
    if (_closed) return;
    sync();
    _closed = true;
    _file.closeSync();
  }

  void discard() {
    if (_closed) return;
    _buffer.clear();
    _closed = true;
    _file.closeSync();
  }
}
