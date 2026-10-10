import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/app.dart';
import 'package:seu_timetable/data/schedule_store.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/domain/school_import.dart';
import 'package:seu_timetable/ui/school_import_page.dart';

Json row({String weeks = '1-16周', int day = 1, String location = '教三 101'}) => {
  'KCM': '导入测试课程',
  'KCH': 'TEST101',
  'JXBID': 'DEMO',
  'SKJS': '示例教师',
  'JASMC': location,
  'SKXQ': '$day',
  'KSJC': '3',
  'JSJC': 4,
  'ZCMC': weeks,
};
Json payload(List<Json> rows) => {
  'termCode': '2026-2027-1',
  'termName': '示例学期',
  'rows': rows,
};

void main() {
  test('不连续周、单双周和中文标点精确展开，未知周次拒绝导入', () {
    expect(SchoolImport.parseWeeks('1-5周（单），8-12周(双)，15周'), [
      1,
      3,
      5,
      8,
      10,
      12,
      15,
    ]);
    expect(SchoolImport.parseWeeks('第1～3周、5周；7-9周'), [1, 2, 3, 5, 7, 8, 9]);
    for (final value in [
      '',
      '0-5周',
      '1-41周',
      '5-2周',
      '待定',
      '2周(单)',
      '1-3周abc',
    ]) {
      expect(
        () => SchoolImport.parseWeeks(value),
        throwsFormatException,
        reason: value,
      );
    }
  });
  test('同课多个时间地点保留，重叠周不重复，标识不依赖响应顺序', () {
    final rows = [
      row(weeks: '1-5周'),
      row(weeks: '3-8周'),
      row(weeks: '2,4,8周', day: 4, location: '实验室'),
    ];
    final imported = SchoolImport.parse(payload(rows));
    expect(imported.courses, hasLength(1));
    final data = imported.candidate(
      ScheduleData(),
      SchoolClock.instant(2026, 8, 31),
    );
    for (var week = 1; week <= 20; week++) {
      expect(data.occurrences(week, weekday: 1).length, week <= 8 ? 1 : 0);
      final thursday = data.occurrences(week, weekday: 4);
      expect(thursday.length, [2, 4, 8].contains(week) ? 1 : 0);
      if (thursday.isNotEmpty) expect(thursday.single.location, '实验室');
    }
    final reversed = SchoolImport.parse(payload(rows.reversed.toList()));
    expect(reversed.courses.single.id, imported.courses.single.id);
    expect(
      reversed.courses.single.meetings.map((m) => m.id).toSet(),
      imported.courses.single.meetings.map((m) => m.id).toSet(),
    );
  });
  test('重复导入更新安排，保留手动课、备注、颜色和额外安排，不修改输入', () {
    final imported = SchoolImport.parse(payload([row()]));
    final original = ScheduleData(
      courses: [
        Course(name: '手动课程', meetings: [WeeklyMeeting()]),
      ],
    );
    final once = imported.candidate(original, SchoolClock.instant(2026, 8, 31));
    final school = once.courses.last
      ..notes = '我的备注'
      ..color = CourseColor.rose;
    school.extras.add(ExtraMeeting(week: 3, weekday: 2, title: '我的实验'));
    final changed = SchoolImport.parse(
      payload([row(weeks: '1-8周', location: '新教室')]),
    );
    final twice = changed.candidate(once, SchoolClock.instant(2026, 8, 31));
    expect(twice.courses, hasLength(2));
    expect(twice.courses.last.notes, '我的备注');
    expect(twice.courses.last.color, CourseColor.rose);
    expect(twice.courses.last.extras.single.title, '我的实验');
    expect(
      twice.occurrences(9, weekday: 1).where((e) => e.courseId == school.id),
      isEmpty,
    );
    expect(original.courses, hasLength(1));
    expect(once.courses.last.meetings.single.location, '教三 101');
    expect(
      changed
          .candidate(once, SchoolClock.instant(2026, 8, 31), replace: true)
          .courses,
      hasLength(1),
    );
  });
  test('教师差异独立，空结果、非法星期和缺少作息的节次拒绝导入', () {
    final other = row()..['SKJS'] = '另一位示例教师';
    expect(SchoolImport.parse(payload([row(), other])).courses, hasLength(2));
    expect(() => SchoolImport.parse(payload([])), throwsFormatException);
    expect(
      () => SchoolImport.parse(payload([row()..['SKXQ'] = 0])),
      throwsFormatException,
    );
    final high = SchoolImport.parse(payload([row()..['JSJC'] = 16]));
    expect(
      () => high.candidate(ScheduleData(), SchoolClock.instant(2026, 8, 31)),
      throwsFormatException,
    );
  });
  test('仅校园 HTTPS 可作为课表源，VPN 前缀路径可识别', () {
    expect(
      isSchoolTimetableUrl(
        Uri.parse('https://ehall.seu.edu.cn/jwapp/sys/wdkb/*default/index.do'),
      ),
      isTrue,
    );
    expect(
      isSchoolTimetableUrl(
        Uri.parse('https://vpn.seu.edu.cn/proxy/abc/jwapp/sys/wdkb/index.do'),
      ),
      isTrue,
    );
    for (final value in [
      'https://seu.edu.cn.evil.test/jwapp/sys/wdkb/',
      'http://ehall.seu.edu.cn/jwapp/sys/wdkb/',
      'https://vpn.seu.edu.cn/login',
    ]) {
      expect(isSchoolTimetableUrl(Uri.parse(value)), isFalse);
    }
  });
  test('旧办事大厅登录回跳升级 HTTPS，保留票据且不放行其他 HTTP', () {
    final legacy = Uri.parse(
      'http://ehall.seu.edu.cn/login?ticket=TEST_ONLY&service=a%2Fb',
    );
    final target = schoolNavigationTarget(legacy)!;
    expect(target.scheme, 'https');
    expect(target.port, 443);
    expect(target.path, legacy.path);
    expect(target.query, legacy.query);
    expect(schoolNavigationTarget(target), target);
    for (final value in [
      'http://other.seu.edu.cn/login',
      'http://ehall.seu.edu.cn.evil.test/login',
      'http://ehall.seu.edu.cn:8080/login',
      'http://user:secret@ehall.seu.edu.cn/login',
    ]) {
      expect(schoolNavigationTarget(Uri.parse(value)), isNull);
    }
  });
  test('导入保留完整旧数据，重启可读取，无效导入不覆盖旧文件', () async {
    final dir = await Directory.systemTemp.createTemp('meike-import-');
    addTearDown(() => dir.delete(recursive: true));
    final store = ScheduleStore(File('${dir.path}/schedule.json'));
    addTearDown(store.dispose);
    await store.load();
    await store.replace(
      ScheduleData(
        courses: [
          Course(name: '手动', meetings: [WeeklyMeeting()]),
        ],
      ),
    );
    final before = await store.exportBytes();
    final candidate = SchoolImport.parse(
      payload([row()]),
    ).candidate(store.data, SchoolClock.instant(2026, 8, 31));
    await store.importSchool(candidate);
    final backups = await dir
        .list()
        .where((f) => f.path.contains('before-school-import-'))
        .toList();
    expect(backups, hasLength(1));
    expect(await File(backups.single.path).readAsBytes(), before);
    final reopened = ScheduleStore(store.file);
    addTearDown(reopened.dispose);
    await reopened.load();
    expect(reopened.data.courses, hasLength(2));
    final bytes = await store.file.readAsBytes();
    await expectLater(
      store.importSchool(candidate.copy()..semester.weekCount = 0),
      throwsFormatException,
    );
    expect(await store.file.readAsBytes(), bytes);
  });
  testWidgets('空课表和已有课表都有导入入口，窄屏无溢出', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('meike-import-ui-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final store = ScheduleStore(File('${dir.path}/schedule.json'));
    addTearDown(store.dispose);
    await tester.runAsync(store.load);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(SeuTimetableApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('一键导入学校课表'), findsOneWidget);
    expect(find.byTooltip('一键导入学校课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.runAsync(
      () async => store.replace(
        ScheduleData(courses: ScheduleData.demo(store.data.semester)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('一键导入学校课表'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('预览必须确认开学周，退出预览不改变课表', (tester) async {
    final dir = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('meike-preview-'),
    ))!;
    addTearDown(() => dir.delete(recursive: true));
    final store = ScheduleStore(File('${dir.path}/schedule.json'));
    addTearDown(store.dispose);
    await tester.runAsync(store.load);
    await tester.pumpWidget(
      MaterialApp(
        home: SchoolImportPreview(
          store: store,
          imported: SchoolImport.parse(payload([row()])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '确认导入 1 门课程'))
          .onPressed,
      isNull,
    );
    expect(find.text('请选择日期，确保周次准确（必填）'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(store.data.courses, isEmpty);
    expect(await tester.runAsync(store.file.exists), isFalse);
  });
}
