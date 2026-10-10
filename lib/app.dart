import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/schedule_store.dart';
import 'ui/courses_page.dart';
import 'ui/discussion_page.dart';
import 'ui/news_page.dart';
import 'ui/settings_page.dart';
import 'ui/timetable_page.dart';
import 'ui/today_page.dart';
import 'ui/theme.dart';

class SeuTimetableApp extends StatelessWidget {
  const SeuTimetableApp({super.key, required this.store});
  final ScheduleStore store;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SEU综合课表',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: _Home(store: store),
  );
  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? const Color(0xFF151C18) : canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xFF151C18) : canvas,
        foregroundColor: dark ? Colors.white : accent,
        centerTitle: true,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xFF232C26) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xFF232C26) : Colors.white,
        indicatorColor: accent.withValues(alpha: 0.12),
      ),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home({required this.store});
  final ScheduleStore store;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int selected = 0;
  bool discussionOpened = false;
  bool newsOpened = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!widget.store.canWrite)
              MaterialBanner(
                content: const Text('本地课表读取失败，原文件已保留，请在设置中恢复。'),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => selected = 5),
                    child: const Text('去设置'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  TimetablePage(store: widget.store),
                  TodayPage(store: widget.store),
                  CoursesPage(store: widget.store),
                  discussionOpened
                      ? DiscussionPage(store: widget.store)
                      : const SizedBox(),
                  newsOpened ? NewsPage(store: widget.store) : const SizedBox(),
                  SettingsPage(store: widget.store),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (v) => setState(() {
          selected = v;
          if (v == 3) discussionOpened = true;
          if (v == 4) newsOpened = true;
        }),
        height: 66,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_rounded),
            label: '课程',
          ),
          NavigationDestination(icon: Icon(Icons.forum_outlined), label: '讨论室'),
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            label: '新闻',
          ),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
        ],
      ),
    ),
  );
}
