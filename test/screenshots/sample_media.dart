import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

Uint8List sampleImage(String path) =>
    File('test/screenshots/images/$path').readAsBytesSync();

Uint8List toneWav({double seconds = 2.4, int rate = 22050}) {
  final samples = (seconds * rate).round();
  final data = ByteData(44 + samples * 2);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      data.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVEfmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  const notes = [392.0, 440.0, 523.25, 587.33];
  for (var i = 0; i < samples; i++) {
    final t = i / rate;
    final note = notes[(t * 4).floor() % notes.length];
    final envelope = 1 - ((t * 4) % 1);
    final value = sin(2 * pi * note * t) * envelope * 0.3;
    data.setInt16(44 + i * 2, (value * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}
