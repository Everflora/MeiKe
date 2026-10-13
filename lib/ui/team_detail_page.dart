import 'package:flutter/material.dart';
import '../data/schedule_store.dart';
import '../data/team_client.dart';
import '../domain/schedule.dart';
import '../domain/team_availability.dart';
import 'discussion_helpers.dart';
import 'team_availability_page.dart';
import 'discussion_profile.dart';
import 'team_questionnaire.dart';

class TeamDetailPage extends StatefulWidget {
  const TeamDetailPage({
    super.key,
    required this.client,
    required this.config,
    required this.teamId,
    this.store,
  });
  final TeamClient client;
  final Json config;
  final String teamId;
  final ScheduleStore? store;
  @override
  State<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends State<TeamDetailPage> {
  Json? team, meeting, feedback;
  List<Json> applications = [];
  String? error;
  bool busy = true, offlineConfirmed = false;
  String get path => 'detail/${widget.teamId}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final t = (await widget.client.get(path))['team'] as Json;
      final a =
          ((await widget.client.get('$path/applications'))['applications']
                  as List)
              .cast<Json>();
      Json? f, m;
      if (t['completed'] == true && t['mine'] == true) {
        f = await widget.client.get('$path/feedback');
      }
      if ((t['mustMeetOffline'] == true || t['needsMeeting'] == true) &&
          t['mine'] == true) {
        m = await widget.client.get('$path/meeting-times');
      }
      if (!mounted) return;
      setState(() {
        team = t;
        applications = a;
        feedback = f;
        meeting = m;
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String operation, [Json body = const {}]) async {
    if (!mounted || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (operation == 'apply') {
        final ready = await ensureTeamPreferences(
          context,
          widget.client,
          widget.config,
          team!['roundId'] as String,
        );
        if (!mounted) return;
        if (!ready) {
          setState(() => busy = false);
          return;
        }
      }
      await widget.client.write('$path/$operation', body);
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = message(e);
          busy = false;
        });
      }
    }
  }

  Future<bool> confirm(String title, String content) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> review(Json application, String decision) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.write('applications/${application['id']}', {
        'action': decision,
      });
      await load();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = message(e);
          busy = false;
        });
      }
    }
  }

  String optionLabel(String tag) =>
      (widget.config['questions'] as List)
              .expand((q) => q['options'] as List)
              .firstWhere((o) => o['id'] == tag)['label']
          as String;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(team?['name'] as String? ?? '团队详情'),
      actions: [
        IconButton(
          tooltip: '刷新团队',
          icon: const Icon(Icons.refresh),
          onPressed: busy ? null : load,
        ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (team != null) ...[
                Text(
                  '${team!['memberCount']}/${team!['capacity']} 人 · ${(widget.config['modes'] as List).firstWhere((m) => m['id'] == team!['collaborationMode'])['label']}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  team!['completed'] == true
                      ? '合作已结束'
                      : team!['published'] != true
                      ? '尚未发布的草稿'
                      : team!['status'] == 'FULL'
                      ? '已满员'
                      : team!['status'] == 'CLOSED'
                      ? '已关闭招募'
                      : '招募中',
                ),
                if ((team!['description'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(team!['description'] as String),
                  ),
                if (team!['mustMeetOffline'] == true)
                  const Text('此团队要求线下见面，需要主动确认。'),
                for (final key in ['requiredSkills', 'requiredRoles']) ...[
                  if ((team![key] as List).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        key == 'requiredSkills' ? '声明的技能需求' : '声明的角色需求',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  for (final need in team![key] as List)
                    Text(
                      '${optionLabel(need['tag'] as String)} · ${need['count']} 人 · 权重 ${need['weight']}',
                    ),
                ],
                const Divider(height: 32),
                Text('团队成员', style: Theme.of(context).textTheme.titleMedium),
                for (final member in (team!['members'] as List).cast<Json>())
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: UserAvatar(
                      client: widget.client.discussion,
                      userId: member['id'] as String,
                      name: member['name'] as String,
                      version: member['avatarVersion'] as String,
                    ),
                    title: Text(member['name'] as String),
                    subtitle: Text(
                      member['id'] == team!['leaderId'] ? '负责人' : '成员',
                    ),
                    trailing: member['id'] == widget.client.userId
                        ? null
                        : PopupMenuButton<String>(
                            onSelected: (v) async {
                              if (v == 'avoid' &&
                                  await confirm(
                                    '私密避开组队',
                                    '今后的推荐和加入申请会避开与这位同学组队。对方不会看到此设置；当前团队不会变动。',
                                  )) {
                                try {
                                  await widget.client.write('avoidances', {
                                    'userId': member['id'],
                                  });
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('已加入私密避开名单'),
                                      ),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => error = message(e));
                                  }
                                }
                              }
                              if (v == 'remove' &&
                                  await confirm('移除成员', '移除后该同学不能再次申请这个团队。')) {
                                await action('remove', {
                                  'userId': member['id'],
                                });
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'avoid',
                                child: Text('私密避开组队'),
                              ),
                              if (team!['manager'] == true &&
                                  team!['completed'] != true)
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('移出团队'),
                                ),
                            ],
                          ),
                  ),
                if (team!['mine'] != true &&
                    team!['status'] == 'RECRUITING') ...[
                  if (team!['mustMeetOffline'] == true)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('我确认可以满足这次任务的线下见面要求'),
                      value: offlineConfirmed,
                      onChanged: busy
                          ? null
                          : (v) => setState(() => offlineConfirmed = v!),
                    ),
                  FilledButton(
                    onPressed:
                        busy ||
                            applications.any((a) => a['status'] == 'PENDING') ||
                            (team!['mustMeetOffline'] == true &&
                                !offlineConfirmed)
                        ? null
                        : () => action('apply', {
                            'offlineConfirmed': offlineConfirmed,
                          }),
                    child: const Text('申请加入'),
                  ),
                ],
                if (applications.isNotEmpty) ...[
                  const Divider(height: 32),
                  Text(
                    team!['manager'] == true ? '加入申请' : '我的申请',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  for (final a in applications)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${a['name']} · ${applicationStatus(a['status'] as String)}',
                            ),
                            if (a['status'] == 'PENDING')
                              Wrap(
                                spacing: 8,
                                children: [
                                  if (team!['manager'] == true) ...[
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => review(a, 'accept'),
                                      child: const Text('同意加入'),
                                    ),
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => review(a, 'reject'),
                                      child: const Text('拒绝'),
                                    ),
                                  ],
                                  if (a['user_id'] == widget.client.userId)
                                    TextButton(
                                      onPressed: busy
                                          ? null
                                          : () => review(a, 'cancel'),
                                      child: const Text('取消申请'),
                                    ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
                if (team!['mine'] == true && team!['completed'] != true) ...[
                  const Divider(height: 32),
                  Wrap(
                    spacing: 8,
                    children: [
                      if (team!['manager'] == true) ...[
                        if (team!['status'] == 'CLOSED')
                          OutlinedButton(
                            onPressed: busy ? null : () => action('publish'),
                            child: const Text('发布招募'),
                          ),
                        if (team!['status'] != 'CLOSED')
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () async {
                                    if (await confirm(
                                      '关闭招募',
                                      '团队成员会保留，待审核申请会取消。',
                                    )) {
                                      await action('close');
                                    }
                                  },
                            child: const Text('关闭招募'),
                          ),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  if (await confirm(
                                    '结束本次合作',
                                    '结束后不能再更改成员。所有成员可自愿同意匿名反馈；不会公开评价个人。',
                                  )) {
                                    await action('complete');
                                  }
                                },
                          child: const Text('结束合作'),
                        ),
                      ],
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                if (await confirm(
                                  '退出团队',
                                  team!['manager'] == true
                                      ? '负责人退出会将管理权交给最早加入的其他成员；空团队会停止招募。'
                                      : '退出后释放名额。',
                                )) {
                                  await action('leave');
                                }
                              },
                        child: const Text('退出团队'),
                      ),
                    ],
                  ),
                ],
                if ((team!['mustMeetOffline'] == true ||
                        team!['needsMeeting'] == true) &&
                    team!['completed'] != true) ...[
                  const Divider(height: 32),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TeamAvailabilityPage(
                                  client: widget.client,
                                  roundId: team!['roundId'] as String,
                                  store: widget.store,
                                ),
                              ),
                            );
                            if (mounted) await load();
                          },
                    icon: const Icon(Icons.event_available),
                    label: const Text('可选空闲时间授权'),
                  ),
                  if (team!['mine'] != true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                final m = await widget.client.get(
                                  '$path/meeting-times',
                                );
                                if (mounted) setState(() => meeting = m);
                              } catch (e) {
                                if (mounted) setState(() => error = message(e));
                              }
                            },
                      child: const Text('查看共同空闲时间建议'),
                    ),
                  if (meeting != null) ...[
                    Text(meeting!['message'] as String),
                    if (meeting!['week'] != null)
                      Text('${meeting!['week']} 起的一周'),
                    for (final slot in (meeting!['slots'] as List).take(20))
                      Text(teamSlotLabel(slot as int)),
                    if ((meeting!['slots'] as List).length > 20)
                      Text(
                        '还有 ${(meeting!['slots'] as List).length - 20} 个时段，可先商议以上时间。',
                      ),
                  ],
                ],
                if (feedback != null) ...[
                  const Divider(height: 32),
                  const Text('合作反馈（自愿匿名汇总，不公开评价具体同学）'),
                  if (feedback!['consent'] != true)
                    FilledButton.tonal(
                      onPressed: busy
                          ? null
                          : () => action('feedback', {'consent': true}),
                      child: const Text('同意匿名汇总反馈'),
                    ),
                  if (feedback!['consent'] == true) ...[
                    if (feedback!['allConsented'] != true)
                      const Text('等待所有参与成员同意后，再填写反馈。'),
                    if (feedback!['allConsented'] == true)
                      FilledButton.tonal(
                        onPressed: busy ? null : fillFeedback,
                        child: Text(
                          feedback!['answers'] == null ? '填写合作反馈' : '修改我的反馈',
                        ),
                      ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => action('feedback', {'consent': false}),
                      child: const Text('撤回同意并删除我的反馈'),
                    ),
                  ],
                  if (feedback!['aggregate'] != null)
                    Text(
                      '团队匿名汇总：满意度 ${feedback!['aggregate']['satisfaction']}/5，效率 ${feedback!['aggregate']['efficiency']}/5，愿意再次合作 ${((feedback!['aggregate']['willingAgain'] as num) * 100).round()}%',
                    ),
                ],
              ],
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Future<void> fillFeedback() async {
    final previous = feedback!['answers'] as Json?;
    int satisfaction = previous?['satisfaction'] as int? ?? 3,
        efficiency = previous?['efficiency'] as int? ?? 3;
    bool again = previous?['willingAgain'] as bool? ?? true;
    final result = await showDialog<Json>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('合作反馈'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('评价本次团队合作整体体验，不评价具体成员。'),
              DropdownButtonFormField<int>(
                initialValue: satisfaction,
                decoration: const InputDecoration(labelText: '满意度'),
                items: [
                  for (var n = 1; n <= 5; n++)
                    DropdownMenuItem(value: n, child: Text('$n / 5')),
                ],
                onChanged: (n) => update(() => satisfaction = n!),
              ),
              DropdownButtonFormField<int>(
                initialValue: efficiency,
                decoration: const InputDecoration(labelText: '合作效率'),
                items: [
                  for (var n = 1; n <= 5; n++)
                    DropdownMenuItem(value: n, child: Text('$n / 5')),
                ],
                onChanged: (n) => update(() => efficiency = n!),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('愿意再次一起合作'),
                value: again,
                onChanged: (v) => update(() => again = v!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'satisfaction': satisfaction,
                'efficiency': efficiency,
                'willingAgain': again,
              }),
              child: const Text('提交'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      await action('feedback', {'consent': true, 'answers': result});
    }
  }
}

String applicationStatus(String status) => switch (status) {
  'PENDING' => '待审核',
  'ACCEPTED' => '已加入',
  'REJECTED' => '未通过',
  _ => '已取消',
};
