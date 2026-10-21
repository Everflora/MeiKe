import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart'
    show kDebugMode, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import '../domain/school_import.dart';
import 'theme.dart';
import 'web_school_page.dart';

Future<void> importSchoolSchedule(
  BuildContext context,
  ScheduleStore store,
) async {
  if (!store.canWrite || store.busy) {
    await showError(context, const FormatException('请先完成当前保存，或在设置中恢复本地数据。'));
    return;
  }
  await Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) => kIsWeb
          ? WebSchoolImportPage(store: store)
          : SchoolImportPage(store: store),
    ),
  );
}

class SchoolImportPage extends StatefulWidget {
  const SchoolImportPage({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<SchoolImportPage> createState() => _SchoolImportPageState();
}

class _SchoolImportPageState extends State<SchoolImportPage> {
  static final entry = Uri.parse(
    'https://ehall.seu.edu.cn/appShow?appId=4770397878132218',
  );
  late final WebViewController controller;
  String currentUrl = '';
  String? nonce, status;
  List<({String code, String name})> terms = [];
  String? termCode;
  bool reading = false, previewing = false;
  int progress = 0;
  Timer? timeout;

  @override
  void initState() {
    super.initState();
    if (kDebugMode && defaultTargetPlatform == TargetPlatform.android) {
      AndroidWebViewController.enableDebugging(true);
    }
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('MeiKeSchoolImport', onMessageReceived: receive)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = Uri.tryParse(request.url);
            final target = url == null ? null : schoolNavigationTarget(url);
            if (request.isMainFrame && target != null && target != url) {
              unawaited(controller.loadRequest(target));
              return NavigationDecision.prevent;
            }
            if (url != null &&
                (isSchoolUrl(url) || request.url == 'about:blank')) {
              return NavigationDecision.navigate;
            }
            if (request.isMainFrame && mounted) {
              final destination = url == null
                  ? '无法识别的网址'
                  : '${url.scheme}://${url.host}${url.path}';
              setState(() => status = '学校跳转未能打开：$destination。请返回学校入口重试。');
            }
            return NavigationDecision.prevent;
          },
          onPageStarted: (url) {
            timeout?.cancel();
            if (!mounted) return;
            setState(() {
              currentUrl = url;
              nonce = null;
              reading = false;
              status = null;
            });
          },
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onPageFinished: (url) {
            currentUrl = url;
            final parsed = Uri.tryParse(url);
            if (parsed != null && isSchoolTimetableUrl(parsed) && !previewing) {
              unawaited(readSchedule());
            }
          },
          onWebResourceError: (error) {
            if (mounted && error.isForMainFrame == true) {
              setState(() => status = '学校网页加载失败，请检查校园网 / VPN 后点击刷新。');
            }
          },
        ),
      )
      ..loadRequest(entry);
  }

  @override
  void dispose() {
    timeout?.cancel();
    super.dispose();
  }

  Future<void> readSchedule() async {
    if (reading || previewing) return;
    final url = Uri.tryParse(await controller.currentUrl() ?? '');
    if (!mounted) return;
    if (url == null || !isSchoolTimetableUrl(url)) {
      setState(() => status = '请先在下方网页登录，进入学校课表后再读取。');
      return;
    }
    final requestNonce = newId();
    setState(() {
      nonce = requestNonce;
      reading = true;
      status = null;
    });
    timeout?.cancel();
    timeout = Timer(const Duration(seconds: 90), () {
      if (mounted && nonce == requestNonce && reading) {
        setState(() {
          reading = false;
          nonce = null;
          status = '读取超时，原课表未更改。请重试。';
        });
      }
    });
    try {
      final script = (await rootBundle.loadString('assets/school_import.js'))
          .replaceAll('__MEIKE_NONCE__', jsonEncode(requestNonce))
          .replaceAll('__MEIKE_TERM__', jsonEncode(termCode));
      if (mounted && nonce == requestNonce) {
        await controller.runJavaScript(script);
      }
    } catch (_) {
      if (mounted && nonce == requestNonce) {
        timeout?.cancel();
        setState(() {
          reading = false;
          status = '无法读取当前网页，请刷新学校课表后重试。';
        });
      }
    }
  }

  Future<void> receive(JavaScriptMessage message) async {
    if (!mounted ||
        !reading ||
        previewing ||
        message.message.length > ScheduleCodec.maxBytes) {
      return;
    }
    try {
      final payload = jsonDecode(message.message);
      if (payload is! Json || payload['nonce'] != nonce) return;
      final receivedNonce = nonce;
      final url = Uri.tryParse(await controller.currentUrl() ?? '');
      if (!mounted ||
          receivedNonce != nonce ||
          url == null ||
          !isSchoolTimetableUrl(url)) {
        return;
      }
      timeout?.cancel();
      if (payload['kind'] == 'terms') {
        final raw = payload['terms'];
        if (raw is! List || raw.isEmpty || raw.length > 200) {
          throw const FormatException('未读到有效学期，请刷新后重试。');
        }
        final available = <({String code, String name})>[];
        for (final item in raw) {
          if (item is! Json ||
              item['code'] is! String ||
              item['name'] is! String ||
              (item['code'] as String).isEmpty ||
              (item['name'] as String).isEmpty) {
            throw const FormatException('学校返回的学期信息无效。');
          }
          if (!available.any((t) => t.code == item['code'])) {
            available.add((
              code: item['code'] as String,
              name: item['name'] as String,
            ));
          }
        }
        final preferred = available
            .where((term) => term.name.trim() == '2026-2027学年秋季学期')
            .toList();
        setState(() {
          reading = false;
          terms = available;
          termCode = preferred.length == 1 ? preferred.single.code : null;
          status = termCode == null
              ? '请选择要导入的学期，再点“读取课表”。'
              : '已默认选择 2026-2027学年秋季学期，可切换学期后读取。';
        });
        return;
      }
      if (payload['kind'] == 'error') {
        final reason = payload['message'];
        setState(() {
          reading = false;
          status = reason is String && reason.length <= 300
              ? reason
              : '读取失败，请重试。';
        });
        return;
      }
      if (payload['kind'] != 'success') {
        throw const FormatException('学校返回的数据格式无效。');
      }
      final imported = SchoolImport.parse(payload);
      setState(() {
        reading = false;
        previewing = true;
        nonce = null;
      });
      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SchoolImportPreview(store: widget.store, imported: imported),
        ),
      );
      if (!mounted) return;
      setState(() => previewing = false);
      if (saved == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已导入 ${imported.courses.length} 门学校课程。')),
        );
      }
    } catch (error) {
      if (mounted) {
        timeout?.cancel();
        setState(() {
          reading = false;
          status = error is FormatException ? error.message : '课表读取失败，原课表未更改。';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget webview = WebViewWidget(controller: controller);
    if (controller.platform is AndroidWebViewController) {
      webview = WebViewWidget.fromPlatformCreationParams(
        params:
            AndroidWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
              PlatformWebViewWidgetCreationParams(
                controller: controller.platform,
              ),
              displayWithHybridComposition: true,
            ),
      );
    }
    final host = Uri.tryParse(currentUrl)?.host;
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入学校课表'),
        actions: [
          IconButton(
            tooltip: '学校入口',
            onPressed: () {
              termCode = null;
              terms = [];
              controller.loadRequest(entry);
            },
            icon: const Icon(Icons.home_outlined),
          ),
          IconButton(
            tooltip: '刷新网页',
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
            child: Text(
              '在学校网页完成登录，显示课表后自动读取。${host == null || host.isEmpty ? '' : '\n当前网站：$host'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(child: webview),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (status != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        status!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  if (terms.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(terms.map((t) => t.code).join(',')),
                        initialValue: termCode,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: '选择学期'),
                        items: terms
                            .map(
                              (t) => DropdownMenuItem(
                                value: t.code,
                                child: Text(t.name),
                              ),
                            )
                            .toList(),
                        onChanged: reading
                            ? null
                            : (value) => setState(() => termCode = value),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed:
                        reading ||
                            previewing ||
                            (terms.isNotEmpty && termCode == null)
                        ? null
                        : readSchedule,
                    icon: reading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_outlined),
                    label: Text(reading ? '正在读取课表…' : '读取课表'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SchoolImportPreview extends StatefulWidget {
  const SchoolImportPreview({
    super.key,
    required this.store,
    required this.imported,
  });
  final ScheduleStore store;
  final SchoolImport imported;
  @override
  State<SchoolImportPreview> createState() => _SchoolImportPreviewState();
}

class _SchoolImportPreviewState extends State<SchoolImportPreview> {
  DateTime? startDate;
  bool replace = false, saving = false;
  @override
  void initState() {
    super.initState();
    if (widget.store.data.semester.name == widget.imported.termName) {
      startDate = widget.store.data.semester.startDate;
    }
  }

  Future<void> chooseDate() async {
    final initial = SchoolClock.wall(
      startDate ?? widget.store.data.semester.startDate,
    );
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: '选择第 1 教学周的周一',
    );
    if (selected != null && mounted) {
      setState(
        () => startDate = SchoolClock.monday(
          SchoolClock.instant(selected.year, selected.month, selected.day),
        ),
      );
    }
  }

  Future<void> save() async {
    if (startDate == null || saving) return;
    if (replace && widget.store.data.courses.isNotEmpty) {
      final accepted = await confirm(
        context,
        '替换当前课表？',
        '当前 ${widget.store.data.courses.length} 门课程将被所选学期的学校课表替换。导入前会在本机保留一份旧课表备份。',
        action: '替换并导入',
        destructive: true,
      );
      if (!accepted || !mounted) return;
    }
    setState(() => saving = true);
    try {
      final candidate = widget.imported.candidate(
        widget.store.data,
        startDate!,
        replace: replace,
      );
      await widget.store.importSchool(candidate);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) await showError(context, error);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('确认导入')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            widget.imported.termName,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            '共 ${widget.imported.courses.length} 门课程，${widget.imported.courses.fold(0, (n, c) => n + c.meetings.length)} 条上课安排。',
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month),
            title: const Text('第 1 教学周的周一'),
            subtitle: Text(
              startDate == null
                  ? '请选择日期，确保周次准确（必填）'
                  : SchoolClock.fullDate(startDate!),
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: saving ? null : chooseDate,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: replace,
            onChanged: saving
                ? null
                : (value) => setState(() => replace = value),
            title: const Text('替换当前课表'),
            subtitle: Text(
              replace ? '删除当前课程，使用此次学校课表。' : '更新此前导入的课程，保留手动课程、备注和额外安排。',
            ),
          ),
          const Text('所有保留课程将使用此学期的开学日期。导入前会在本机保留旧课表备份。'),
          const SizedBox(height: 16),
          for (final course in widget.imported.courses)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (course.teacher.isNotEmpty) Text(course.teacher),
                    for (final meeting in course.meetings)
                      Text(
                        '${meeting.summary} · ${meeting.recurrence}${meeting.location.isEmpty ? '' : '\n${meeting.location}'}',
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: startDate == null || saving ? null : save,
            icon: saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              saving ? '正在导入…' : '确认导入 ${widget.imported.courses.length} 门课程',
            ),
          ),
        ),
      ),
    ),
  );
}
