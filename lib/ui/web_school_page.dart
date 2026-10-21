import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/jwc_news.dart';
import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import '../platform/support_directory.dart';
import 'theme.dart';

class WebSchoolPage extends StatelessWidget {
  const WebSchoolPage({
    super.key,
    required this.title,
    required this.url,
    this.message,
  });
  final String title, url;
  final String? message;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.open_in_browser, size: 48, color: context.meike.green),
        const SizedBox(height: 20),
        Text(message ?? '将在浏览器中打开学校官网。请在学校页面登录和操作，结果以学校平台为准。'),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => openExternalPage(url),
          icon: const Icon(Icons.open_in_new),
          label: const Text('打开学校官网'),
        ),
        const SizedBox(height: 16),
        const Text('校外访问可能需要学校 VPN。梅课网页不会读取学校登录页面的账号或密码。'),
      ],
    ),
  );
}

class WebSchoolImportPage extends StatefulWidget {
  const WebSchoolImportPage({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<WebSchoolImportPage> createState() => _WebSchoolImportState();
}

class _WebSchoolImportState extends State<WebSchoolImportPage> {
  bool busy = false;
  Future<void> importBackup() async {
    setState(() => busy = true);
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (selected == null) return;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in selected.readAsByteStream()) {
        if (bytes.length + chunk.length > ScheduleCodec.maxBytes) {
          throw const FormatException('备份不能大于 2 MB。');
        }
        bytes.add(chunk);
      }
      final data = ScheduleCodec.decode(bytes.takeBytes());
      if (!mounted) return;
      final approved = await confirm(
        context,
        '导入这份课表？',
        '「${data.semester.name}」共 ${data.courses.length} 门课程，将替换网页当前课表。替换前会在本机保留原课表副本。',
        action: '确认导入',
        destructive: true,
      );
      if (!approved) return;
      await widget.store.importSchool(data);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('课表已导入并保存在本机。')));
        Navigator.pop(context);
      }
    } catch (error) {
      if (mounted) await showError(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('导入课表')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('把已有课表带到网页版', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        const Text(
          '在梅课手机 App 中进入「我的」导出 JSON 课表备份，保存到「文件」，再在这里选择导入。教师、教室、单双周和额外安排都会保留。',
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: busy ? null : importBackup,
          icon: const Icon(Icons.upload_file),
          label: Text(busy ? '正在导入…' : '选择课表备份'),
        ),
        const SizedBox(height: 28),
        const Text(
          '学校的一键登录导入目前仅在手机 App 中提供。浏览器安全机制不允许梅课网页读取其他学校网站的登录会话和页面。你也可以回到课表，用「＋」手动添加课程。',
        ),
      ],
    ),
  );
}

class WebJwcPanel extends StatelessWidget {
  const WebJwcPanel({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text('教务通知', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      const Text('选择栏目，在学校官网查看最新通知。网页版暂不自动抓取官网内容。'),
      for (final section in JwcSection.values)
        ListTile(
          title: Text(section.label),
          trailing: const Icon(Icons.open_in_new),
          onTap: () => openExternalPage(section.pageUrl(1).toString()),
        ),
    ],
  );
}

class WebDiscussionInfo extends StatelessWidget {
  const WebDiscussionInfo({super.key});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const BrandHeader(
        title: '课程讨论',
        subtitle: '同一间教室，也在这里相遇。',
        padding: EdgeInsets.only(bottom: 24),
      ),
      const Icon(Icons.forum_outlined, size: 54),
      const SizedBox(height: 20),
      Text('网页版讨论室准备中', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text('当前网页版本先提供课表、今日安排与校历。课程聊天和组队请继续使用手机 App；网页版接入完成后会在这里开放。'),
    ],
  );
}
