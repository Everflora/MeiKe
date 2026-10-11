import 'package:flutter/material.dart';
import '../data/team_client.dart';
import '../domain/schedule.dart';
import 'discussion_helpers.dart';

class TeamCreatePage extends StatefulWidget {
  const TeamCreatePage({
    super.key,
    required this.client,
    required this.config,
    required this.roundId,
  });
  final TeamClient client;
  final Json config;
  final String roundId;
  @override
  State<TeamCreatePage> createState() => _TeamCreatePageState();
}

class _TeamCreatePageState extends State<TeamCreatePage> {
  final name = TextEditingController(), description = TextEditingController();
  late int capacity;
  String mode = 'LIGHT';
  bool offline = false, meeting = false, publish = true, busy = false;
  String? error;
  final Map<String, int> counts = {};
  final Map<String, double> weights = {};
  @override
  void initState() {
    super.initState();
    capacity = widget.config['limits']['defaultCapacity'] as int;
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = '请输入团队名称。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      List<Json> requirements(String questionId) {
        final q = (widget.config['questions'] as List).cast<Json>().firstWhere(
          (q) => q['id'] == questionId,
        );
        return [
          for (final option in q['options'] as List)
            if ((counts[option['id']] ?? 0) > 0)
              {
                'tag': option['id'],
                'count': counts[option['id']],
                'weight': weights[option['id']] ?? 1,
              },
        ];
      }

      final result = await widget.client.write('list', {
        'roundId': widget.roundId,
        'name': name.text.trim(),
        'description': description.text.trim(),
        'capacity': capacity,
        'collaborationMode': mode,
        'mustMeetOffline': offline,
        'needsMeeting': meeting,
        'requiredSkills': requirements('q3'),
        'requiredRoles': requirements('q4'),
        'publish': publish,
      });
      if (mounted) Navigator.pop(context, result['team']);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget needs(String key, String title) {
    final q = (widget.config['questions'] as List).cast<Json>().firstWhere(
      (q) => q['id'] == key,
    );
    final excluded = key == 'q3'
        ? widget.config['emptySkills']
        : widget.config['flexibleRole']['answer'];
    return ExpansionTile(
      title: Text(title),
      subtitle: const Text('可选；未声明的需求不参与技能与角色匹配'),
      children: [
        for (final option in (q['options'] as List).cast<Json>().where(
          (o) => o['id'] != excluded,
        ))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(option['label'] as String),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ValueKey('${option['id']}:$capacity'),
                        initialValue: counts[option['id']] ?? 0,
                        decoration: const InputDecoration(labelText: '需要人数'),
                        items: [
                          for (var n = 0; n <= capacity; n++)
                            DropdownMenuItem(
                              value: n,
                              child: Text(n == 0 ? '无要求' : '$n 人'),
                            ),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(
                                () => counts[option['id'] as String] = v!,
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<double>(
                        initialValue: weights[option['id']] ?? 1,
                        decoration: const InputDecoration(labelText: '需求权重'),
                        items: [
                          for (final n in [0.5, 1.0, 2.0])
                            DropdownMenuItem(value: n, child: Text('$n')),
                        ],
                        onChanged: busy
                            ? null
                            : (v) => setState(
                                () => weights[option['id'] as String] = v!,
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('创建课程团队')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        TextField(
          controller: name,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '团队名称'),
        ),
        TextField(
          controller: description,
          maxLength: 1000,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: '任务说明（可选）'),
        ),
        DropdownButtonFormField<int>(
          initialValue: capacity,
          decoration: const InputDecoration(labelText: '总人数（含创建者）'),
          items: [
            for (
              var n = 2;
              n <= (widget.config['limits']['maxCapacity'] as int);
              n++
            )
              DropdownMenuItem(value: n, child: Text('$n 人')),
          ],
          onChanged: busy
              ? null
              : (v) => setState(() {
                  capacity = v!;
                  counts.updateAll((_, n) => n > capacity ? capacity : n);
                }),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: mode,
          decoration: const InputDecoration(labelText: '合作程度'),
          items: [
            for (final m in widget.config['modes'] as List)
              DropdownMenuItem(
                value: m['id'] as String,
                child: Text(m['label']),
              ),
          ],
          onChanged: busy ? null : (v) => setState(() => mode = v!),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('必须线下见面'),
          value: offline,
          onChanged: busy ? null : (v) => setState(() => offline = v!),
        ),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('任务需要安排共同会议（可选）'),
          value: meeting,
          onChanged: busy ? null : (v) => setState(() => meeting = v!),
        ),
        needs('q3', '技能需求'),
        needs('q4', '角色需求'),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('立即发布招募'),
          subtitle: const Text('关闭可保存草稿；发布前需要完成问卷。'),
          value: publish,
          onChanged: busy ? null : (v) => setState(() => publish = v),
        ),
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
                : publish
                ? '发布招募'
                : '保存草稿',
          ),
        ),
      ],
    ),
  );
}
