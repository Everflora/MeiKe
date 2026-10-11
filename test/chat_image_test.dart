import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/avatar_png.dart';
import 'package:seu_timetable/data/chat_image.dart';

void main() {
  testWidgets('图片保留比例和透明度，输出可解码 PNG', (tester) async {
    await tester.runAsync(() async {
      final pixels = Uint8List(200 * 100 * 4);
      for (var i = 0; i < pixels.length; i += 4) {
        pixels[i] = 240;
        pixels[i + 3] = 128;
      }
      final png = await prepareChatImage(encodeRgbaPng(pixels, 200, 100));
      final codec = await ui.instantiateImageCodec(png);
      final image = (await codec.getNextFrame()).image;
      expect([image.width, image.height], [200, 100]);
      final data = await image.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      expect(data!.getUint8(3), 128);
      expect(data.getUint8(0), closeTo(240, 2));
      image.dispose();
      codec.dispose();
    });
  });

  testWidgets('GIF 保留动画原文件，大尺寸 GIF 明确拒绝', (tester) async {
    await tester.runAsync(() async {
      final gif = base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAkQBADs=',
      );
      expect(await prepareChatImage(gif), gif);
      final wide = Uint8List.fromList(gif);
      ByteData.sublistView(wide).setUint16(6, 513, Endian.little);
      await expectLater(prepareChatImage(wide), throwsFormatException);
    });
  });
}
