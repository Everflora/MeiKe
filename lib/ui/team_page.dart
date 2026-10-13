import 'package:flutter/material.dart';
import '../data/discussion_client.dart';
import '../data/schedule_store.dart';
import '../data/team_client.dart';
import '../domain/schedule.dart';
import 'discussion_helpers.dart';
import 'team_create_page.dart';
import 'team_detail_page.dart';
import 'team_questionnaire.dart';
import 'team_contacts_page.dart';

class TeamPage extends StatefulWidget {
  const TeamPage({
    super.key,
    required this.client,
    required this.room,
    this.store,
  });
  final DiscussionClient client;
  final DiscussionRoom room;
  final ScheduleStore? store;
  @override
  State<TeamPage> createState() => _TeamPageState();
}

class _TeamPageState extends State<TeamPage> {
  late final TeamClient client = TeamClient(widget.client);
  Json? config;
  List<Json> teams = [];
  String? roundId, error, mode, skill;
  bool consent = false,
      checkedConsent = false,
      checkedClass = false,
      busy = false,
      myTeams = false;
  int? next;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
      teams = [];
      next = null;
    });
    try {
      config ??= (await client.get('config'))['config'] as Json;
      try {
        roundId =
            (await client.write('default-round', {
                  'offeringId': widget.room.id,
                }))['round']['id']
                as String;
        consent = true;
      } on FormatException catch (e) {
        if (e.message.contains('确认所属教学班')) {
          consent = false;
        } else {
          rethrow;
        }
      }
      if (consent) {
        if (roundId != null) {
          final result = await client.get('list', {
            'roundId': roundId!,
            'view': myTeams ? 'mine' : 'recruiting',
            if (!myTeams) 'mode': ?mode,
            if (!myTeams) 'skill': ?skill,
          });
          teams = (result['teams'] as List).cast<Json>();
          next = result['next'] as int?;
        } else {
          teams = [];
          next = null;
        }
      }
    } catch (e) {
      error = message(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> agree() async {
    setState(() => busy = true);
    try {
      await client.write('consent', {
        'offeringId': widget.room.id,
        'consent': checkedConsent,
        'confirmMembership': checkedClass,
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

  Future<void> questionnaire({
    bool profile = false,
    bool overrides = false,
  }) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamQuestionnairePage(
          client: client,
          config: config!,
          roundId: roundId!,
          profileOnly: profile,
          overridesOnly: overrides,
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> openTeam(Json team) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TeamDetailPage(
          client: client,
          config: config!,
          teamId: team['id'] as String,
          store: widget.store,
        ),
      ),
    );
    if (mounted) await load();
  }

  Future<void> editContacts() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TeamContactsPage(client: client)),
    );
    if (mounted) await load();
  }

  Future<void> more() async {
    if (next == null || busy) return;
    setState(() => busy = true);
    try {
      final result = await client.get('list', {
        'roundId': roundId!,
        'view': myTeams ? 'mine' : 'recruiting',
        'offset': '$next',
        if (!myTeams) 'mode': ?mode,
        if (!myTeams) 'skill': ?skill,
      });
      if (!mounted) return;
      final newTeams = (result['teams'] as List).cast<Json>();
      teams = {
        for (final t in [...teams, ...newTeams]) t['id']: t,
      }.values.toList();
      next = result['next'] as int?;
    } catch (e) {
      error = message(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('课程组队'),
      actions: [
        IconButton(
          tooltip: '组队联系方式',
          icon: const Icon(Icons.contact_mail_outlined),
          onPressed: busy ? null : editContacts,
        ),
        IconButton(
          tooltip: '刷新推荐',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
        if (consent && roundId != null)
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'profile') await questionnaire(profile: true);
              if (v == 'override') await questionnaire(overrides: true);
              if (v == 'avoid') await manageAvoidances();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('编辑个人画像')),
              PopupMenuItem(value: 'override', child: Text('本次技能与角色')),
              PopupMenuItem(value: 'avoid', child: Text('私密避开名单')),
            ],
          ),
      ],
    ),
    body: Column(
      children: [
        if (busy) const LinearProgressIndicator(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.room.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('${widget.room.teacher} · ${widget.room.classes}'),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('正在组队'),
                      icon: Icon(Icons.group_add_outlined),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('我的队伍'),
                      icon: Icon(Icons.groups_outlined),
                    ),
                  ],
                  selected: {myTeams},
                  onSelectionChanged: busy
                      ? null
                      : (selected) {
                          setState(() => myTeams = selected.single);
                          if (consent) load();
                        },
                ),
                const SizedBox(height: 16),
                if (config != null && !consent) ...[
                  const Text(
                    '首次使用请确认教学班。确认后即可查看队伍，问卷可稍后填写，用于计算匹配度；原始答案仅自己可见。当前账户未验证学籍。',
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('我确认属于这个教学班'),
                    value: checkedClass,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => checkedClass = v!),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('我同意主动参与组队和展示组队身份'),
                    value: checkedConsent,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => checkedConsent = v!),
                  ),
                  FilledButton(
                    onPressed: busy || !checkedClass || !checkedConsent
                        ? null
                        : agree,
                    child: const Text('开始课程组队'),
                  ),
                ],
                if (consent && config != null) ...[
                  if (roundId != null) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: busy ? null : questionnaire,
                          icon: const Icon(Icons.edit_note),
                          label: const Text('填写偏好，查看匹配度'),
                        ),
                        if (myTeams)
                          OutlinedButton.icon(
                            onPressed: busy ? null : editContacts,
                            icon: const Icon(Icons.contact_mail_outlined),
                            label: const Text('联系方式（选填）'),
                          ),
                        if (myTeams)
                          FilledButton.icon(
                            onPressed: busy
                                ? null
                                : () async {
                                    setState(() => busy = true);
                                    try {
                                      final ready = await ensureTeamPreferences(
                                        context,
                                        client,
                                        config!,
                                        roundId!,
                                      );
                                      if (!context.mounted || !ready) return;
                                      final created =
                                          await Navigator.push<Json>(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TeamCreatePage(
                                                client: client,
                                                config: config!,
                                                roundId: roundId!,
                                              ),
                                            ),
                                          );
                                      if (!mounted) return;
                                      if (created != null) {
                                        await openTeam(created);
                                      } else {
                                        await load();
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        setState(() => error = message(e));
                                      }
                                    } finally {
                                      if (mounted) setState(() => busy = false);
                                    }
                                  },
                            icon: const Icon(Icons.group_add),
                            label: const Text('创建团队'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (!myTeams)
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('筛选队伍'),
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: mode ?? '',
                            decoration: const InputDecoration(
                              labelText: '合作程度筛选',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('全部合作程度'),
                              ),
                              for (final m in config!['modes'] as List)
                                DropdownMenuItem(
                                  value: m['id'] as String,
                                  child: Text(m['label']),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    mode = v!.isEmpty ? null : v;
                                    load();
                                  },
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            initialValue: skill ?? '',
                            decoration: const InputDecoration(
                              labelText: '团队声明的技能需求',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: '',
                                child: Text('全部技能需求'),
                              ),
                              for (final o
                                  in (config!['questions'] as List).firstWhere(
                                        (q) => q['id'] == 'q3',
                                      )['options']
                                      as List)
                                if (o['id'] != config!['emptySkills'])
                                  DropdownMenuItem(
                                    value: o['id'] as String,
                                    child: Text(o['label']),
                                  ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) {
                                    skill = v!.isEmpty ? null : v;
                                    load();
                                  },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    const Text('匹配度根据组队偏好计算，帮助你找到合适的队友。'),
                    if (!busy && teams.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          myTeams
                              ? '你还没有加入队伍。去“正在组队”找队友，或创建自己的队伍。'
                              : '暂时没有正在招募的队伍，可以创建队伍，邀请同班同学加入。',
                        ),
                      ),
                    if (!myTeams && teams.isEmpty && !busy)
                      TextButton.icon(
                        onPressed: () {
                          setState(() => myTeams = true);
                          load();
                        },
                        icon: const Icon(Icons.group_add),
                        label: const Text('去创建我的队伍'),
                      ),
                    for (final t in teams)
                      Card(
                        child: InkWell(
                          onTap: () => openTeam(t),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        t['name'] as String,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium,
                                      ),
                                    ),
                                    Text(
                                      '${t['memberCount']}/${t['capacity']} 人',
                                    ),
                                  ],
                                ),
                                Text(
                                  '${modeLabel(config!, t['collaborationMode'])} · ${t['completed'] == true
                                      ? '合作已结束'
                                      : t['published'] != true
                                      ? '草稿'
                                      : t['status'] == 'FULL'
                                      ? '已满员'
                                      : t['status'] == 'CLOSED'
                                      ? '已关闭招募'
                                      : '招募中'}${t['mine'] == true ? ' · 我的团队' : ''}',
                                ),
                                if (t['mustMeetOffline'] == true)
                                  const Text('要求线下见面'),
                                if (t['match'] != null) ...[
                                  if (t['match']['displayScore'] == true)
                                    Text(
                                      '匹配度 ${(t['match']['score'] as num).toStringAsFixed(0)}%',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  if (t['match']['displayScore'] != true)
                                    const Text('填写偏好后查看匹配度'),
                                  for (final reason
                                      in t['match']['reasons'] as List)
                                    Text(reason),
                                  for (final caution
                                      in t['match']['cautions'] as List)
                                    Text(caution),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (next != null)
                      TextButton(
                        onPressed: busy ? null : more,
                        child: const Text('加载更多'),
                      ),
                  ],
                ],
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  Future<void> manageAvoidances() async {
    try {
      final users = ((await client.get('avoidances'))['users'] as List)
          .cast<Json>();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('私密避开名单'),
          content: SizedBox(
            width: 320,
            child: users.isEmpty
                ? const Text('名单为空。可在团队成员详情中私密避开某位同学。对方不会看到此设置。')
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in users)
                        ListTile(
                          title: Text(u['name'] as String),
                          trailing: IconButton(
                            tooltip: '取消避开',
                            icon: const Icon(Icons.close),
                            onPressed: () async {
                              try {
                                await client.write('avoidances', {
                                  'userId': u['id'],
                                }, method: 'DELETE');
                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) await load();
                              } catch (e) {
                                if (mounted) setState(() => error = message(e));
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    }
  }
}

String modeLabel(Json config, dynamic id) =>
    (config['modes'] as List).firstWhere((m) => m['id'] == id)['label']
        as String;
