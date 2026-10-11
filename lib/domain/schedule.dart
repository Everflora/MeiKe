import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:characters/characters.dart';
import 'package:uuid/uuid.dart';

String newId() => const Uuid().v4().toUpperCase();
typedef Json = Map<String, dynamic>;

enum WeekPattern {
  every('每周'),
  odd('单周'),
  even('双周');

  const WeekPattern(this.title);
  final String title;
  bool includes(int week) =>
      this == every || (this == odd ? week.isOdd : week.isEven);
}

enum CourseColor {
  jade('青绿'),
  blue('天蓝'),
  peach('杏橙'),
  violet('浅紫'),
  rose('玫瑰'),
  mint('薄荷'),
  teal('湖绿'),
  cyan('冰青'),
  indigo('靛蓝'),
  lavender('薰衣草'),
  plum('梅紫'),
  coral('珊瑚'),
  red('朱红'),
  amber('琥珀'),
  lemon('柠黄'),
  lime('青柠'),
  olive('橄榄'),
  slate('雾蓝'),
  espresso('咖啡'),
  sand('燕麦');

  const CourseColor(this.title);
  final String title;
}

// Work in Shanghai wall-clock dates independently of the phone's time zone.
// UTC+08:00 has no DST over the supported 2000–2100 date range.
abstract final class SchoolClock {
  static const offset = Duration(hours: 8);
  static const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  static DateTime wall(DateTime instant) => instant.toUtc().add(offset);
  static DateTime instant(
    int year,
    int month,
    int day, [
    int hour = 0,
    int minute = 0,
    int second = 0,
  ]) => DateTime.utc(year, month, day, hour, minute, second).subtract(offset);
  static DateTime day(DateTime instant) {
    final w = wall(instant);
    return DateTime.utc(w.year, w.month, w.day);
  }

  static DateTime monday(DateTime instant) {
    final d = day(instant);
    return d.subtract(Duration(days: d.weekday - 1)).subtract(offset);
  }

  static int week(DateTime instant, Semester semester) =>
      (day(instant).difference(day(monday(semester.startDate))).inDays / 7)
          .floor() +
      1;
  static int weekday(DateTime instant) => wall(instant).weekday;
  static int minute(DateTime instant) =>
      wall(instant).hour * 60 + wall(instant).minute;
  static DateTime date(int week, int weekday, Semester semester) => monday(
    semester.startDate,
  ).add(Duration(days: (week - 1) * 7 + weekday - 1));
  static String shortDate(DateTime instant) {
    final w = wall(instant);
    return '${w.month}.${w.day}';
  }

  static String fullDate(DateTime instant) {
    final w = wall(instant);
    return '${w.year}年${w.month}月${w.day}日 ${weekdays[w.weekday - 1]}';
  }
}

class LessonPeriod {
  LessonPeriod({
    required this.id,
    required this.startMinute,
    required this.endMinute,
  });
  int id, startMinute, endMinute;
  static String format(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  static List<LessonPeriod> defaults() =>
      [480, 530, 590, 640, 690, 840, 890, 950, 1000, 1050, 1140, 1190, 1240]
          .indexed
          .map(
            (p) => LessonPeriod(
              id: p.$1 + 1,
              startMinute: p.$2,
              endMinute: p.$2 + 45,
            ),
          )
          .toList();
  factory LessonPeriod.fromJson(Json j) => LessonPeriod(
    id: j['id'] as int,
    startMinute: j['startMinute'] as int,
    endMinute: j['endMinute'] as int,
  );
  Json toJson() => {
    'id': id,
    'startMinute': startMinute,
    'endMinute': endMinute,
  };
}

class Semester {
  Semester({
    this.name = '我的学期',
    DateTime? startDate,
    this.weekCount = 20,
    List<LessonPeriod>? periods,
  }) : startDate = startDate ?? SchoolClock.monday(DateTime.now()),
       periods = periods ?? LessonPeriod.defaults();
  String name;
  DateTime startDate;
  int weekCount;
  List<LessonPeriod> periods;
  factory Semester.fromJson(Json j) => Semester(
    name: j['name'] as String,
    startDate: _date(j['startDate']),
    weekCount: j['weekCount'] as int,
    periods: (j['periods'] as List)
        .map((e) => LessonPeriod.fromJson(e as Json))
        .toList(),
  );
  Json toJson() => {
    'name': name,
    'startDate': startDate.toUtc().toIso8601String().replaceFirst(
      RegExp(r'\.\d+(?=Z$)'),
      '',
    ),
    'weekCount': weekCount,
    'periods': periods.map((p) => p.toJson()).toList(),
  };
  Semester copy() => Semester.fromJson(toJson());
}

class WeeklyMeeting {
  WeeklyMeeting({
    String? id,
    this.weekday = 1,
    this.startPeriod = 1,
    this.endPeriod = 2,
    this.startWeek = 1,
    this.endWeek = 20,
    this.pattern = WeekPattern.every,
    this.location = '',
  }) : id = id ?? newId();
  String id, location;
  int weekday, startPeriod, endPeriod, startWeek, endWeek;
  WeekPattern pattern;
  bool occurs(int week) =>
      week >= startWeek && week <= endWeek && pattern.includes(week);
  String get periodLabel => startPeriod == endPeriod
      ? '第 $startPeriod 节'
      : '第 $startPeriod–$endPeriod 节';
  String get summary => '${SchoolClock.weekdays[weekday - 1]} · $periodLabel';
  String get recurrence => '第 $startWeek–$endWeek 周 · ${pattern.title}';
  List<WeeklyMeeting> onWeekdays(Set<int> days) =>
      (days.toList()..sort()).indexed.map((p) {
        final m = copy();
        m.weekday = p.$2;
        if (p.$1 > 0) m.id = newId();
        return m;
      }).toList();
  factory WeeklyMeeting.fromJson(Json j) => WeeklyMeeting(
    id: _id(j['id']),
    weekday: j['weekday'] as int,
    startPeriod: j['startPeriod'] as int,
    endPeriod: j['endPeriod'] as int,
    startWeek: j['startWeek'] as int,
    endWeek: j['endWeek'] as int,
    pattern: WeekPattern.values.byName(j['pattern'] as String),
    location: j['location'] as String,
  );
  Json toJson() => {
    'id': id,
    'weekday': weekday,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'startWeek': startWeek,
    'endWeek': endWeek,
    'pattern': pattern.name,
    'location': location,
  };
  WeeklyMeeting copy() => WeeklyMeeting.fromJson(toJson());
}

class ExtraMeeting {
  ExtraMeeting({
    String? id,
    this.title = '实验',
    this.week = 1,
    this.weekday = 7,
    this.allDay = false,
    this.startMinute = 480,
    this.endMinute = 1020,
    this.location = '',
    this.teacher = '',
    this.notes = '',
  }) : id = id ?? newId();
  String id, title, location, teacher, notes;
  int week, weekday, startMinute, endMinute;
  bool allDay;
  String get timeLabel => allDay
      ? '全天'
      : '${LessonPeriod.format(startMinute)}–${LessonPeriod.format(endMinute)}';
  String get summary =>
      '第 $week 周 · ${SchoolClock.weekdays[weekday - 1]} · $timeLabel';
  factory ExtraMeeting.fromJson(Json j) => ExtraMeeting(
    id: _id(j['id']),
    title: j['title'] as String,
    week: j['week'] as int,
    weekday: j['weekday'] as int,
    allDay: j['allDay'] as bool,
    startMinute: j['startMinute'] as int,
    endMinute: j['endMinute'] as int,
    location: j['location'] as String,
    teacher: j['teacher'] as String,
    notes: j['notes'] as String,
  );
  Json toJson() => {
    'id': id,
    'title': title,
    'week': week,
    'weekday': weekday,
    'allDay': allDay,
    'startMinute': startMinute,
    'endMinute': endMinute,
    'location': location,
    'teacher': teacher,
    'notes': notes,
  };
  ExtraMeeting copy() => ExtraMeeting.fromJson(toJson());
}

class SchoolClass {
  SchoolClass({
    required this.termCode,
    required this.courseCode,
    required this.classId,
    required this.classNumber,
  });
  final String termCode, courseCode, classId, classNumber;
  List<String>? get identity => classId.isNotEmpty
      ? ['JXBID', classId]
      : classNumber.isNotEmpty && courseCode.isNotEmpty
      ? ['JXBH', courseCode, classNumber]
      : null;
  String? get key =>
      identity == null ? null : jsonEncode([termCode, ...identity!]);
  factory SchoolClass.fromJson(Json j) => SchoolClass(
    termCode: j['termCode'] as String,
    courseCode: j['courseCode'] as String,
    classId: j['classId'] as String,
    classNumber: j['classNumber'] as String,
  );
  Json toJson() => {
    'termCode': termCode,
    'courseCode': courseCode,
    'classId': classId,
    'classNumber': classNumber,
  };
}

class Course {
  Course({
    String? id,
    this.name = '',
    this.teacher = '',
    this.location = '',
    this.color = CourseColor.jade,
    this.notes = '',
    this.schoolClass,
    List<WeeklyMeeting>? meetings,
    List<ExtraMeeting>? extras,
  }) : id = id ?? newId(),
       meetings = meetings ?? [],
       extras = extras ?? [];
  String id, name, teacher, location, notes;
  SchoolClass? schoolClass;
  CourseColor color;
  List<WeeklyMeeting> meetings;
  List<ExtraMeeting> extras;
  factory Course.fromJson(Json j) => Course(
    id: _id(j['id']),
    name: j['name'] as String,
    teacher: j['teacher'] as String,
    location: j['location'] as String,
    color: CourseColor.values.byName(j['color'] as String),
    notes: j['notes'] as String,
    schoolClass: j['schoolClass'] == null
        ? null
        : SchoolClass.fromJson(j['schoolClass'] as Json),
    meetings: (j['meetings'] as List)
        .map((e) => WeeklyMeeting.fromJson(e as Json))
        .toList(),
    extras: (j['extras'] as List)
        .map((e) => ExtraMeeting.fromJson(e as Json))
        .toList(),
  );
  Json toJson() => {
    'id': id,
    'name': name,
    'teacher': teacher,
    'location': location,
    'color': color.name,
    'notes': notes,
    if (schoolClass != null) 'schoolClass': schoolClass!.toJson(),
    'meetings': meetings.map((m) => m.toJson()).toList(),
    'extras': extras.map((m) => m.toJson()).toList(),
  };
  Course copy() => Course.fromJson(toJson());
  String get searchText =>
      '$name $teacher $location ${meetings.map((m) => m.location).join(' ')} ${extras.map((e) => '${e.title} ${e.location} ${e.teacher}').join(' ')}'
          .toLowerCase();
}

class MinuteRange {
  const MinuteRange(this.start, this.end);
  final int start, end;
  bool contains(int minute) => start <= minute && minute < end;
  bool overlaps(MinuteRange other) =>
      math.max(start, other.start) < math.min(end, other.end);
}

class BreakSlot extends MinuteRange {
  const BreakSlot(super.start, super.end);
  int get duration => end - start;
  String get title => duration >= 60 && start < 840
      ? '午休'
      : (duration >= 30 && start >= 1020 ? '晚饭 / 休息' : '课间休息');
}

class Occurrence {
  const Occurrence({
    required this.id,
    required this.courseId,
    required this.sourceId,
    required this.name,
    required this.teacher,
    required this.location,
    required this.color,
    required this.week,
    required this.weekday,
    required this.startMinute,
    required this.endMinute,
    required this.periodLabel,
    required this.isExtra,
    required this.allDay,
    required this.notes,
    required this.busyRanges,
  });
  final String id,
      courseId,
      sourceId,
      name,
      teacher,
      location,
      periodLabel,
      notes;
  final CourseColor color;
  final int week, weekday, startMinute, endMinute;
  final bool isExtra, allDay;
  final List<MinuteRange> busyRanges;
  String get timeLabel => allDay
      ? '全天'
      : '${LessonPeriod.format(startMinute)}–${LessonPeriod.format(endMinute)}';
  bool overlaps(Occurrence other) =>
      id != other.id &&
      week == other.week &&
      weekday == other.weekday &&
      busyRanges.any((r) => other.busyRanges.any(r.overlaps));
  int? secondsUntilLessonEnds(DateTime now) {
    if (allDay) return null;
    final minute = SchoolClock.minute(now);
    for (final r in busyRanges) {
      if (r.contains(minute)) {
        final end = SchoolClock.day(
          now,
        ).subtract(SchoolClock.offset).add(Duration(minutes: r.end));
        return math.max(
          0,
          (end.difference(now).inMicroseconds / Duration.microsecondsPerSecond)
              .ceil(),
        );
      }
    }
    return null;
  }

  String status(DateTime now) {
    if (allDay) return '全天安排';
    final m = SchoolClock.minute(now);
    if (m < startMinute) return '未开始';
    if (m >= endMinute) return '已结束';
    return busyRanges.any((r) => r.contains(m)) ? '进行中' : '课间休息';
  }
}

class ScheduleData {
  ScheduleData({this.version = 1, Semester? semester, List<Course>? courses})
    : semester = semester ?? Semester(),
      courses = courses ?? [];
  int version;
  Semester semester;
  List<Course> courses;
  List<BreakSlot> get breaks => [
    for (var i = 1; i < semester.periods.length; i++)
      if (semester.periods[i].startMinute > semester.periods[i - 1].endMinute)
        BreakSlot(
          semester.periods[i - 1].endMinute,
          semester.periods[i].startMinute,
        ),
  ];
  factory ScheduleData.fromJson(Json j) => ScheduleData(
    version: j['version'] as int,
    semester: Semester.fromJson(j['semester'] as Json),
    courses: (j['courses'] as List)
        .map((c) => Course.fromJson(c as Json))
        .toList(),
  );
  Json toJson() => {
    'version': version,
    'semester': semester.toJson(),
    'courses': courses.map((c) => c.toJson()).toList(),
  };
  ScheduleData copy() => ScheduleData.fromJson(toJson());
  String? validationError() {
    if (version != 1) return '不支持此备份版本。';
    final s = semester;
    if (s.weekCount < 1 || s.weekCount > 40) return '学期周数需为 1–40。';
    if (s.name.trim().isEmpty || s.name.characters.length > 80) {
      return '请填写学期名称（最多 80 字）。';
    }
    if (SchoolClock.wall(s.startDate).year < 2000 ||
        SchoolClock.wall(s.startDate).year > 2100) {
      return '学期日期需在 2000–2100 年之间。';
    }
    if (s.periods.isEmpty || s.periods.length > 16) return '每天需有 1–16 个节次。';
    var lastEnd = -1;
    for (final (index, p) in s.periods.indexed) {
      if (p.id != index + 1 ||
          p.startMinute < 0 ||
          p.endMinute >= 1440 ||
          p.startMinute >= p.endMinute ||
          p.startMinute < lastEnd) {
        return '第 ${index + 1} 节时间无效：下课应晚于上课，且各节次不能重叠。';
      }
      lastEnd = p.endMinute;
    }
    if (courses.length > 500) return '最多支持 500 门课程。';
    if (courses.map((c) => c.id).toSet().length != courses.length) {
      return '备份中含有重复的课程标识。';
    }
    for (final c in courses) {
      final error = courseError(c);
      if (error != null) return error;
    }
    return null;
  }

  String? courseError(Course c) {
    if (!_validId(c.id)) return '课程标识无效。';
    if (c.name.trim().isEmpty || c.name.characters.length > 80) {
      return '课程名称不能为空，且最多 80 字。';
    }
    if (c.teacher.characters.length > 80 ||
        c.location.characters.length > 120 ||
        c.notes.characters.length > 2000) {
      return '教师最多 80 字，地点最多 120 字，备注最多 2000 字。';
    }
    if (c.meetings.isEmpty && c.extras.isEmpty) return '请添加至少一条常规或额外上课安排。';
    if (c.meetings.length > 30 || c.extras.length > 100) {
      return '每门课程最多 30 条常规安排和 100 条额外安排。';
    }
    final ids = [...c.meetings.map((m) => m.id), ...c.extras.map((e) => e.id)];
    if (ids.toSet().length != ids.length || ids.any((id) => !_validId(id))) {
      return '课程内含有重复或无效的安排标识。';
    }
    for (final m in c.meetings) {
      if (m.weekday < 1 ||
          m.weekday > 7 ||
          m.startPeriod < 1 ||
          m.endPeriod < m.startPeriod ||
          m.endPeriod > semester.periods.length) {
        return '「${c.name}」的节次或星期超出了当前设置。';
      }
      if (m.startWeek < 1 ||
          m.endWeek < m.startWeek ||
          m.endWeek > semester.weekCount) {
        return '「${c.name}」的周次超出了学期范围。';
      }
      if (![
        for (var w = m.startWeek; w <= m.endWeek; w++) w,
      ].any(m.pattern.includes)) {
        return '所选周次内没有符合单双周规则的上课周。';
      }
      if (m.location.characters.length > 120) return '上课地点最多 120 字。';
    }
    for (final e in c.extras) {
      if (e.week < 1 ||
          e.week > semester.weekCount ||
          e.weekday < 1 ||
          e.weekday > 7) {
        return '「${c.name}」的额外安排周次或星期无效。';
      }
      if (e.startMinute < 0 ||
          e.endMinute >= 1440 ||
          e.startMinute >= e.endMinute) {
        return '额外安排的结束时间应晚于开始时间。';
      }
      if (e.title.trim().isEmpty ||
          e.title.characters.length > 80 ||
          e.teacher.characters.length > 80 ||
          e.location.characters.length > 120 ||
          e.notes.characters.length > 2000) {
        return '额外安排标题不能为空；标题/教师最多 80 字，地点最多 120 字，备注最多 2000 字。';
      }
    }
    return null;
  }

  List<Occurrence> occurrencesFor(Course c, int week) {
    if (week < 1 || week > semester.weekCount) return [];
    return [
      for (final m in c.meetings.where((m) => m.occurs(week)))
        Occurrence(
          id: '${c.id}-${m.id}-$week',
          courseId: c.id,
          sourceId: m.id,
          name: c.name,
          teacher: c.teacher,
          location: m.location.isEmpty ? c.location : m.location,
          color: c.color,
          week: week,
          weekday: m.weekday,
          startMinute: semester.periods[m.startPeriod - 1].startMinute,
          endMinute: semester.periods[m.endPeriod - 1].endMinute,
          periodLabel: m.periodLabel,
          isExtra: false,
          allDay: false,
          notes: c.notes,
          busyRanges: semester.periods
              .sublist(m.startPeriod - 1, m.endPeriod)
              .map((p) => MinuteRange(p.startMinute, p.endMinute))
              .toList(),
        ),
      for (final e in c.extras.where((e) => e.week == week))
        Occurrence(
          id: '${c.id}-${e.id}-$week',
          courseId: c.id,
          sourceId: e.id,
          name: '${c.name} · ${e.title}',
          teacher: e.teacher.isEmpty ? c.teacher : e.teacher,
          location: e.location.isEmpty ? c.location : e.location,
          color: c.color,
          week: week,
          weekday: e.weekday,
          startMinute: e.allDay ? 0 : e.startMinute,
          endMinute: e.allDay ? 1440 : e.endMinute,
          periodLabel: e.allDay ? '全天' : '额外安排',
          isExtra: true,
          allDay: e.allDay,
          notes: e.notes,
          busyRanges: [
            MinuteRange(
              e.allDay ? 0 : e.startMinute,
              e.allDay ? 1440 : e.endMinute,
            ),
          ],
        ),
    ];
  }

  List<Occurrence> occurrences(int week, {int? weekday}) {
    final result = courses
        .expand((c) => occurrencesFor(c, week))
        .where((e) => weekday == null || e.weekday == weekday)
        .toList();
    result.sort((a, b) {
      var v = a.weekday.compareTo(b.weekday);
      if (v == 0) v = a.startMinute.compareTo(b.startMinute);
      if (v == 0) v = a.name.compareTo(b.name);
      return v == 0 ? a.id.compareTo(b.id) : v;
    });
    return result;
  }

  List<String> conflicts(Course candidate) {
    final names = <String>{};
    for (var week = 1; week <= semester.weekCount; week++) {
      final own = occurrencesFor(candidate, week);
      final other = courses
          .where((c) => c.id != candidate.id)
          .expand((c) => occurrencesFor(c, week));
      for (final a in own) {
        for (final b in [...own, ...other]) {
          if (a.overlaps(b)) {
            names.add(
              '第 $week 周${SchoolClock.weekdays[a.weekday - 1]}：${b.name}',
            );
          }
        }
      }
    }
    return names.toList()..sort();
  }

  static List<Course> demo(Semester semester) {
    if (semester.periods.length < 9) return [];
    final end = semester.weekCount;
    WeeklyMeeting meeting(int day, int start, int finish) => WeeklyMeeting(
      weekday: day,
      startPeriod: start,
      endPeriod: finish,
      endWeek: end,
    );
    return [
      Course(
        name: '计算机网络',
        teacher: '示例教师',
        location: '教三 · 402',
        color: CourseColor.peach,
        meetings: [meeting(4, 3, 5)],
        extras: [
          ExtraMeeting(
            title: '大型实验',
            week: math.min(8, end),
            weekday: 7,
            allDay: true,
            location: '实验中心 · 301',
            notes: '示例：请携带电脑和实验报告。',
          ),
        ],
      ),
      Course(
        name: '数据库原理',
        teacher: '示例教师',
        location: '教三 · 302',
        meetings: [meeting(1, 3, 5)],
      ),
      Course(
        name: '编译原理',
        teacher: '示例教师',
        location: '教三 · 501',
        color: CourseColor.blue,
        meetings: [meeting(2, 3, 4), meeting(5, 3, 5)],
      ),
      Course(
        name: '大数据处理',
        teacher: '示例教师',
        location: '教三 · 304',
        color: CourseColor.violet,
        meetings: [meeting(3, 3, 4), meeting(4, 8, 9)],
      ),
      Course(
        name: '体育',
        teacher: '示例教师',
        location: '体育馆2楼',
        color: CourseColor.mint,
        meetings: [meeting(3, 2, 2)],
      ),
    ];
  }
}

abstract final class ScheduleCodec {
  static const maxBytes = 2000000;
  static Uint8List encode(ScheduleData data) => Uint8List.fromList(
    utf8.encode(const JsonEncoder.withIndent('  ').convert(data.toJson())),
  );
  static ScheduleData decode(List<int> bytes) {
    if (bytes.length > maxBytes) throw const FormatException('备份不能大于 2 MB。');
    try {
      final data = ScheduleData.fromJson(
        jsonDecode(utf8.decode(bytes)) as Json,
      );
      final error = data.validationError();
      if (error != null) throw FormatException(error);
      return data;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份格式无效或缺少必要字段。');
    }
  }
}

bool _validId(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);
String _id(dynamic value) {
  if (value is! String || !_validId(value)) {
    throw const FormatException('备份标识无效。');
  }
  return value.toUpperCase();
}

DateTime _date(dynamic value) {
  if (value is! String ||
      !RegExp(
        r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d+)?(?:Z|[+-]\d\d:\d\d)$',
      ).hasMatch(value)) {
    throw const FormatException('学期日期应为 ISO 8601 时间。');
  }
  final parts = value.substring(0, 10).split('-').map(int.parse).toList();
  final day = DateTime.utc(parts[0], parts[1], parts[2]);
  if (day.year != parts[0] ||
      day.month != parts[1] ||
      day.day != parts[2] ||
      int.parse(value.substring(11, 13)) > 23 ||
      int.parse(value.substring(14, 16)) > 59 ||
      int.parse(value.substring(17, 19)) > 59) {
    throw const FormatException('学期日期无效。');
  }
  if (!value.endsWith('Z')) {
    final zone = value
        .substring(value.length - 5)
        .split(':')
        .map(int.parse)
        .toList();
    if (zone[0] > 23 || zone[1] > 59) throw const FormatException('学期时区无效。');
  }
  return DateTime.parse(value).toUtc();
}

class TimelineSegment {
  const TimelineSegment(this.start, this.end, this.period, this.y, this.height);
  final int start, end;
  final int? period;
  final double y, height;
  String get label => period?.toString() ?? BreakSlot(start, end).title;
}

class TimelineLayout {
  TimelineLayout(
    List<LessonPeriod> periods, {
    List<Occurrence> occurrences = const [],
    double? fittingHeight,
    bool compact = false,
  }) {
    final timed = occurrences.where((e) => !e.allDay);
    var cursor = periods.first.startMinute;
    var upper = periods.last.endMinute;
    for (final e in timed) {
      cursor = math.min(cursor, e.startMinute);
      upper = math.max(upper, e.endMinute);
    }
    var y = 0.0;
    final result = <TimelineSegment>[];
    for (final p in periods) {
      if (p.startMinute > cursor) {
        final gap = p.startMinute - cursor;
        final h = compact
            ? (gap > 20
                  ? 18.0
                  : gap >= 15
                  ? 8.0
                  : 4.0)
            : (gap > 20 ? 38.0 : 22.0);
        result.add(TimelineSegment(cursor, p.startMinute, null, y, h));
        y += h;
      }
      final lessonHeight = compact ? 52.0 : 68.0;
      result.add(
        TimelineSegment(p.startMinute, p.endMinute, p.id, y, lessonHeight),
      );
      y += lessonHeight;
      cursor = p.endMinute;
    }
    if (cursor < upper) {
      final extraHeight = compact ? 52.0 : 68.0;
      result.add(TimelineSegment(cursor, upper, null, y, extraHeight));
      y += extraHeight;
    }
    final scale = fittingHeight == null
        ? 1.0
        : math.max(1.0, fittingHeight) / y;
    segments = result
        .map(
          (s) => TimelineSegment(
            s.start,
            s.end,
            s.period,
            s.y * scale,
            s.height * scale,
          ),
        )
        .toList();
  }
  late final List<TimelineSegment> segments;
  double get height => segments.last.y + segments.last.height;
  double position(int minute) {
    for (final s in segments) {
      if (minute >= s.start && minute <= s.end) {
        return s.y + (minute - s.start) / (s.end - s.start) * s.height;
      }
    }
    return minute < segments.first.start ? 0 : height;
  }
}

class OccurrenceLane {
  const OccurrenceLane(this.occurrence, this.index, this.count);
  final Occurrence occurrence;
  final int index, count;
  static List<OccurrenceLane> arrange(List<Occurrence> events) {
    final sorted = [...events]
      ..sort((a, b) {
        var v = a.startMinute.compareTo(b.startMinute);
        if (v == 0) v = a.endMinute.compareTo(b.endMinute);
        return v == 0 ? a.id.compareTo(b.id) : v;
      });
    final result = <OccurrenceLane>[];
    var group = <Occurrence>[];
    var groupEnd = -1;
    void flush() {
      final ends = <int>[];
      final assigned = <(Occurrence, int)>[];
      for (final e in group) {
        var index = ends.indexWhere((end) => end <= e.startMinute);
        if (index < 0) {
          index = ends.length;
          ends.add(e.endMinute);
        } else {
          ends[index] = e.endMinute;
        }
        assigned.add((e, index));
      }
      result.addAll(
        assigned.map((a) => OccurrenceLane(a.$1, a.$2, ends.length)),
      );
    }

    for (final e in sorted) {
      if (e.startMinute >= groupEnd && group.isNotEmpty) {
        flush();
        group = [];
        groupEnd = -1;
      }
      group.add(e);
      groupEnd = math.max(groupEnd, e.endMinute);
    }
    if (group.isNotEmpty) flush();
    return result;
  }
}
