import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('seu-store-');
    file = File('${dir.path}/KeJian/schedule.json');
  });
  tearDown(() async => dir.delete(recursive: true));
  test('保存重启、多天课程、隔离编辑草稿、删除整课', () async {
    final store = ScheduleStore(file);
    await store.load();
    final c = Course(
      name: '网络',
      meetings: WeeklyMeeting().onWeekdays({1, 4}),
      extras: [ExtraMeeting(allDay: true)],
    );
    await store.saveCourse(c);
    c.name = '未保存的草稿';
    expect(store.data.courses.single.name, '网络');
    final reopen = ScheduleStore(file);
    await reopen.load();
    expect(reopen.data.toJson(), store.data.toJson());
    expect(reopen.data.courses.single.meetings.length, 2);
    await reopen.deleteCourse(store.data.courses.single.id);
    expect(reopen.data.courses, isEmpty);
  });
  test('损坏文件不被普通保存覆盖，可导出原文件并保留副本后恢复', () async {
    await file.parent.create(recursive: true);
    await file.writeAsString('broken original');
    final store = ScheduleStore(file);
    await store.load();
    expect(store.canWrite, isFalse);
    expect(store.loadError, isNotNull);
    await expectLater(store.replace(ScheduleData()), throwsFormatException);
    expect(await file.readAsString(), 'broken original');
    expect(utf8.decode(await store.exportBytes()), 'broken original');
    await store.replace(ScheduleData(), recovering: true);
    expect(store.canWrite, isTrue);
    final backup = await file.parent
        .list()
        .where((f) => f.path.contains('unreadable-'))
        .first;
    expect(await File(backup.path).readAsString(), 'broken original');
  });
  test('非法或超大写入失败，旧课表与原文件保留', () async {
    final store = ScheduleStore(file);
    await store.load();
    await store.replace(ScheduleData());
    final before = await file.readAsBytes();
    final invalid = store.data.copy()..semester.weekCount = 0;
    await expectLater(store.replace(invalid), throwsFormatException);
    expect(await file.readAsBytes(), before);
    expect(store.data.semester.weekCount, 20);
    final huge = ScheduleData(
      courses: [
        for (var i = 0; i < 5; i++)
          Course(
            name: '大备注$i',
            extras: [
              for (var j = 0; j < 100; j++)
                ExtraMeeting(notes: List.filled(2000, '字').join()),
            ],
          ),
      ],
    );
    await expectLater(store.replace(huge), throwsFormatException);
    expect(await file.readAsBytes(), before);
    expect(store.data.courses, isEmpty);
  });
}
