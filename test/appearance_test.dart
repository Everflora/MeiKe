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

  test('旧版深色设置使用奶家日常默认主题，主题和显示模式独立保存', () async {
    final dir = await Directory.systemTemp.createTemp('meike-migrate-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/appearance.txt');
    await file.writeAsString('dark');
    final settings = AppearanceController(file);
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.mode, ThemeMode.dark);
    expect(settings.theme, MeikeTheme.naiFamily);
    await settings.setTheme(MeikeTheme.ginkgo);
    expect(settings.mode, ThemeMode.dark);
    final reopened = AppearanceController(file);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.theme, MeikeTheme.ginkgo);
    expect(reopened.mode, ThemeMode.dark);
    await reopened.setMode(ThemeMode.system);
    await settings.load();
    expect(settings.theme, MeikeTheme.ginkgo);
    expect(settings.mode, ThemeMode.system);
    await file.writeAsString('{"theme":"missing","mode":"light"}');
    await settings.load();
    expect(settings.theme, MeikeTheme.naiFamily);
    expect(settings.mode, ThemeMode.light);
    await file.writeAsString('{broken');
    await settings.load();
    expect(settings.theme, MeikeTheme.naiFamily);
    expect(settings.mode, ThemeMode.system);
  });

  test('连续选择主题和显示模式不丢失任一偏好', () async {
    final dir = await Directory.systemTemp.createTemp('meike-rapid-');
    addTearDown(() => dir.delete(recursive: true));
    final settings = AppearanceController(File('${dir.path}/appearance.txt'));
    addTearDown(settings.dispose);
    await Future.wait([
      settings.setTheme(MeikeTheme.ginkgo),
      settings.setMode(ThemeMode.dark),
    ]);
    await settings.load();
    expect(settings.theme, MeikeTheme.ginkgo);
    expect(settings.mode, ThemeMode.dark);
  });

  for (final design in MeikeTheme.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${design.label} $brightness 下20种课程配色满足4.5:1对比度', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: meikeTheme(brightness, design),
            home: Builder(
              builder: (context) {
                final p = context.meike;
                expect(p.design, design);
                for (final pair in [
                  (p.ink, p.paper),
                  (p.muted, p.surface),
                  (p.goldInk, p.goldSoft),
                  (p.onHero, p.hero),
                  (p.onHero, p.heroEnd),
                  (p.heroAccent, p.hero),
                  (p.heroAccent, p.heroEnd),
                  (Theme.of(context).colorScheme.onPrimary, p.green),
                ]) {
                  expect(contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5));
                }
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
}
