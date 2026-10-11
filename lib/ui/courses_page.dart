import 'package:flutter/material.dart';

import '../data/schedule_store.dart';
import 'course_editor.dart';
import 'theme.dart';

Future<void> showCourses(BuildContext context, ScheduleStore store) =>
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('课程管理')),
          body: SafeArea(
            child: ListenableBuilder(
              listenable: store,
              builder: (context, _) => CoursesPage(store: store),
            ),
          ),
        ),
      ),
    );

class CoursesPage extends StatefulWidget {
  const CoursesPage({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<CoursesPage> createState() => _CoursesPageState();
}

class _CoursesPageState extends State<CoursesPage> {
  String search = '';
  @override
  Widget build(BuildContext context) {
    final courses =
        widget.store.data.courses
            .where((c) => c.searchText.contains(search.trim().toLowerCase()))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 12),
          child: Row(
            children: [
              Text(
                '所有课程',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '添加课程',
                onPressed: () => editCourse(context, widget.store),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            onChanged: (v) => setState(() => search = v),
            decoration: const InputDecoration(
              hintText: '搜索课程、教师、教室',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            children: [
              if (courses.isEmpty)
                EmptySchedule(
                  title: search.isEmpty ? '还没有课程' : '没有找到课程',
                  subtitle: search.isEmpty
                      ? '以课程为单位添加，常规课和额外实验都放在同一门课里。'
                      : '试试课程名、教师或教室。',
                ),
              for (final c in courses)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () => editCourse(context, widget.store, c),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: c.color.foreground(context),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    c.name,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                ),
                                const Icon(Icons.chevron_right, size: 18),
                              ],
                            ),
                            if (c.teacher.isNotEmpty || c.location.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Text(
                                  [
                                    c.teacher,
                                    c.location,
                                  ].where((s) => s.isNotEmpty).join(' · '),
                                ),
                              ),
                            for (final m in c.meetings)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  '${m.summary} · ${m.recurrence}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                            for (final e in c.extras)
                              Container(
                                margin: const EdgeInsets.only(top: 10),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: c.color.surface(context),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${e.title} · ${e.summary}',
                                  style: TextStyle(
                                    color: c.color.foreground(context),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
