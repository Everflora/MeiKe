import 'package:flutter/foundation.dart' show kIsWeb;
import 'web_school_page.dart';
import '../platform/io.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../data/jwc_news.dart';
import 'theme.dart';

class JwcNewsPanel extends StatefulWidget {
  const JwcNewsPanel({super.key, required this.file});
  final File file;
  @override
  State<JwcNewsPanel> createState() => _JwcSectionsState();
}

class _JwcSectionsState extends State<JwcNewsPanel> {
  JwcSection selected = JwcSection.latest;
  final opened = {JwcSection.latest};
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: DropdownButtonFormField<JwcSection>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '教务处栏目',
            border: _sectionBorder(context),
            enabledBorder: _sectionBorder(context),
            focusedBorder: _sectionBorder(context),
          ),
          items: [
            for (final section in JwcSection.values)
              DropdownMenuItem(value: section, child: Text(section.label)),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() {
                selected = value;
                opened.add(value);
              });
            }
          },
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: selected.index,
          children: [
            for (final section in JwcSection.values)
              opened.contains(section)
                  ? _JwcSectionPanel(
                      key: ValueKey(section),
                      file: section.cacheFile(widget.file),
                      section: section,
                    )
                  : const SizedBox(),
          ],
        ),
      ),
    ],
  );

  OutlineInputBorder _sectionBorder(BuildContext context) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: context.meike.green, width: 1.2),
  );
}

class _JwcSectionPanel extends StatefulWidget {
  const _JwcSectionPanel({
    super.key,
    required this.file,
    required this.section,
  });
  final File file;
  final JwcSection section;
  @override
  State<_JwcSectionPanel> createState() => _JwcNewsPanelState();
}

class _JwcNewsPanelState extends State<_JwcSectionPanel> {
  late final cache = JwcCache(widget.file);
  final client = JwcNewsClient();
  bool busy = false;
  String search = '';
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      await cache.load();
    } catch (_) {
      error = '本地通知缓存无法读取，将尝试获取最新通知。';
    }
    if (!mounted) return;
    setState(() {});
    await refresh();
  }

  Future<void> refresh({bool more = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await client.fetch(
        more ? cache.page + 1 : 1,
        section: widget.section,
      );
      if (!mounted) return;
      await cache.save(result, refresh: !more);
    } catch (e) {
      if (mounted) error = e is FormatException ? e.message : '教务通知读取失败，请重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = cache.items
        .where((item) => item.title.contains(search.trim()))
        .toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.section.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: '刷新教务通知',
                onPressed: busy ? null : refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            onChanged: (value) => setState(() => search = value),
            decoration: const InputDecoration(
              hintText: '搜索教务通知',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        busy
                            ? '正在获取教务通知…'
                            : cache.items.isEmpty
                            ? '暂无缓存，请刷新获取通知'
                            : '没有符合搜索的通知',
                      ),
                    ),
                  ),
                for (final item in items)
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: context.meike.goldSoft,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  widget.section.label,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.meike.goldInk,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                item.date,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            item.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                      subtitle: const Padding(
                        padding: EdgeInsets.only(top: 9),
                        child: Text('东南大学教务处 · 查看原文'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => JwcArticlePage(item: item),
                        ),
                      ),
                    ),
                  ),
                if (cache.page < cache.pages)
                  TextButton(
                    onPressed: busy ? null : () => refresh(more: true),
                    child: Text(busy ? '正在加载…' : '加载更早通知'),
                  ),
                if (cache.items.isNotEmpty)
                  Center(
                    child: Text(
                      '已加载 ${cache.items.length} 条 · 第 ${cache.page}/${cache.pages} 页',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class JwcArticlePage extends StatefulWidget {
  const JwcArticlePage({super.key, required this.item});
  final JwcNotice item;
  @override
  State<JwcArticlePage> createState() => _JwcArticlePageState();
}

class _JwcArticlePageState extends State<JwcArticlePage> {
  late final WebViewController controller;
  int progress = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) =>
              Uri.tryParse(request.url)?.scheme == 'https' ||
                  request.url == 'about:blank'
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
          onProgress: (value) {
            if (mounted) setState(() => progress = value);
          },
          onWebResourceError: (event) {
            if (mounted && event.isForMainFrame == true) {
              setState(() => error = '原文加载失败，请刷新重试。');
            }
          },
          onPageStarted: (_) {
            if (mounted) setState(() => error = null);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.item.url));
  }

  @override
  Widget build(BuildContext context) => kIsWeb
      ? WebSchoolPage(title: '教务通知原文', url: widget.item.url)
      : Scaffold(
          appBar: AppBar(
            title: const Text('教务通知原文'),
            actions: [
              IconButton(
                tooltip: '刷新原文',
                onPressed: () => controller.reload(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: [
              if (progress < 100)
                LinearProgressIndicator(value: progress / 100),
              if (error != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
              Expanded(child: WebViewWidget(controller: controller)),
            ],
          ),
        );
}
