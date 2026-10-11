import 'dart:async';
import 'package:flutter/material.dart';
import '../data/discussion_client.dart';
import '../domain/schedule.dart';
import 'discussion_helpers.dart';
import 'discussion_profile.dart';
import 'theme.dart';
import '../data/schedule_store.dart';
import 'team_page.dart';

List<Json> mergeChatMessages(List<Json> current, List<Json> updates) {
  final merged = {for (final item in current) item['id'] as int: item};
  for (final item in updates) {
    merged[item['id'] as int] = item;
  }
  return merged.values.toList()
    ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));
}

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.client,
    required this.room,
    this.store,
  });
  final DiscussionClient client;
  final DiscussionRoom room;
  final ScheduleStore? store;
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final input = TextEditingController(), scroll = ScrollController();
  List<Json> messages = [];
  int cursor = 0, unread = 0;
  int? before;
  bool loading = true, sending = false, historyBusy = false;
  bool active = true, polling = false, connected = false;
  String? error, draftId, draftBody;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
  }

  Future<void> load() async {
    try {
      final result = await widget.client.messages(widget.room.id);
      if (!mounted) return;
      setState(() {
        messages = (result['messages'] as List).cast<Json>();
        cursor = result['cursor'] as int;
        before = result['before'] as int?;
        loading = false;
        connected = true;
        error = null;
      });
      poll();
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          error = message(e);
        });
      }
    }
  }

  Future<void> poll() async {
    if (polling || !active || !mounted) return;
    polling = true;
    try {
      while (mounted && active) {
        try {
          final result = await widget.client.messages(
            widget.room.id,
            after: cursor,
            wait: true,
          );
          if (!mounted) break;
          final changes = (result['messages'] as List).cast<Json>();
          final atBottom = !scroll.hasClients || scroll.offset < 100;
          final incoming = changes
              .where(
                (m) =>
                    m['mine'] != true &&
                    !messages.any((old) => old['id'] == m['id']),
              )
              .length;
          setState(() {
            if (!connected) error = null;
            messages = mergeChatMessages(messages, changes);
            cursor = result['cursor'] as int;
            connected = true;
            if (!atBottom) unread += incoming;
          });
          if (atBottom && changes.isNotEmpty) toBottom();
        } catch (e) {
          if (!mounted) break;
          setState(() {
            connected = false;
            error = message(e);
          });
          if (!widget.client.signedIn) break;
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    } finally {
      polling = false;
    }
  }

  void toBottom() {
    if (mounted) setState(() => unread = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && scroll.hasClients) {
        scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> history() async {
    if (historyBusy || before == null) return;
    setState(() => historyBusy = true);
    try {
      final result = await widget.client.messages(
        widget.room.id,
        before: before,
      );
      if (mounted) {
        setState(() {
          messages = mergeChatMessages(
            messages,
            (result['messages'] as List).cast<Json>(),
          );
          before = result['before'] as int?;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => historyBusy = false);
    }
  }

  Future<void> send() async {
    final body = input.text.trim();
    if (sending || body.isEmpty) return;
    if (draftBody != body || draftId == null) {
      draftBody = body;
      draftId = newId();
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final sent = await widget.client.sendMessage(
        widget.room.id,
        body,
        draftId!,
      );
      if (!mounted) return;
      setState(() {
        messages = mergeChatMessages(messages, [sent]);
        draftId = null;
        draftBody = null;
      });
      input.clear();
      toBottom();
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> editProfile() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DiscussionProfilePage(client: widget.client),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> actions(Json item) async {
    if (item['recalled'] == true) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item['mine'] == true)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('撤回消息'),
                onTap: () => Navigator.pop(ctx, 'recall'),
              ),
            ListTile(
              leading: const Icon(Icons.flag_outlined),
              title: const Text('举报消息'),
              onTap: () => Navigator.pop(ctx, 'report'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    try {
      if (action == 'recall') {
        if (!await confirm(context, '撤回消息？', '其他同学将看到消息已撤回。', action: '撤回')) {
          return;
        }
        await widget.client.recallMessage(item['id'] as int);
        if (mounted) {
          setState(() {
            messages = mergeChatMessages(messages, [
              {...item, 'recalled': true, 'body': ''},
            ]);
          });
        }
      } else {
        final reason = await discussionText(context, '举报消息', '举报原因');
        if (reason == null) return;
        await widget.client.reportMessage(item['id'] as int, reason);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('举报已提交')));
        }
      }
    } catch (e) {
      if (mounted) await showError(context, e);
    }
  }

  Widget bubble(Json item, bool showTime) {
    final mine = item['mine'] == true;
    final time = SchoolClock.wall(
      DateTime.fromMillisecondsSinceEpoch(
        (item['created'] as int) * 1000,
        isUtc: true,
      ),
    );
    final avatar = UserAvatar(
      client: widget.client,
      userId: item['userId'] as String,
      name: item['name'] as String,
      version: item['avatarVersion'] as String? ?? '',
    );
    final content = Flexible(
      child: Column(
        crossAxisAlignment: mine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            item['name'] as String,
            style: Theme.of(context).textTheme.labelSmall,
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onLongPress: () => actions(item),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: mine
                    ? const Color(0xFFB7E99A)
                    : Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                child: Text(
                  item['body'] as String,
                  style: TextStyle(
                    fontSize: 16,
                    color: mine
                        ? const Color(0xFF182414)
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        children: [
          if (showTime)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 8),
              child: Text(
                '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ),
          if (item['recalled'] == true)
            Text(
              '${mine ? '你' : item['name']}撤回了一条消息',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: mine
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              children: [
                if (!mine) ...[avatar, const SizedBox(width: 8)],
                const SizedBox(width: 10),
                content,
                const SizedBox(width: 10),
                if (mine) ...[const SizedBox(width: 8), avatar],
              ],
            ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    active = state == AppLifecycleState.resumed;
    if (active && !loading) poll();
  }

  @override
  void dispose() {
    active = false;
    WidgetsBinding.instance.removeObserver(this);
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.room.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            connected ? '课程讨论群' : '正在连接…',
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '课程组队',
          icon: const Icon(Icons.groups_outlined),
          onPressed: () => Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => TeamPage(
                client: widget.client,
                room: widget.room,
                store: widget.store,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: '群信息',
          icon: const Icon(Icons.info_outline),
          onPressed: () => showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(widget.room.name),
              content: SingleChildScrollView(
                child: Text(
                  '${widget.room.teacher}\n上课班级：${widget.room.classes}\n\n${widget.room.schedule}',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: '设置头像和昵称',
          onPressed: editProfile,
          icon: const Icon(Icons.person_outline),
        ),
      ],
    ),
    body: Column(
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          MaterialBanner(
            content: Text(error!),
            actions: [
              TextButton(
                onPressed: () {
                  setState(() => error = null);
                  if (!connected && !polling) load();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        Expanded(
          child: Stack(
            children: [
              if (messages.isEmpty && !loading)
                const Center(child: Text('还没有消息，和同班同学打个招呼吧。')),
              ListView.builder(
                controller: scroll,
                reverse: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: messages.length + (before != null ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == messages.length) {
                    return Center(
                      child: TextButton(
                        onPressed: historyBusy ? null : history,
                        child: Text(historyBusy ? '正在加载…' : '加载更早消息'),
                      ),
                    );
                  }
                  final position = messages.length - 1 - index;
                  final item = messages[position];
                  return bubble(
                    item,
                    position == 0 ||
                        (item['created'] as int) -
                                (messages[position - 1]['created'] as int) >=
                            300,
                  );
                },
              ),
              if (unread > 0)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: FilledButton.tonal(
                    onPressed: toBottom,
                    child: Text('$unread 条新消息 ↓'),
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: input,
                      enabled: !sending && !loading,
                      minLines: 1,
                      maxLines: 5,
                      maxLength: 3000,
                      textInputAction: TextInputAction.newline,
                      decoration: const InputDecoration(
                        hintText: '发送消息',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: sending || loading ? null : send,
                    child: Text(sending ? '发送中' : '发送'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
