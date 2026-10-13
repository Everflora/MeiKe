import 'package:flutter/material.dart';

import '../data/team_client.dart';
import '../domain/schedule.dart';
import 'discussion_helpers.dart';

class TeamContactsPage extends StatefulWidget {
  const TeamContactsPage({super.key, required this.client});
  final TeamClient client;
  @override
  State<TeamContactsPage> createState() => _TeamContactsPageState();
}

class _TeamContactsPageState extends State<TeamContactsPage> {
  final qq = TextEditingController(),
      wechat = TextEditingController(),
      email = TextEditingController();
  bool busy = true, loaded = false;
  String? error;
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
      final contacts =
          (await widget.client.get('contacts'))['contacts'] as Json;
      if (!mounted) return;
      qq.text = contacts['qq'] as String? ?? '';
      wechat.text = contacts['wechat'] as String? ?? '';
      email.text = contacts['email'] as String? ?? '';
      loaded = true;
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
      await widget.client.write('contacts', {
        'qq': qq.text.trim(),
        'wechat': wechat.text.trim(),
        'email': email.text.trim(),
      }, method: 'PUT');
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    qq.dispose();
    wechat.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('组队联系方式')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (busy) const LinearProgressIndicator(),
        const Text('以下均为选填，可以全部留空。联系方式跨课程复用，仅同队成员可在队伍详情查看，不参与匹配度计算。'),
        const SizedBox(height: 20),
        TextField(
          controller: qq,
          enabled: loaded && !busy,
          keyboardType: TextInputType.number,
          maxLength: 32,
          decoration: const InputDecoration(labelText: 'QQ（选填）'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: wechat,
          enabled: loaded && !busy,
          maxLength: 64,
          decoration: const InputDecoration(labelText: '微信（选填）'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: email,
          enabled: loaded && !busy,
          keyboardType: TextInputType.emailAddress,
          maxLength: 254,
          decoration: const InputDecoration(labelText: '邮箱（选填）'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (!loaded && !busy)
          TextButton(onPressed: load, child: const Text('重试')),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: loaded && !busy ? save : null,
          child: const Text('保存'),
        ),
      ],
    ),
  );
}
