import 'dart:io';
import 'dart:math';

final _random = Random();

Future<void> writeAtomic(File file, String content) async {
  final temp = File('${file.path}.${_random.nextInt(1 << 32)}.tmp');
  await temp.writeAsString(content, flush: true);
  await temp.rename(file.path);
}

Future<void> moveFile(String from, String to) async {
  final source = File(from);
  try {
    await source.rename(to);
  } on FileSystemException {
    await source.copy(to);
    await source.delete();
  }
}
