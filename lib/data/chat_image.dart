import 'dart:typed_data';
import 'dart:ui' as ui;

import 'avatar_png.dart';

const maxChatImageBytes = 3 * 1024 * 1024;

/// Photos are scaled without cropping; GIF bytes are kept to preserve animation.
Future<Uint8List> prepareChatImage(Uint8List source) async {
  if (source.length > 15 * 1024 * 1024) {
    throw const FormatException('请选择小于 15 MB 的图片。');
  }
  final gif =
      source.length >= 6 &&
      (String.fromCharCodes(source.sublist(0, 6)) == 'GIF89a' ||
          String.fromCharCodes(source.sublist(0, 6)) == 'GIF87a');
  if (gif) {
    if (source.length > maxChatImageBytes || source.length < 13) {
      throw const FormatException('GIF 表情包不能超过 3 MB。');
    }
    final header = ByteData.sublistView(source);
    final width = header.getUint16(6, Endian.little);
    final height = header.getUint16(8, Endian.little);
    if (width < 1 || height < 1 || width > 512 || height > 512) {
      throw const FormatException('GIF 宽高不能超过 512 像素。');
    }
    final codec = await ui.instantiateImageCodec(source);
    try {
      if (codec.frameCount > 200 ||
          codec.frameCount * width * height > 32 * 1024 * 1024) {
        throw const FormatException('GIF 动画过长，请选择较短的表情包。');
      }
      final frame = await codec.getNextFrame();
      frame.image.dispose();
      return source;
    } finally {
      codec.dispose();
    }
  }
  final codec = await ui.instantiateImageCodecWithSize(
    await ui.ImmutableBuffer.fromUint8List(source),
    getTargetSize: (width, height) => width >= height
        ? ui.TargetImageSize(width: width > 768 ? 768 : width)
        : ui.TargetImageSize(height: height > 768 ? 768 : height),
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final rgba = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (rgba == null) throw const FormatException('无法读取图片。');
      return encodeRgbaPng(
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
        image.width,
        image.height,
      );
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
