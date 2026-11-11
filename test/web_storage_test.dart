@TestOn('browser')
library;

import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/platform/io.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/appearance.dart';

void main() {
  testWidgets(
    'Fresh web profile renders timetable and campus without native plugins',
    (tester) async {
      final base = '/test-${newId()}';
      final store = ScheduleStore(File('$base/schedule.json'));
      addTearDown(() async {
        store.dispose();
        await File('$base/schedule.json').delete();
        await File('$base/appearance.txt').delete();
      });
      await tester.runAsync(() async {
        await store.load();
        await tester.pumpWidget(SeuTimetableApp(store: store));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('课表'), findsWidgets);
      await tester.tap(find.text('校园'));
      await tester.pumpAndSettle();
      expect(find.text('打开学校官网'), findsOneWidget);
      expect(find.text('登录并同步劳动教育'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'IndexedDB saves survive new store instances and preserve course rules',
    () async {
      final path = '/test-${newId()}/schedule.json';
      final first = ScheduleStore(File(path));
      final second = ScheduleStore(File(path));
      addTearDown(() async {
        first.dispose();
        second.dispose();
        await File(path).delete();
      });
      final course = Course(
        name: '浏览器存储测试',
        teacher: '演示教师',
        location: '教三-304',
        meetings: [
          WeeklyMeeting(weekday: 1, startPeriod: 3, endPeriod: 5),
          WeeklyMeeting(weekday: 4, startPeriod: 6, endPeriod: 7),
        ],
        extras: [ExtraMeeting(week: 4, weekday: 7, allDay: true)],
      );
      await first.saveCourse(course);
      await second.load();
      expect(second.canWrite, isTrue);
      expect(
        second.data.courses.single.toJson(),
        first.data.courses.single.toJson(),
      );
      expect(await second.exportBytes(), await first.exportBytes());
    },
  );
  test(
    'IndexedDB atomic rename keeps destination if source does not exist',
    () async {
      final path = '/test-${newId()}/record';
      final saved = File(path);
      final temporary = File('$path.tmp');
      addTearDown(() async {
        await saved.delete();
        await temporary.delete();
      });
      await saved.writeAsBytes([1, 2, 3]);
      await expectLater(
        temporary.rename(path),
        throwsA(isA<FileSystemException>()),
      );
      expect(await saved.readAsBytes(), [1, 2, 3]);
      await temporary.writeAsBytes([4, 5]);
      await temporary.rename(path);
      expect(await saved.readAsBytes(), [4, 5]);
      expect(await temporary.exists(), isFalse);
    },
  );
  test(
    'Invalid browser data is preserved and appearance persists independently',
    () async {
      final base = '/test-${newId()}';
      final file = File('$base/schedule.json');
      final prefs = File('$base/appearance.txt');
      final store = ScheduleStore(file);
      final first = AppearanceController(prefs),
          second = AppearanceController(prefs);
      addTearDown(() async {
        store.dispose();
        first.dispose();
        second.dispose();
        await file.delete();
        await prefs.delete();
      });
      await file.writeAsString('invalid');
      await store.load();
      expect(store.canWrite, isFalse);
      expect(
        await store.exportBytes(),
        Uint8List.fromList('invalid'.codeUnits),
      );
      await first.setTheme(MeikeTheme.naiFamily);
      await second.load();
      expect(second.theme, MeikeTheme.naiFamily);
      expect(await file.readAsString(), 'invalid');
    },
  );
}
