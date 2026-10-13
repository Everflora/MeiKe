import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'course_editor.dart';
import 'courses_page.dart';
import 'appearance.dart';
import 'theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store, this.appearance});
  final ScheduleStore store;
  final AppearanceController? appearance;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool transferring = false;
  void message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> export() async {
    setState(() => transferring = true);
    try {
      final bytes = await widget.store.exportBytes();
      final result = await FilePicker.saveFile(
        fileName: widget.store.canWrite
            ? 'SEU综合课表-备份.json'
            : 'SEU综合课表-原始数据.json',
        dialogTitle: '导出课表备份',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );
      if (result != null && mounted) message('备份已导出。');
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  Future<void> restore() async {
    setState(() => transferring = true);
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (selected == null) return;
      // Stream to a bounded buffer even when the native picker cannot report size.
      final reported = await selected.length();
      if (reported != null && reported > ScheduleCodec.maxBytes) {
        throw const FormatException('备份不能大于 2 MB。');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in selected.readAsByteStream()) {
        if (builder.length + chunk.length > ScheduleCodec.maxBytes) {
          throw const FormatException('备份不能大于 2 MB。');
        }
        builder.add(chunk);
      }
      final candidate = ScheduleCodec.decode(builder.takeBytes());
      if (!mounted) return;
      final approved = await confirm(
        context,
        '恢复备份并替换当前课表？',
        '备份「${candidate.semester.name}」包含 ${candidate.courses.length} 门课程及所有安排。当前课表将被替换，建议先导出当前备份。',
        action: '替换并恢复',
        destructive: true,
      );
      if (!approved) return;
      await widget.store.replace(candidate, recovering: true);
      if (mounted) message('已恢复 ${candidate.courses.length} 门课程。');
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => transferring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final semester = widget.store.data.semester;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const BrandHeader(
          title: '我的',
          subtitle: '把学习与生活，安排得刚刚好。',
          padding: EdgeInsets.only(bottom: 24),
        ),
        if (!widget.store.canWrite)
          SectionCard(
            title: '本地数据读取失败',
            children: [Text(widget.store.loadError ?? '请先导出原始数据，再通过有效备份恢复。')],
          ),
        SectionCard(
          title: '学期与作息',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('课程管理'),
              subtitle: Text(
                '${widget.store.data.courses.length} 门课程 · 每周与额外安排',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showCourses(context, widget.store),
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('学期 / 节次设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => SemesterEditor(store: widget.store),
                ),
              ),
            ),
            const Divider(),
            _setting('当前学期', semester.name),
            _setting('教学周数', '${semester.weekCount} 周'),
            _setting('每日节次', '${semester.periods.length} 节'),
            _setting('时间基准', '中国标准时间'),
          ],
        ),
        if (widget.appearance != null)
          SectionCard(
            title: '外观',
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('主题'),
                trailing: PopupMenuButton<MeikeTheme>(
                  tooltip: '选择主题',
                  initialValue: widget.appearance!.theme,
                  onSelected: (theme) async {
                    try {
                      await widget.appearance!.setTheme(theme);
                    } catch (e) {
                      if (context.mounted) await showError(context, e);
                    }
                  },
                  itemBuilder: (_) => [
                    for (final theme in MeikeTheme.values)
                      PopupMenuItem(value: theme, child: Text(theme.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      widget.appearance!.theme.label,
                      style: TextStyle(color: context.meike.green),
                    ),
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.brightness_6_outlined),
                title: const Text('显示模式'),
                trailing: PopupMenuButton<ThemeMode>(
                  tooltip: '选择显示模式',
                  initialValue: widget.appearance!.mode,
                  onSelected: (mode) async {
                    try {
                      await widget.appearance!.setMode(mode);
                    } catch (e) {
                      if (context.mounted) await showError(context, e);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: ThemeMode.system, child: Text('跟随系统')),
                    PopupMenuItem(value: ThemeMode.light, child: Text('浅色')),
                    PopupMenuItem(value: ThemeMode.dark, child: Text('深色')),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Text(
                      widget.appearance!.label,
                      style: TextStyle(color: context.meike.green),
                    ),
                  ),
                ),
              ),
            ],
          ),
        SectionCard(
          title: '数据备份',
          footer:
              '数据仅保存在本机，不需要账号。删除 App 会删除本机数据，请定期导出备份。可导入原 SwiftUI 版的 JSON 备份。',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.ios_share),
              title: const Text('导出课表备份'),
              onTap: transferring ? null : export,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('从备份恢复'),
              onTap: transferring ? null : restore,
            ),
            if (transferring) const LinearProgressIndicator(),
          ],
        ),
        const SectionCard(
          title: '使用说明',
          children: [
            Text('一门课程可以包含多条每周时间，新增时可一次选择多天。'),
            SizedBox(height: 10),
            Text('额外安排支持指定周、全天实验和独立地点。'),
            SizedBox(height: 10),
            Text('课表保留课间与午休，今天页显示当前节次下课倒计时。'),
            SizedBox(height: 10),
            Text('示例课程仅供体验，不代表真实课程信息。'),
          ],
        ),
        Text(
          '梅课 1.5.2 · SEU 校园课表',
          style: Theme.of(context).textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _setting(String title, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Text(title),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

class SemesterEditor extends StatefulWidget {
  const SemesterEditor({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<SemesterEditor> createState() => _SemesterEditorState();
}

class _SemesterEditorState extends State<SemesterEditor> {
  late final Semester draft = widget.store.data.semester.copy();
  bool saving = false;
  Future<void> save() async {
    final candidate = widget.store.data.copy()..semester = draft.copy();
    candidate.semester.startDate = SchoolClock.monday(draft.startDate);
    setState(() => saving = true);
    try {
      await widget.store.replace(candidate);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickDate() async {
    final w = SchoolClock.wall(draft.startDate);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(w.year, w.month, w.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked != null && mounted) {
      setState(
        () => draft.startDate = SchoolClock.monday(
          SchoolClock.instant(picked.year, picked.month, picked.day),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('学期与作息'),
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
          title: '学期',
          footer: '日期自动对齐所在周的周一。调整学期起点会移动所有课程和额外安排的日历日期。',
          children: [
            EditField(
              label: '学期名称',
              value: draft.name,
              onChanged: (v) => draft.name = v,
              maxLength: 80,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('第 1 周的周一'),
              subtitle: Text(SchoolClock.fullDate(draft.startDate)),
              trailing: const Icon(Icons.calendar_month),
              onTap: pickDate,
            ),
            numberChoice(
              label: '教学周数',
              value: draft.weekCount,
              min: 1,
              max: 40,
              format: (v) => '$v 周',
              onChanged: (v) => setState(() => draft.weekCount = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('按 SEU 校历显示课程'),
              subtitle: const Text('匹配校历学期时隐藏常规停课日、调整补课；手动额外安排保留。'),
              value: draft.useSchoolCalendar,
              onChanged: (v) => setState(() => draft.useSchoolCalendar = v),
            ),
          ],
        ),
        SectionCard(
          title: '每天的上课时间',
          footer: '课间、午休和晚饭时间由相邻节次自动计算。减少周数或节次前，请先调整超出范围的课程。',
          children: [
            for (final p in draft.periods)
              Column(
                key: ValueKey(p.id),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '第 ${p.id} 节',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  MinuteButton(
                    label: '上课',
                    value: p.startMinute,
                    onChanged: (v) => setState(() => p.startMinute = v),
                  ),
                  MinuteButton(
                    label: '下课',
                    value: p.endMinute,
                    onChanged: (v) => setState(() => p.endMinute = v),
                  ),
                  const Divider(),
                ],
              ),
            TextButton.icon(
              onPressed: draft.periods.length >= 16
                  ? null
                  : () {
                      final last = draft.periods.last.endMinute;
                      if (last + 50 >= 1440) {
                        showError(
                          context,
                          const FormatException('当天没有足够时间添加节次。'),
                        );
                        return;
                      }
                      setState(
                        () => draft.periods.add(
                          LessonPeriod(
                            id: draft.periods.length + 1,
                            startMinute: last + 5,
                            endMinute: last + 50,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.add),
              label: const Text('添加节次'),
            ),
            TextButton(
              onPressed: draft.periods.length <= 1
                  ? null
                  : () => setState(() => draft.periods.removeLast()),
              child: const Text('移除最后一节'),
            ),
            TextButton(
              onPressed: () =>
                  setState(() => draft.periods = LessonPeriod.defaults()),
              child: const Text('恢复学校默认作息（13 节）'),
            ),
          ],
        ),
      ],
    ),
  );
}
