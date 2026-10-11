import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/ui/appearance.dart';
import 'package:seu_timetable/ui/theme.dart';
import 'package:seu_timetable/domain/schedule.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance(), y = b.computeLuminance();
  return x > y ? (x + .05) / (y + .05) : (y + .05) / (x + .05);
}

void main() {
  test('主题设置单独保存，重启恢复；无效值回到系统主题', () async {
    final dir = await Directory.systemTemp.createTemp('meike-appearance-');
    final file = File('${dir.path}/appearance.txt');
    final settings = AppearanceController(file);
    await settings.load();
    expect(settings.mode, ThemeMode.system);
    await settings.setMode(ThemeMode.dark);
    final reopened = AppearanceController(file);
    await reopened.load();
    expect(reopened.mode, ThemeMode.dark);
    await file.writeAsString('unknown');
    await reopened.load();
    expect(reopened.mode, ThemeMode.system);
    settings.dispose();
    reopened.dispose();
    await dir.delete(recursive: true);
  });

  for (final brightness in Brightness.values) {
    testWidgets('$brightness 下20种课程配色均满足小字4.5:1对比度', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: meikeTheme(brightness),
          home: Builder(
            builder: (context) {
              for (final color in CourseColor.values) {
                expect(
                  contrast(color.foreground(context), color.surface(context)),
                  greaterThanOrEqualTo(4.5),
                  reason: color.name,
                );
              }
              return const SizedBox();
            },
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }
}
