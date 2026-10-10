import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'schedule.dart';

/// Adapter for SEU's wdkb/xskcb response. It never reads login credentials.
class SchoolImport {
  SchoolImport._(this.termCode, this.termName, this.courses, this.maxWeek);
  final String termCode, termName;
  final List<Course> courses;
  final int maxWeek;

  static SchoolImport parse(Json payload) {
    final termCode = _text(payload['termCode']);
    final termName = _text(payload['termName']);
    final rows = payload['rows'];
    if (termCode.isEmpty || termName.isEmpty || rows is! List || rows.isEmpty) {
      throw const FormatException('没有读到完整课表，请登录并选择有课程的学期。');
    }
    if (termCode.length > 100 || termName.length > 80 || rows.length > 5000) {
      throw const FormatException('学校返回的课表数据超过支持范围。');
    }
    final grouped = <String, Course>{};
    final seen = <String>{};
    var maxWeek = 1;
    for (var index = 0; index < rows.length; index++) {
      final raw = rows[index];
      if (raw is! Json) throw FormatException('第 ${index + 1} 条课表数据格式无效。');
      final name = _text(raw['KCM'] ?? raw['KCMC']);
      final teacher = _text(raw['SKJS']);
      final location = _text(raw['JASMC']);
      final code = _text(raw['KCH']);
      final classCode = _text(raw['JXBID'] ?? raw['JXBH']);
      final day = _integer(raw['SKXQ']);
      final start = _integer(raw['KSJC']);
      final end = _integer(raw['JSJC']);
      if (name.isEmpty ||
          day < 1 ||
          day > 7 ||
          start < 1 ||
          end < start ||
          end > 16) {
        throw FormatException(
          '「${name.isEmpty ? '第 ${index + 1} 条课程' : name}」的星期或节次无法识别，原课表未更改。',
        );
      }
      final weeks = parseWeeks(_text(raw['ZCMC']));
      maxWeek = weeks.last > maxWeek ? weeks.last : maxWeek;
      // A separate teacher gets a separate course because WeeklyMeeting has no
      // teacher override. Course and meeting IDs remain stable across imports.
      final key = jsonEncode([
        termCode,
        code.isEmpty ? name : code,
        classCode,
        teacher,
      ]);
      final id = _id(key);
      final course = grouped.putIfAbsent(
        id,
        () => Course(
          id: id,
          name: name,
          teacher: teacher,
          location: location,
          color: CourseColor.values[grouped.length % CourseColor.values.length],
          notes: '学校课表 · $termName${code.isEmpty ? '' : '\n课程号：$code'}',
          schoolClass: SchoolClass(
            termCode: termCode,
            courseCode: code,
            classId: _text(raw['JXBID']),
            classNumber: _text(raw['JXBH']),
          ),
        ),
      );
      final signature = jsonEncode([id, day, start, end, location, weeks]);
      if (!seen.add(signature)) continue;
      for (final range in _ranges(weeks)) {
        course.meetings.add(
          WeeklyMeeting(
            id: _id(jsonEncode([signature, range.$1, range.$2, range.$3.name])),
            weekday: day,
            startPeriod: start,
            endPeriod: end,
            startWeek: range.$1,
            endWeek: range.$2,
            pattern: range.$3,
            location: location,
          ),
        );
      }
    }
    for (final course in grouped.values) {
      final slots = <String, (WeeklyMeeting, Set<int>)>{};
      for (final meeting in course.meetings) {
        final key = jsonEncode([
          meeting.weekday,
          meeting.startPeriod,
          meeting.endPeriod,
          meeting.location,
        ]);
        final slot = slots.putIfAbsent(key, () => (meeting, <int>{}));
        for (var week = meeting.startWeek; week <= meeting.endWeek; week++) {
          if (meeting.pattern.includes(week)) slot.$2.add(week);
        }
      }
      course.meetings = [
        for (final slot in slots.entries)
          for (final range in _ranges(slot.value.$2.toList()..sort()))
            slot.value.$1.copy()
              ..id = _id(
                jsonEncode([
                  course.id,
                  slot.key,
                  range.$1,
                  range.$2,
                  range.$3.name,
                ]),
              )
              ..startWeek = range.$1
              ..endWeek = range.$2
              ..pattern = range.$3,
      ];
    }
    return SchoolImport._(termCode, termName, grouped.values.toList(), maxWeek);
  }

  /// No date is guessed from the term code: the user confirms week one's Monday.
  ScheduleData candidate(
    ScheduleData current,
    DateTime startDate, {
    bool replace = false,
  }) {
    final result = current.copy();
    result.semester
      ..name = termName
      ..startDate = SchoolClock.monday(startDate)
      ..weekCount = maxWeek > result.semester.weekCount
          ? maxWeek
          : result.semester.weekCount;
    final highestPeriod = courses
        .expand((c) => c.meetings)
        .fold(1, (n, m) => m.endPeriod > n ? m.endPeriod : n);
    if (highestPeriod > result.semester.periods.length) {
      throw FormatException('学校课表包含第 $highestPeriod 节，请先在设置中补齐节次时间。');
    }
    if (replace) result.courses.clear();
    for (final incoming in courses) {
      final position = result.courses.indexWhere((c) => c.id == incoming.id);
      final course = incoming.copy();
      if (position < 0) {
        result.courses.add(course);
      } else {
        final existing = result.courses[position];
        course
          ..color = existing.color
          ..notes = existing.notes
          ..extras = existing.extras.map((e) => e.copy()).toList();
        result.courses[position] = course;
      }
    }
    final error = result.validationError();
    if (error != null) throw FormatException(error);
    return result;
  }

  static List<int> parseWeeks(String source) {
    if (source.isEmpty || source.length > 500) {
      throw const FormatException('无法识别上课周次，原课表未更改。');
    }
    var value = source
        .replaceAll(RegExp(r'[\s第周]'), '')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll(RegExp('[，、;；]'), ',')
        .replaceAll(RegExp('[—–－~～至]'), '-');
    final result = <int>{};
    for (final part in value.split(',')) {
      final match = RegExp(
        r'^(\d+)(?:-(\d+))?(?:\(([单双])\)|([单双]))?$',
      ).firstMatch(part);
      if (match == null) throw FormatException('无法识别周次「$source」，原课表未更改。');
      final start = int.parse(match.group(1)!);
      final end = int.parse(match.group(2) ?? match.group(1)!);
      final parity = match.group(3) ?? match.group(4);
      if (start < 1 || end < start || end > 40) {
        throw FormatException('周次「$source」超出 1–40 周范围。');
      }
      for (var week = start; week <= end; week++) {
        if (parity == null || (parity == '单' ? week.isOdd : week.isEven)) {
          result.add(week);
        }
      }
    }
    if (result.isEmpty) throw FormatException('周次「$source」没有有效上课周。');
    return result.toList()..sort();
  }

  static Iterable<(int, int, WeekPattern)> _ranges(List<int> weeks) sync* {
    var index = 0;
    while (index < weeks.length) {
      final start = weeks[index];
      var end = start;
      var step = 1;
      if (index + 1 < weeks.length && weeks[index + 1] - start <= 2) {
        step = weeks[index + 1] - start;
        while (index + 1 < weeks.length && weeks[index + 1] - end == step) {
          end = weeks[++index];
        }
      }
      yield (
        start,
        end,
        step == 1
            ? WeekPattern.every
            : (start.isOdd ? WeekPattern.odd : WeekPattern.even),
      );
      index++;
    }
  }

  static int _integer(dynamic value) => int.tryParse(_text(value)) ?? -1;
  static String _text(dynamic value) {
    if (value == null) return '';
    final text = value.toString().trim();
    return text.toLowerCase() == 'null' ? '' : text;
  }

  static String _id(String key) => const Uuid()
      .v5(Namespace.url.value, 'https://ehall.seu.edu.cn/meike/$key')
      .toUpperCase();
}

bool isSchoolUrl(Uri url) =>
    url.scheme == 'https' &&
    (url.host == 'seu.edu.cn' || url.host.endsWith('.seu.edu.cn'));

bool isSchoolTimetableUrl(Uri url) =>
    isSchoolUrl(url) && url.path.contains('/jwapp/sys/wdkb/');

/// The legacy CAS service URL uses HTTP. Never load it in cleartext; replay
/// the main-frame navigation over the verified HTTPS ehall entry instead.
Uri? schoolNavigationTarget(Uri url) {
  if (isSchoolUrl(url)) return url;
  if (url.scheme == 'http' &&
      url.host == 'ehall.seu.edu.cn' &&
      url.port == 80 &&
      url.userInfo.isEmpty) {
    return url.replace(scheme: 'https', port: 443);
  }
  return null;
}
