import 'schedule.dart';

/// Called only after explicit permission. Returns abstract half-hour slots;
/// course names, locations, and the source timetable never leave the device.
List<int> teamFreeSlots(
  ScheduleData schedule,
  DateTime monday, {
  int from = 8 * 60,
  int to = 22 * 60,
}) {
  final week = SchoolClock.week(monday, schedule.semester);
  if (week < 1 || week > schedule.semester.weekCount) {
    throw const FormatException('所选日期不在当前课表学期内，请选择本学期的一周或手动提供空闲时间。');
  }
  final occupied = schedule.occurrences(week);
  return [
    for (var day = 1; day <= 7; day++)
      for (var minute = from; minute + 30 <= to; minute += 30)
        if (!occupied.any(
          (o) =>
              o.weekday == day &&
              o.busyRanges.any((r) => r.start < minute + 30 && r.end > minute),
        ))
          (day - 1) * 48 + minute ~/ 30,
  ];
}

String teamSlotLabel(int slot) =>
    '${SchoolClock.weekdays[slot ~/ 48]} ${LessonPeriod.format(slot % 48 * 30)}–${LessonPeriod.format(slot % 48 * 30 + 30)}';
