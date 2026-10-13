import 'dart:io';

import 'package:flutter/material.dart';

import '../data/discussion_client.dart';
import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'theme.dart';
import 'nai_family.dart';
import 'chat_page.dart';
import 'discussion_profile.dart';
import 'discussion_helpers.dart';

class DiscussionPage extends StatefulWidget {
  const DiscussionPage({super.key, required this.store, this.client});
  final ScheduleStore store;

  /// An injected client is owned by its caller.
  final DiscussionClient? client;
  @override
  State<DiscussionPage> createState() => _DiscussionPageState();
}

class _DiscussionPageState extends State<DiscussionPage> {
  late final DiscussionClient client;
  bool ready = false, busy = false;
  List<Json> terms = [];
  String? term, error;

  @override
  void initState() {
    super.initState();
    client =
        widget.client ??
        DiscussionClient(
          sessionFile: File(
            '${widget.store.file.parent.path}/discussion-session.json',
          ),
        );
    load();
  }

  Future<void> load() async {
    try {
      await client.loadSession();
      if (client.signedIn) await client.refreshProfile();
    } catch (_) {
      error = '无法读取讨论身份，请重新设置昵称。';
    }
    if (mounted) setState(() => ready = true);
  }

  Future<void> connect() async {
    if (busy) return;
    if (!client.signedIn) {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => DiscussionProfilePage(client: client, creating: true),
        ),
      );
      if (saved != true || !mounted) return;
      setState(() {
        busy = true;
        error = null;
      });
      try {
        await client.refreshProfile();
      } catch (e) {
        if (mounted) {
          setState(() {
            error = message(e);
            busy = false;
          });
        }
        return;
      }
    } else {
      setState(() {
        busy = true;
        error = null;
      });
    }
    try {
      final available = await client.terms();
      if (!mounted) return;
      final imported = widget.store.data.courses
          .map((c) => c.schoolClass?.termCode)
          .whereType<String>()
          .toSet();
      final matching = available.where(
        (t) =>
            imported.contains(t['code']) ||
            t['name'] == widget.store.data.semester.name,
      );
      setState(() {
        terms = available;
        term = matching.isNotEmpty
            ? matching.first['code'] as String
            : available.length == 1
            ? available.first['code'] as String
            : null;
      });
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> enter(Course course) async {
    if (busy || term == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rooms = await client.match(course, term!);
      if (!mounted) return;
      if (rooms.isEmpty) {
        await showError(
          context,
          const FormatException('未找到对应讨论室。请核对学期、课程名称、教师、周次和节次是否与学校课表一致。'),
        );
        return;
      }
      DiscussionRoom? room = rooms.length == 1
          ? rooms.first
          : await showDialog<DiscussionRoom>(
              context: context,
              builder: (ctx) => SimpleDialog(
                title: const Text('请选择上课班级'),
                children: [
                  for (final candidate in rooms)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(ctx, candidate),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(candidate.classes),
                          const SizedBox(height: 4),
                          Text(candidate.schedule),
                          const Divider(),
                        ],
                      ),
                    ),
                ],
              ),
            );
      if (room == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ChatPage(client: client, room: room, store: widget.store),
        ),
      );
    } catch (e) {
      if (mounted) await showError(context, e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    if (widget.client == null) client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final courses = widget.store.data.courses;
    final termBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: context.meike.green, width: 1.2),
    );
    return Column(
      children: [
        BrandHeader(
          title: '课程讨论',
          subtitle: '同一间教室，也在这里相遇。',
          trailing: client.signedIn
              ? IconButton(
                  tooltip: '设置头像和昵称',
                  onPressed: () async {
                    await Navigator.of(context).push<bool>(
                      MaterialPageRoute(
                        builder: (_) => DiscussionProfilePage(client: client),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                  icon: UserAvatar(
                    client: client,
                    userId: client.userId,
                    name: client.nickname,
                    version: client.avatarVersion,
                    radius: 16,
                  ),
                )
              : null,
        ),
        if (context.naiFamily && client.signedIn && terms.isNotEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: NaiFamilyBanner(height: 108),
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        if (!client.signedIn || terms.isEmpty)
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: context.meike.soft,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: context.naiFamily
                            ? const NaiCharacter(NaiAnimal.mouse, size: 72)
                            : const PlumMark(size: 52),
                      ),
                      const SizedBox(height: 16),
                      const Text('和同一个教学班的同学交流'),
                      const SizedBox(height: 8),
                      const Text(
                        '设置昵称后，选择自己的课程进入讨论室。',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: ready && !busy ? connect : null,
                        child: Text(client.signedIn ? '连接讨论室' : '设置头像和昵称'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: term,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '学期',
                border: termBorder,
                enabledBorder: termBorder,
                focusedBorder: termBorder,
                disabledBorder: termBorder,
              ),
              items: [
                for (final item in terms)
                  DropdownMenuItem(
                    value: item['code'] as String,
                    child: Text(
                      item['name'] as String,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: busy ? null : (value) => setState(() => term = value),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('按课程名称、教师、上课时间查找对应讨论室。'),
          ),
          Expanded(
            child: courses.isEmpty
                ? const Center(child: Text('先导入或添加课程，再进入讨论室。'))
                : ListView.builder(
                    itemCount: courses.length,
                    itemBuilder: (context, index) {
                      final course = courses[index];
                      return Card(
                        margin: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          leading: Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: course.color.surface(context),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: context.naiFamily
                                ? NaiCharacter(
                                    NaiAnimal.values[index % 5],
                                    size: 44,
                                  )
                                : Icon(
                                    Icons.forum_outlined,
                                    color: course.color.foreground(context),
                                  ),
                          ),
                          title: Text(course.name),
                          subtitle: Text(
                            '${course.teacher.isEmpty ? '未填写教师' : course.teacher}\n${course.meetings.map((m) => '${m.summary} · ${m.recurrence}').join('\n')}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          isThreeLine: false,
                          onTap: !busy && term != null
                              ? () => enter(course)
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }
}
