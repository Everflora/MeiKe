import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../data/news_store.dart';
import '../domain/schedule.dart';
import '../domain/school_import.dart';

class LaborNewsPage extends StatefulWidget {
  const LaborNewsPage({super.key, this.sync = true});
  final bool sync;
  @override
  State<LaborNewsPage> createState() => _LaborNewsPageState();
}

class _LaborNewsPageState extends State<LaborNewsPage> {
  late final WebViewController controller;
  bool reading = false;
  int progress = 0;
  String? nonce, status;
  Timer? timeout;
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('MeiKeLaborNews', onMessageReceived: receive)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            return url != null &&
                    (isSchoolUrl(url) || request.url == 'about:blank')
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageStarted: (_) {
            timeout?.cancel();
            if (mounted) {
              setState(() {
                reading = false;
                nonce = null;
                status = null;
              });
            }
          },
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageFinished: (value) {
            final url = Uri.tryParse(value);
            if (widget.sync && url != null && isLaborNewsUrl(url)) {
              unawaited(read());
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => status = '学校网页加载失败，请检查校园网 / VPN 后刷新。');
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(laborNewsUrl));
  }

  Future<void> read() async {
    if (reading) return;
    final url = Uri.tryParse(await controller.currentUrl() ?? '');
    if (!mounted) return;
    if (url == null || !isLaborNewsUrl(url)) {
      setState(() => status = '请先完成学校登录，进入劳动教育选课页面。');
      return;
    }
    final requestNonce = newId();
    setState(() {
      reading = true;
      nonce = requestNonce;
      status = '正在读取最新课程…';
    });
    timeout = Timer(const Duration(seconds: 30), () {
      if (mounted && nonce == requestNonce) {
        setState(() {
          reading = false;
          nonce = null;
          status = '读取超时，请刷新学校页面后重试。';
        });
      }
    });
    try {
      final script = (await rootBundle.loadString(
        'assets/labor_news.js',
      )).replaceAll('__MEIKE_LABOR_NONCE__', jsonEncode(requestNonce));
      if (mounted && nonce == requestNonce) {
        await controller.runJavaScript(script);
      }
    } catch (_) {
      if (mounted && nonce == requestNonce) {
        timeout?.cancel();
        setState(() {
          reading = false;
          nonce = null;
          status = '无法读取当前页面，请刷新后重试。';
        });
      }
    }
  }

  Future<void> receive(JavaScriptMessage message) async {
    if (!mounted || !reading || message.message.length > NewsStore.maxBytes) {
      return;
    }
    try {
      final data = jsonDecode(message.message);
      if (data is! Json || data['nonce'] != nonce) return;
      final requestNonce = nonce;
      final url = Uri.tryParse(await controller.currentUrl() ?? '');
      if (!mounted ||
          requestNonce != nonce ||
          url == null ||
          !isLaborNewsUrl(url)) {
        return;
      }
      timeout?.cancel();
      if (data['kind'] == 'courses' && data['rows'] is List) {
        nonce = null;
        reading = false;
        Navigator.of(context).pop<List<dynamic>>(data['rows'] as List);
      } else {
        setState(() {
          reading = false;
          nonce = null;
          status = data['message'] is String
              ? (data['message'] as String).substring(
                  0,
                  (data['message'] as String).length.clamp(0, 300),
                )
              : '学校返回的课程信息无法识别。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          reading = false;
          nonce = null;
          status = '学校返回的课程信息无法识别，请重试。';
        });
      }
    }
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.sync ? '同步劳动教育课程' : '劳动教育选课'),
      actions: [
        IconButton(
          tooltip: '学校选课首页',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => controller.loadRequest(Uri.parse(laborNewsUrl)),
        ),
        IconButton(
          tooltip: '刷新',
          icon: const Icon(Icons.refresh),
          onPressed: () => controller.reload(),
        ),
      ],
    ),
    body: Column(
      children: [
        if (progress < 100) LinearProgressIndicator(value: progress / 100),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            status ??
                (widget.sync
                    ? '在学校网页完成登录，课程列表出现后会自动读取。'
                    : '在学校网页手动选课，报名结果以学校平台为准。'),
          ),
        ),
        Expanded(child: WebViewWidget(controller: controller)),
        if (widget.sync)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: reading ? null : read,
                  icon: const Icon(Icons.sync),
                  label: Text(reading ? '正在读取…' : '读取课程通知'),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
