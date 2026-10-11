import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/avatar_png.dart';

void main() {
  test('RGBA 编码保留透明度与所有像素，符合服务器尺寸和格式限制', () {
    final random = Random(42);
    final rgba = Uint8List.fromList(
      List.generate(128 * 128 * 4, (_) => random.nextInt(256)),
    );
    final png = encodeAvatarPng(rgba);
    expect(png.length, lessThanOrEqualTo(98304));
    final bytes = ByteData.sublistView(png);
    expect(bytes.getUint32(16), 128);
    expect(bytes.getUint32(20), 128);
    expect(png.sublist(24, 29), [8, 6, 0, 0, 0]);
    final compressedLength = bytes.getUint32(33);
    final pixels = ZLibDecoder().convert(
      png.sublist(41, 41 + compressedLength),
    );
    expect(pixels.length, 128 * 513);
    for (var row = 0; row < 128; row++) {
      expect(pixels[row * 513], 0);
      expect(
        pixels.sublist(row * 513 + 1, (row + 1) * 513),
        rgba.sublist(row * 512, (row + 1) * 512),
      );
    }
  });

  test('拒绝不完整的 RGBA 像素', () {
    expect(() => encodeAvatarPng(Uint8List(12)), throwsFormatException);
  });
}
