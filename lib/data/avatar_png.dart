import 'dart:io';
import 'dart:typed_data';

/// Server avatar format: 128×128, straight RGBA, 8 bits, no interlacing.
/// Encode explicitly because native PNG encoders can choose other PNG formats.
Uint8List encodeAvatarPng(Uint8List rgba) {
  return encodeRgbaPng(rgba, 128, 128);
}

Uint8List encodeRgbaPng(Uint8List rgba, int width, int height) {
  final stride = width * 4;
  if (width < 1 ||
      height < 1 ||
      width > 768 ||
      height > 768 ||
      rgba.length != height * stride) {
    throw const FormatException('头像像素数据无效。');
  }
  final pixels = Uint8List(height * (stride + 1));
  for (var row = 0; row < height; row++) {
    // Each row starts with filter type 0 (None).
    pixels.setRange(
      row * (stride + 1) + 1,
      (row + 1) * (stride + 1),
      rgba,
      row * stride,
    );
  }
  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  final output = BytesBuilder(copy: false)
    ..add([137, 80, 78, 71, 13, 10, 26, 10]);
  void chunk(String type, List<int> payload) {
    final bytes = Uint8List(12 + payload.length);
    final view = ByteData.sublistView(bytes);
    view.setUint32(0, payload.length);
    bytes.setRange(4, 8, type.codeUnits);
    bytes.setRange(8, 8 + payload.length, payload);
    var crc = 0xffffffff;
    for (var i = 4; i < 8 + payload.length; i++) {
      crc ^= bytes[i];
      for (var bit = 0; bit < 8; bit++) {
        crc = (crc >>> 1) ^ ((crc & 1) == 1 ? 0xedb88320 : 0);
      }
    }
    view.setUint32(8 + payload.length, crc ^ 0xffffffff);
    output.add(bytes);
  }

  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(pixels));
  chunk('IEND', const []);
  return output.takeBytes();
}
