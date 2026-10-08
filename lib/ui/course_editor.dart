import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'theme.dart';

Future<void> editCourse(
  BuildContext context,
  ScheduleStore store, [
  Course? course,
]) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => CourseEditor(store: store, course: course),
  ),
);

class CourseEditor extends StatefulWidget {
  const CourseEditor({super.key, required this.store, this.course});
  final ScheduleStore store;
  final Course? course;
  @override
  State<CourseEditor> createState() => _CourseEditorState();
}

class _CourseEditorState extends State<CourseEditor> {
  late final Course draft = widget.course?.copy() ?? Course();
  late final String initial = jsonEncode(draft.toJson());
  bool saving = false, closing = false;
  void close() {
    setState(() => closing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    final error = widget.store.data.courseError(draft);
    if (error != null) {
      await showError(context, FormatException(error));
      return;
    }
    final conflicts = widget.store.data.conflicts(draft);
    if (conflicts.isNotEmpty &&
        !await confirm(
          context,
          '发现时间冲突',
          '${conflicts.take(5).join('\n')}${conflicts.length > 5 ? '\n另有 ${conflicts.length - 5} 处冲突。' : ''}',
          action: '仍然保存',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() => saving = true);
    try {
      await widget.store.saveCourse(draft);
      if (mounted) close();
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> weekly([WeeklyMeeting? original]) async {
    final semester = widget.store.data.semester;
    final result = await Navigator.push<List<WeeklyMeeting>>(
      context,
      MaterialPageRoute(
        builder: (_) => WeeklyEditor(
          semester: semester,
          initial:
              original ??
              WeeklyMeeting(
                endPeriod: math.min(2, semester.periods.length),
                endWeek: semester.weekCount,
              ),
          multiDay: original == null,
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      for (final m in result) {
        final index = draft.meetings.indexWhere((e) => e.id == m.id);
        if (index < 0) {
          draft.meetings.add(m);
        } else {
          draft.meetings[index] = m;
        }
      }
    });
  }

  Future<void> extra([ExtraMeeting? original]) async {
    final semester = widget.store.data.semester;
    final result = await Navigator.push<ExtraMeeting>(
      context,
      MaterialPageRoute(
        builder: (_) => ExtraEditor(
          semester: semester,
          initial:
              original ??
              ExtraMeeting(
                week: SchoolClock.week(
                  DateTime.now(),
                  semester,
                ).clamp(1, semester.weekCount),
              ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = draft.extras.indexWhere((e) => e.id == result.id);
      if (index < 0) {
        draft.extras.add(result);
      } else {
        draft.extras[index] = result;
      }
    });
  }

  Future<void> removeCourse() async {
    if (!await confirm(
      context,
      '删除「${draft.name}」？',
      '该课程的所有常规和额外安排都会删除。',
      action: '删除课程',
      destructive: true,
    )) {
      return;
    }
    try {
      await widget.store.deleteCourse(draft.id);
      if (mounted) close();
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: closing,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || saving) return;
      if (jsonEncode(draft.toJson()) == initial ||
          await confirm(context, '放弃未保存的修改？', '这次编辑尚未写入课表。', action: '放弃修改')) {
        if (mounted) close();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.course == null ? '添加课程' : '编辑课程'),
        actions: [
          TextButton(
            onPressed: saving ? null : save,
            child: Text(saving ? '保存中…' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionCard(
            title: '课程信息',
            children: [
              EditField(
                label: '课程名称（必填）',
                value: draft.name,
                onChanged: (v) => draft.name = v,
                maxLength: 80,
              ),
              EditField(
                label: '任课教师',
                value: draft.teacher,
                onChanged: (v) => draft.teacher = v,
                maxLength: 80,
              ),
              EditField(
                label: '默认上课地点',
                value: draft.location,
                onChanged: (v) => draft.location = v,
                maxLength: 120,
              ),
            ],
          ),
          SectionCard(
            title: '课程颜色 · 20 种',
            children: [
              GridView.count(
                crossAxisCount: 5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.92,
                children: [
                  for (final color in CourseColor.values)
                    Semantics(
                      label: color.title,
                      selected: draft.color == color,
                      button: true,
                      child: InkWell(
                        onTap: () => setState(() => draft.color = color),
                        borderRadius: BorderRadius.circular(12),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color.pastel,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: draft.color == color
                                      ? color.tint
                                      : Colors.transparent,
                                  width: 2,
                                ),
                              ),
                              child: draft.color == color
                                  ? Icon(
                                      Icons.check,
                                      size: 20,
                                      color: color.tint,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              color.title,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          SectionCard(
            title: '每周上课时间 · ${draft.meetings.length} 条',
            footer: '周一、周四相同时间可一次勾选两天；不同节次或教室可分别添加。',
            children: [
              for (final meeting in draft.meetings)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(meeting.summary),
                  subtitle: Text(
                    '${meeting.recurrence}${meeting.location.isEmpty ? '' : '\n${meeting.location}'}',
                  ),
                  onTap: () => weekly(meeting),
                  trailing: IconButton(
                    tooltip: '移除这条上课时间',
                    onPressed: () =>
                        setState(() => draft.meetings.remove(meeting)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              TextButton.icon(
                onPressed: () => weekly(),
                icon: const Icon(Icons.add_circle_outline),
                label: Text(
                  draft.meetings.isEmpty ? '添加每周上课时间（可选多天）' : '再添加一次每周上课时间',
                ),
              ),
            ],
          ),
          SectionCard(
            title: '额外安排 · ${draft.extras.length} 条',
            footer: '适用于指定周的全天实验、补课或考试，独立于单双周规则；不会自动取消常规课。',
            children: [
              for (final meeting in draft.extras)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(meeting.title),
                  subtitle: Text(
                    '${meeting.summary}${meeting.location.isEmpty ? '' : '\n${meeting.location}'}',
                  ),
                  onTap: () => extra(meeting),
                  trailing: IconButton(
                    tooltip: '移除这条额外安排',
                    onPressed: () =>
                        setState(() => draft.extras.remove(meeting)),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              TextButton.icon(
                onPressed: () => extra(),
                icon: const Icon(Icons.add_circle_outline),
                label: const Text('添加额外安排'),
              ),
            ],
          ),
          SectionCard(
            title: '课程备注',
            children: [
              EditField(
                label: '教材、作业或其他说明',
                value: draft.notes,
                onChanged: (v) => draft.notes = v,
                lines: 4,
                maxLength: 2000,
              ),
            ],
          ),
          if (widget.course != null)
            TextButton(
              onPressed: saving ? null : removeCourse,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('删除这门课程及所有安排'),
            ),
          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}

class EditField extends StatelessWidget {
  const EditField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.lines = 1,
    this.maxLength,
  });
  final String label, value;
  final ValueChanged<String> onChanged;
  final int lines;
  final int? maxLength;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      initialValue: value,
      onChanged: onChanged,
      maxLines: lines,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: label,
        counterText: '',
        border: const OutlineInputBorder(),
      ),
    ),
  );
}

Widget numberChoice({
  required String label,
  required int value,
  required int min,
  required int max,
  required ValueChanged<int> onChanged,
  String Function(int)? format,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: DropdownButtonFormField<int>(
    key: ValueKey('$label-$value-$min-$max'),
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: [
      for (var n = min; n <= max; n++)
        DropdownMenuItem(value: n, child: Text(format?.call(n) ?? '$n')),
    ],
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  ),
);

class WeeklyEditor extends StatefulWidget {
  const WeeklyEditor({
    super.key,
    required this.semester,
    required this.initial,
    required this.multiDay,
  });
  final Semester semester;
  final WeeklyMeeting initial;
  final bool multiDay;
  @override
  State<WeeklyEditor> createState() => _WeeklyEditorState();
}

class _WeeklyEditorState extends State<WeeklyEditor> {
  late final WeeklyMeeting draft = widget.initial.copy();
  late final Set<int> days = {draft.weekday};
  void finish() {
    final result = widget.multiDay ? draft.onWeekdays(days) : [draft];
    final data = ScheduleData(semester: widget.semester);
    final error = result.isEmpty
        ? '请至少选择一个上课日。'
        : data.courseError(Course(name: '当前课程', meetings: result));
    if (error != null) {
      showError(context, FormatException(error));
    } else {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('常规上课时间'),
      actions: [TextButton(onPressed: finish, child: const Text('完成'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '每周哪天上课',
          footer: widget.multiDay ? '可选择多天，以下规则应用到每个选中的星期；保存后可分别编辑。' : null,
          children: [
            if (widget.multiDay)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var day = 1; day <= 7; day++)
                    FilterChip(
                      label: Text(SchoolClock.weekdays[day - 1]),
                      selected: days.contains(day),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          days.add(day);
                        } else {
                          days.remove(day);
                        }
                      }),
                    ),
                ],
              )
            else
              numberChoice(
                label: '星期',
                value: draft.weekday,
                min: 1,
                max: 7,
                format: (d) => SchoolClock.weekdays[d - 1],
                onChanged: (v) => setState(() => draft.weekday = v),
              ),
          ],
        ),
        SectionCard(
          title: '上课节次',
          children: [
            numberChoice(
              label: '开始节次',
              value: draft.startPeriod,
              min: 1,
              max: widget.semester.periods.length,
              format: (p) =>
                  '第 $p 节 · ${LessonPeriod.format(widget.semester.periods[p - 1].startMinute)}',
              onChanged: (v) => setState(() {
                draft.startPeriod = v;
                draft.endPeriod = math.max(v, draft.endPeriod);
              }),
            ),
            numberChoice(
              label: '结束节次',
              value: draft.endPeriod,
              min: draft.startPeriod,
              max: widget.semester.periods.length,
              format: (p) =>
                  '第 $p 节 · ${LessonPeriod.format(widget.semester.periods[p - 1].endMinute)}',
              onChanged: (v) => setState(() => draft.endPeriod = v),
            ),
          ],
        ),
        SectionCard(
          title: '教学周',
          footer: '单双周按教学周计算，第 1、3、5 周为单周。',
          children: [
            numberChoice(
              label: '开始教学周',
              value: draft.startWeek,
              min: 1,
              max: widget.semester.weekCount,
              format: (v) => '第 $v 周',
              onChanged: (v) => setState(() {
                draft.startWeek = v;
                draft.endWeek = math.max(v, draft.endWeek);
              }),
            ),
            numberChoice(
              label: '结束教学周',
              value: draft.endWeek,
              min: draft.startWeek,
              max: widget.semester.weekCount,
              format: (v) => '第 $v 周',
              onChanged: (v) => setState(() => draft.endWeek = v),
            ),
            SegmentedButton<WeekPattern>(
              segments: [
                for (final p in WeekPattern.values)
                  ButtonSegment(value: p, label: Text(p.title)),
              ],
              selected: {draft.pattern},
              onSelectionChanged: (v) =>
                  setState(() => draft.pattern = v.first),
            ),
          ],
        ),
        SectionCard(
          title: '本次安排的地点',
          children: [
            EditField(
              label: '留空使用课程默认地点',
              value: draft.location,
              onChanged: (v) => draft.location = v,
              maxLength: 120,
            ),
          ],
        ),
      ],
    ),
  );
}

class ExtraEditor extends StatefulWidget {
  const ExtraEditor({super.key, required this.semester, required this.initial});
  final Semester semester;
  final ExtraMeeting initial;
  @override
  State<ExtraEditor> createState() => _ExtraEditorState();
}

class _ExtraEditorState extends State<ExtraEditor> {
  late final ExtraMeeting draft = widget.initial.copy();
  void finish() {
    final error = ScheduleData(
      semester: widget.semester,
    ).courseError(Course(name: '当前课程', extras: [draft]));
    if (error != null) {
      showError(context, FormatException(error));
    } else {
      Navigator.pop(context, draft);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('额外上课安排'),
      actions: [TextButton(onPressed: finish, child: const Text('完成'))],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SectionCard(
          title: '额外安排',
          children: [
            EditField(
              label: '标题，例如大型实验、补课、考试',
              value: draft.title,
              onChanged: (v) => draft.title = v,
              maxLength: 80,
            ),
          ],
        ),
        SectionCard(
          title: '哪一天',
          children: [
            numberChoice(
              label: '教学周',
              value: draft.week,
              min: 1,
              max: widget.semester.weekCount,
              format: (v) => '第 $v 周',
              onChanged: (v) => setState(() => draft.week = v),
            ),
            numberChoice(
              label: '星期',
              value: draft.weekday,
              min: 1,
              max: 7,
              format: (v) => SchoolClock.weekdays[v - 1],
              onChanged: (v) => setState(() => draft.weekday = v),
            ),
            Text(
              SchoolClock.fullDate(
                SchoolClock.date(draft.week, draft.weekday, widget.semester),
              ),
            ),
          ],
        ),
        SectionCard(
          title: '时间',
          footer: '全天安排显示在日期顶部，并与当天其他课程检查冲突。关闭全天可设置连续实验时段。',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('全天安排'),
              value: draft.allDay,
              onChanged: (v) => setState(() => draft.allDay = v),
            ),
            if (!draft.allDay) ...[
              MinuteButton(
                label: '开始时间',
                value: draft.startMinute,
                onChanged: (v) => setState(() => draft.startMinute = v),
              ),
              MinuteButton(
                label: '结束时间',
                value: draft.endMinute,
                onChanged: (v) => setState(() => draft.endMinute = v),
              ),
            ],
          ],
        ),
        SectionCard(
          title: '本次安排专用信息',
          children: [
            EditField(
              label: '地点（留空沿用课程地点）',
              value: draft.location,
              onChanged: (v) => draft.location = v,
              maxLength: 120,
            ),
            EditField(
              label: '指导教师（留空沿用任课教师）',
              value: draft.teacher,
              onChanged: (v) => draft.teacher = v,
              maxLength: 80,
            ),
            EditField(
              label: '备注，例如携带电脑、实验报告',
              value: draft.notes,
              onChanged: (v) => draft.notes = v,
              lines: 3,
              maxLength: 2000,
            ),
          ],
        ),
      ],
    ),
  );
}

class MinuteButton extends StatelessWidget {
  const MinuteButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(LessonPeriod.format(value)),
    onTap: () async {
      final selected = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (selected != null) onChanged(selected.hour * 60 + selected.minute);
    },
  );
}
