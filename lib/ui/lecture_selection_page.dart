import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../domain/school_import.dart';
import 'theme.dart';

const lectureSelectionUrl =
    'https://ehall.seu.edu.cn/gsapp/sys/yddjzxxtjappseu/*default/index.do';

class LectureSelectionPanel extends StatelessWidget {
  const LectureSelectionPanel({super.key});

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
    children: [
      Text('素质讲座选课', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.school_outlined, size: 36, color: context.meike.green),
              const SizedBox(height: 12),
              const Text('在学校平台查看素质讲座、报名和选课记录。'),
              const SizedBox(height: 8),
              Text(
                '使用学校账号登录，选课结果以学校平台为准。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const LectureSelectionPage(),
                  ),
                ),
                icon: const Icon(Icons.open_in_new),
                label: const Text('进入素质讲座选课'),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class LectureSelectionPage extends StatefulWidget {
  const LectureSelectionPage({super.key});
  @override
  State<LectureSelectionPage> createState() => _LectureSelectionPageState();
}

class _LectureSelectionPageState extends State<LectureSelectionPage> {
  late final WebViewController controller;
  int progress = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            final url = Uri.tryParse(request.url);
            final target = url == null ? null : schoolNavigationTarget(url);
            if (target == null || !mounted) {
              return NavigationDecision.prevent;
            }
            if (target != url) {
              unawaited(controller.loadRequest(target));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                progress = 0;
                error = null;
              });
            }
          },
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onWebResourceError: (event) {
            if (mounted && event.isForMainFrame == true) {
              setState(() => error = '学校网页加载失败，请检查校园网 / VPN 后刷新。');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(lectureSelectionUrl));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('素质讲座选课'),
      actions: [
        IconButton(
          tooltip: '素质讲座首页',
          onPressed: () =>
              controller.loadRequest(Uri.parse(lectureSelectionUrl)),
          icon: const Icon(Icons.home_outlined),
        ),
        IconButton(
          tooltip: '刷新学校页面',
          onPressed: () => controller.reload(),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      children: [
        if (progress < 100) LinearProgressIndicator(value: progress / 100),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(error ?? '在学校网页完成登录和选课，报名结果以学校平台为准。'),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
      ],
    ),
  );
}
