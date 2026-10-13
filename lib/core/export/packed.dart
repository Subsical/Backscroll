import 'dart:convert';
import 'dart:io';

String packData(String text) => base64.encode(zlib.encode(utf8.encode(text)));

String unpackData(String packed) =>
    utf8.decode(zlib.decode(base64.decode(packed)));
