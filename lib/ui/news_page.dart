import 'dart:io';
import 'package:flutter/material.dart';
import '../data/news_store.dart';
import '../data/schedule_store.dart';
import '../domain/schedule.dart';
import 'labor_news_page.dart';
import 'theme.dart';
import 'jwc_news_page.dart';

class NewsPage extends StatefulWidget {
  const NewsPage({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<NewsPage> createState() => _NewsSectionsState();
}

class _NewsSectionsState extends State<NewsPage> {
  int selected = 0;
  bool jwcOpened = false;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      const BrandHeader(title: '校园消息', subtitle: '把与你有关的消息，放在一起。'),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(
          children: [
            ChoiceChip(
              label: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('劳动教育'),
              ),
              selected: selected == 0,
              onSelected: (_) => setState(() => selected = 0),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('教务通知'),
              ),
              selected: selected == 1,
              onSelected: (_) => setState(() {
                selected = 1;
                jwcOpened = true;
              }),
            ),
          ],
        ),
      ),
      Expanded(
        child: IndexedStack(
          index: selected,
          children: [
            LaborNewsPanel(store: widget.store),
            jwcOpened
                ? JwcNewsPanel(
                    file: File(
                      '${widget.store.file.parent.path}/jwc-news.json',
                    ),
                  )
                : const SizedBox(),
          ],
        ),
      ),
    ],
  );
}

class LaborNewsPanel extends StatefulWidget {
  const LaborNewsPanel({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<LaborNewsPanel> createState() => _NewsPageState();
}

class _NewsPageState extends State<LaborNewsPanel> {
  late final news = NewsStore(
    File('${widget.store.file.parent.path}/news.json'),
  );
  bool ready = false, busy = false, onlyAvailable = true;
  String query = '', location = '', category = '';
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    await news.load();
    if (mounted) setState(() => ready = true);
  }

  Future<void> sync() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final rows = await Navigator.of(context).push<List<dynamic>>(
        MaterialPageRoute(builder: (_) => const LaborNewsPage()),
      );
      if (rows == null) return;
      final count = await news.sync(rows);
      if (mounted) {
        setState(() {
          location = '';
          category = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              count == 0 ? '已更新 ${rows.length} 门课程' : '发现 $count 门新课程',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '新闻保存失败，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> open(NewsItem item) async {
    try {
      await news.markRead(item.id);
    } catch (_) {
      /* Reading remains available if cache saving fails. */
    }
    if (!mounted) return;
    setState(() {});
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('劳动教育课程')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(item.name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text('来源：东南大学劳动教育平台 · ${state(item)}'),
              const SizedBox(height: 20),
              for (final field in {
                'category': '劳动类型',
                'location': '开课地点',
                'time': '实施时间',
                'deadline': '选课截止',
                'enrollment': '选课情况',
                'teacher': '教师',
              }.entries)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(field.value),
                  subtitle: SelectableText(
                    item.field(field.key).isEmpty
                        ? '学校未提供'
                        : item.field(field.key),
                  ),
                ),
              const SizedBox(height: 12),
              const Text('课程信息为最近同步结果，实时名额和报名结果以学校选课页面为准。'),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('打开学校选课页面'),
                onPressed: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => const LaborNewsPage(sync: false),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String state(NewsItem item) => !item.present
      ? '已不在最新列表'
      : item.field('deadline').contains('已截止')
      ? '已截止'
      : item.field('enrollment').contains('已满')
      ? '已满'
      : '选课中';
  @override
  void dispose() {
    news.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = news.items
        .where(
          (item) =>
              (!onlyAvailable || item.selectable) &&
              (location.isEmpty || item.field('location') == location) &&
              (category.isEmpty || item.field('category') == category) &&
              '${item.name} ${item.field('teacher')} ${item.field('location')}'
                  .contains(query.trim()),
        )
        .toList();
    final locations =
        news.items
            .map((item) => item.field('location'))
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final categories =
        news.items
            .map((item) => item.field('category'))
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '劳动教育课程',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              TextButton.icon(
                onPressed: !ready || busy ? null : sync,
                icon: const Icon(Icons.sync),
                label: Text(busy ? '同步中' : '同步'),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: sync,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          news.updated == null
                              ? '首次同步需要学校登录，获取最新劳动教育课程。'
                              : '最近同步：${formatTime(news.updated!)} · ${news.items.where((item) => item.present).length} 门课程',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        if (error != null || news.loadError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              error ?? news.loadError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (value) => setState(() => query = value),
                          decoration: const InputDecoration(
                            hintText: '搜索课程、教师或地点',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            filter(
                              '全部地点',
                              location,
                              locations,
                              (value) => setState(() => location = value),
                            ),
                            filter(
                              '全部类型',
                              category,
                              categories,
                              (value) => setState(() => category = value),
                            ),
                            FilterChip(
                              label: const Text('仅看可选'),
                              selected: onlyAvailable,
                              onSelected: (value) =>
                                  setState(() => onlyAvailable = value),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                if (filtered.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.newspaper_outlined, size: 48),
                            const SizedBox(height: 12),
                            Text(
                              !ready
                                  ? '正在读取新闻…'
                                  : news.updated == null
                                  ? '同步后，在这里查看劳动教育选课信息'
                                  : '当前筛选下没有课程',
                            ),
                            if (ready && news.updated == null)
                              Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: FilledButton(
                                  onPressed: busy ? null : sync,
                                  child: const Text('登录并同步劳动教育'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return Card(
                      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => open(item),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (item.unread)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 8),
                                      child: Icon(
                                        Icons.fiber_new,
                                        color: accent,
                                      ),
                                    ),
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${item.field('category')} · ${state(item)}',
                              ),
                              if (item.field('time').isNotEmpty)
                                Text(item.field('time')),
                              if (item.field('location').isNotEmpty)
                                Text(item.field('location')),
                              if (item.field('enrollment').isNotEmpty)
                                Text(
                                  item.field('enrollment'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget filter(
    String label,
    String selected,
    List<String> values,
    ValueChanged<String> change,
  ) => PopupMenuButton<String>(
    tooltip: label,
    onSelected: change,
    itemBuilder: (_) => [
      PopupMenuItem(value: '', child: Text(label)),
      for (final value in values)
        PopupMenuItem(value: value, child: Text(value)),
    ],
    child: Chip(
      label: Text(
        selected.isEmpty ? label : selected,
        overflow: TextOverflow.ellipsis,
      ),
      avatar: const Icon(Icons.filter_list, size: 18),
    ),
  );
  String formatTime(int value) {
    final date = SchoolClock.wall(
      DateTime.fromMillisecondsSinceEpoch(value, isUtc: true),
    );
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
