import 'dart:convert';
import 'dart:typed_data';

const maxChatFileBytes = 10 * 1024 * 1024;

String chatFileName(String name) {
  final value = name.trim();
  if (value.isEmpty ||
      value == '.' ||
      value == '..' ||
      utf8.encode(value).length > 240 ||
      RegExp(r'[/\\\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(value)) {
    throw const FormatException('文件名无效，请重命名后重试。');
  }
  return value;
}

Future<Uint8List> readChatFile(Stream<List<int>> stream) async {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in stream) {
    if (buffer.length + chunk.length > maxChatFileBytes) {
      throw const FormatException('文件不能超过 10 MB。');
    }
    buffer.add(chunk);
  }
  if (buffer.isEmpty) throw const FormatException('请选择非空文件。');
  return buffer.takeBytes();
}

String chatFileSize(int size) => size >= 1024 * 1024
    ? '${(size / (1024 * 1024)).toStringAsFixed(1)} MB'
    : size >= 1024
    ? '${(size / 1024).toStringAsFixed(1)} KB'
    : '$size B';
