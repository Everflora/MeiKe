import 'package:flutter/material.dart';
import '../data/schedule_store.dart';
import '../data/team_client.dart';
import '../domain/schedule.dart';
import '../domain/team_availability.dart';
import 'discussion_helpers.dart';

class TeamAvailabilityPage extends StatefulWidget {
  const TeamAvailabilityPage({
    super.key,
    required this.client,
    required this.roundId,
    this.store,
  });
  final TeamClient client;
  final String roundId;
  final ScheduleStore? store;
  @override
  State<TeamAvailabilityPage> createState() => _TeamAvailabilityPageState();
}

class _TeamAvailabilityPageState extends State<TeamAvailabilityPage> {
  DateTime monday = SchoolClock.monday(DateTime.now());
  Set<int> slots = {};
  bool consent = false, busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  String get week {
    final wall = SchoolClock.wall(monday);
    return '${wall.year}-${wall.month.toString().padLeft(2, '0')}-${wall.day.toString().padLeft(2, '0')}';
  }

  Future<void> load() async {
    try {
      final saved = await widget.client.get('availability/${widget.roundId}');
      if (!mounted) return;
      setState(() {
        slots = (saved['slots'] as List).cast<int>().toSet();
        consent = saved['consent'] == true;
        if (saved['week'] != null) {
          final date = DateTime.parse(saved['week'] as String);
          monday = SchoolClock.instant(date.year, date.month, date.day);
        }
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.write(
        'availability/${widget.roundId}',
        consent
            ? {'consent': true, 'week': week, 'slots': slots.toList()..sort()}
            : {},
        method: consent ? 'PUT' : 'DELETE',
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('可选共同空闲时间')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '只有需要见面的任务才启用。服务器只保存你确认的半小时空闲时段，用于提供共同会议时间建议，不参与规则匹配分。不会上传课程名称或完整课表。',
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: consent,
          title: const Text('我同意分享本周抽象空闲时段'),
          subtitle: const Text('可随时撤回；关闭并保存会删除服务器上的时段。'),
          onChanged: busy ? null : (v) => setState(() => consent = v!),
        ),
        if (consent) ...[
          Row(
            children: [
              IconButton(
                tooltip: '上一周',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        monday = monday.subtract(const Duration(days: 7));
                        slots = {};
                      }),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(child: Text('$week 起的一周', textAlign: TextAlign.center)),
              IconButton(
                tooltip: '下一周',
                onPressed: busy
                    ? null
                    : () => setState(() {
                        monday = monday.add(const Duration(days: 7));
                        slots = {};
                      }),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (widget.store != null)
            OutlinedButton.icon(
              icon: const Icon(Icons.calendar_month),
              label: const Text('授权读取本地课表，生成可选空闲时段'),
              onPressed: busy
                  ? null
                  : () async {
                      final allowed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('读取本地课表'),
                          content: const Text(
                            '仅在手机上计算这周 08:00–22:00 的空闲时间。生成后可删改；点击保存才上传抽象时段。空闲不等于一定愿意参加，请核对。',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('允许并生成'),
                            ),
                          ],
                        ),
                      );
                      if (allowed != true || !mounted) return;
                      try {
                        setState(() {
                          slots = teamFreeSlots(
                            widget.store!.data,
                            monday,
                          ).toSet();
                          error = null;
                        });
                      } catch (e) {
                        setState(() => error = message(e));
                      }
                    },
            ),
          const Text('手动选择或修改愿意参加的时间。每格 30 分钟。'),
          for (var day = 0; day < 7; day++)
            ExpansionTile(
              title: Text(
                '${SchoolClock.weekdays[day]}（已选 ${slots.where((s) => s ~/ 48 == day).length} 格）',
              ),
              children: [
                Wrap(
                  spacing: 4,
                  children: [
                    for (var half = 16; half < 44; half++)
                      FilterChip(
                        label: Text(LessonPeriod.format(half * 30)),
                        selected: slots.contains(day * 48 + half),
                        onSelected: busy
                            ? null
                            : (v) => setState(() {
                                if (v) {
                                  slots.add(day * 48 + half);
                                } else {
                                  slots.remove(day * 48 + half);
                                }
                              }),
                      ),
                  ],
                ),
              ],
            ),
        ],
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(
            busy
                ? '保存中…'
                : consent
                ? '保存空闲时段'
                : '撤回授权并删除时段',
          ),
        ),
      ],
    ),
  );
}
