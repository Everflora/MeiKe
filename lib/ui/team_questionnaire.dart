import 'package:flutter/material.dart';
import '../data/team_client.dart';
import '../domain/schedule.dart';
import 'discussion_helpers.dart';

class TeamQuestion extends StatelessWidget {
  const TeamQuestion({
    super.key,
    required this.question,
    required this.answer,
    required this.onChanged,
  });
  final Json question;
  final dynamic answer;
  final ValueChanged<dynamic> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question['title'] as String,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (question['multiple'] == true)
          Text('选择 ${question['min']}–${question['max']} 项'),
        const SizedBox(height: 8),
        for (final option in (question['options'] as List).cast<Json>())
          question['multiple'] == true
              ? CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option['label'] as String),
                  value: (answer as List? ?? []).contains(option['id']),
                  onChanged: (_) => onChanged(
                    toggleTeamAnswer(
                      question,
                      (answer as List? ?? []).cast<String>(),
                      option['id'] as String,
                    ),
                  ),
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(option['label'] as String),
                  leading: Icon(
                    answer == option['id']
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: answer == option['id']
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  onTap: () => onChanged(option['id']),
                ),
      ],
    ),
  );
}

class TeamQuestionnairePage extends StatefulWidget {
  const TeamQuestionnairePage({
    super.key,
    required this.client,
    required this.config,
    required this.roundId,
    this.profileOnly = false,
    this.overridesOnly = false,
  });
  final TeamClient client;
  final Json config;
  final String roundId;
  final bool profileOnly, overridesOnly;
  @override
  State<TeamQuestionnairePage> createState() => _TeamQuestionnairePageState();
}

class _TeamQuestionnairePageState extends State<TeamQuestionnairePage> {
  final scroll = ScrollController();
  List<Json> questions = [];
  Json answers = {}, tags = {}, overrides = {};
  bool loading = true, busy = false, offline = false, useOverrides = false;
  int page = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final profile = await widget.client.get('profile');
      final preference = await widget.client.get(
        'preferences/${widget.roundId}',
      );
      final all = (widget.config['questions'] as List).cast<Json>();
      final p = profile['answers'] as Json;
      final hasProfile = all
          .where((q) => q['scope'] == 'profile')
          .every((q) => teamAnswerError(q, p[q['id']]) == null);
      if (!mounted) return;
      setState(() {
        answers = {...p, ...preference['answers'] as Json};
        tags = {...profile['tags'] as Json};
        overrides = {...preference['overrides'] as Json};
        useOverrides = overrides.isNotEmpty;
        offline = preference['canMeetOffline'] == true;
        questions = widget.overridesOnly
            ? all.where((q) => ['q3', 'q4'].contains(q['id'])).toList()
            : all
                  .where(
                    (q) => widget.profileOnly
                        ? q['scope'] == 'profile'
                        : !hasProfile || q['scope'] == 'round',
                  )
                  .toList();
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = message(e);
        });
      }
    }
  }

  int get pages => (questions.length / 2).ceil();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> next() async {
    for (final q in questions.skip(page * 2).take(2)) {
      if (widget.overridesOnly && !useOverrides) break;
      final problem = teamAnswerError(
        q,
        widget.overridesOnly
            ? (overrides[q['id']] ?? answers[q['id']])
            : answers[q['id']],
      );
      if (problem != null) {
        setState(() => error = problem);
        return;
      }
    }
    if (page < pages - 1) {
      setState(() {
        page++;
        error = null;
      });
      if (scroll.hasClients) scroll.jumpTo(0);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final all = (widget.config['questions'] as List).cast<Json>();
      if (!widget.overridesOnly &&
          questions.any((q) => q['scope'] == 'profile')) {
        await widget.client.write('profile', {
          'answers': {
            for (final q in all.where((q) => q['scope'] == 'profile'))
              q['id'] as String: answers[q['id']],
          },
          'tags': tags,
          'questionnaireVersion': widget.config['questionnaireVersion'],
        }, method: 'PUT');
      }
      if (!widget.profileOnly) {
        if (widget.overridesOnly && useOverrides) {
          for (final q in questions) {
            overrides[q['id'] as String] ??= answers[q['id']];
          }
        }
        await widget.client.write('preferences/${widget.roundId}', {
          'answers': {
            for (final q in all.where((q) => q['scope'] == 'round'))
              q['id'] as String: answers[q['id']],
          },
          'overrides': useOverrides ? overrides : <String, dynamic>{},
          'canMeetOffline': offline,
          'questionnaireVersion': widget.config['questionnaireVersion'],
        }, method: 'PUT');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.overridesOnly
            ? '本次任务的技能与角色'
            : widget.profileOnly
            ? '编辑个人画像'
            : '本次组队偏好',
      ),
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : questions.isEmpty
        ? Center(child: Text(error ?? '暂时无法读取问卷。'))
        : Column(
            children: [
              LinearProgressIndicator(value: (page + 1) / pages),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text('第 ${page + 1} / $pages 页'),
                    const Text('个人画像跨课程复用；任务目标、投入和同步频率按课程分别保存。答案仅自己可见。'),
                    if (widget.overridesOnly)
                      SwitchListTile(
                        title: const Text('仅本次任务使用不同技能与角色'),
                        subtitle: const Text('关闭后沿用个人画像，不修改其他课程。'),
                        value: useOverrides,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => useOverrides = v),
                      ),
                    const SizedBox(height: 16),
                    if (!widget.overridesOnly || useOverrides)
                      for (final q in questions.skip(page * 2).take(2))
                        TeamQuestion(
                          question: q,
                          answer: widget.overridesOnly
                              ? overrides[q['id']] ?? answers[q['id']]
                              : answers[q['id']],
                          onChanged: (v) => setState(() {
                            (widget.overridesOnly ? overrides : answers)[q['id']
                                    as String] =
                                v;
                            error = null;
                          }),
                        ),
                    if (page == pages - 1 &&
                        !widget.profileOnly &&
                        !widget.overridesOnly)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('本次任务可以参加线下见面'),
                        subtitle: const Text('不勾选也可正常组队；线下要求团队会单独确认。'),
                        value: offline,
                        onChanged: busy
                            ? null
                            : (v) => setState(() => offline = v!),
                      ),
                    if (page == pages - 1 &&
                        questions.any((q) => q['scope'] == 'profile') &&
                        !widget.overridesOnly) ...[
                      const Text('以下标签可跳过，仅自己可见，不参与匹配。'),
                      for (final kind in ['mbti', 'zodiac'])
                        DropdownButtonFormField<String>(
                          initialValue: tags[kind] as String?,
                          decoration: InputDecoration(
                            labelText: kind == 'mbti' ? 'MBTI（自愿）' : '星座（自愿）',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('跳过'),
                            ),
                            for (final value
                                in widget.config['optionalTags'][kind] as List)
                              DropdownMenuItem(
                                value: value as String,
                                child: Text(value),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (value) => setState(() {
                                  if (value == null || value.isEmpty) {
                                    tags.remove(kind);
                                  } else {
                                    tags[kind] = value;
                                  }
                                }),
                        ),
                    ],
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      if (page > 0)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () {
                                  setState(() {
                                    page--;
                                    error = null;
                                  });
                                  if (scroll.hasClients) scroll.jumpTo(0);
                                },
                          child: const Text('上一步'),
                        ),
                      const Spacer(),
                      FilledButton(
                        onPressed: busy ? null : next,
                        child: Text(
                          busy
                              ? '保存中…'
                              : page == pages - 1
                              ? '保存偏好'
                              : '下一步',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}
