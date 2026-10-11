import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/schedule_store.dart';
import 'ui/appearance.dart';
import 'ui/discussion_page.dart';
import 'ui/news_page.dart';
import 'ui/settings_page.dart';
import 'ui/timetable_page.dart';
import 'ui/today_page.dart';
import 'ui/theme.dart';

class SeuTimetableApp extends StatefulWidget {
  const SeuTimetableApp({super.key, required this.store});
  final ScheduleStore store;
  @override
  State<SeuTimetableApp> createState() => _SeuTimetableAppState();
}

class _SeuTimetableAppState extends State<SeuTimetableApp> {
  late final appearance = AppearanceController(
    File('${widget.store.file.parent.path}/appearance.txt'),
  );
  @override
  void initState() {
    super.initState();
    appearance.load();
  }

  @override
  void dispose() {
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) => MaterialApp(
      title: '梅课',
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: meikeTheme(Brightness.light),
      darkTheme: meikeTheme(Brightness.dark),
      themeMode: appearance.mode,
      home: _Home(store: widget.store, appearance: appearance),
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({required this.store, required this.appearance});
  final ScheduleStore store;
  final AppearanceController appearance;
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
                    onPressed: () => setState(() => selected = 4),
                    child: const Text('去恢复'),
                  ),
                ],
              ),
            Expanded(
              child: IndexedStack(
                index: selected,
                children: [
                  TimetablePage(store: widget.store),
                  TodayPage(store: widget.store),
                  discussionOpened
                      ? DiscussionPage(store: widget.store)
                      : const SizedBox(),
                  newsOpened ? NewsPage(store: widget.store) : const SizedBox(),
                  SettingsPage(
                    store: widget.store,
                    appearance: widget.appearance,
                  ),
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
          if (v == 2) discussionOpened = true;
          if (v == 3) newsOpened = true;
        }),
        height: 60,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: _SelectedIcon(Icons.calendar_month_outlined),
            label: '课表',
          ),
          NavigationDestination(
            icon: Icon(Icons.wb_sunny_outlined),
            selectedIcon: _SelectedIcon(Icons.wb_sunny_outlined),
            label: '今天',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: _SelectedIcon(Icons.forum_outlined),
            label: '讨论',
          ),
          NavigationDestination(
            icon: Icon(Icons.newspaper_outlined),
            selectedIcon: _SelectedIcon(Icons.newspaper_outlined),
            label: '校园',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: _SelectedIcon(Icons.person_outline_rounded),
            label: '我的',
          ),
        ],
      ),
    ),
  );
}

class _SelectedIcon extends StatelessWidget {
  const _SelectedIcon(this.icon);
  final IconData icon;
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Icon(icon),
      Positioned(
        right: -5,
        top: -3,
        child: Container(
          width: 4,
          height: 4,
          decoration: const BoxDecoration(
            color: gingko,
            shape: BoxShape.circle,
          ),
        ),
      ),
    ],
  );
}
