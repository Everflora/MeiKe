import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/schedule_store.dart';
import 'ui/appearance.dart';
import 'ui/ginkgo_header.dart';
import 'ui/discussion_page.dart';
import 'ui/news_page.dart';
import 'ui/settings_page.dart';
import 'ui/timetable_page.dart';
import 'ui/today_page.dart';
import 'ui/theme.dart';
import 'ui/nai_family.dart';

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
      theme: meikeTheme(Brightness.light, appearance.theme),
      darkTheme: meikeTheme(Brightness.dark, appearance.theme),
      themeMode: appearance.mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations:
              MediaQuery.disableAnimationsOf(context) || !appearance.motion,
        ),
        child: child!,
      ),
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
      backgroundColor: context.meike.design == MeikeTheme.ginkgo
          ? context.meike.hero
          : context.meike.paper,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: context.meike.design == MeikeTheme.ginkgo
            ? SystemUiOverlayStyle.light
            : Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: SafeArea(
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
              if (context.meike.design == MeikeTheme.ginkgo)
                GinkgoHeader(store: widget.store),
              Expanded(
                child: ColoredBox(
                  color: context.meike.paper,
                  child: IndexedStack(
                    index: selected,
                    children: [
                      TimetablePage(store: widget.store),
                      TodayPage(store: widget.store),
                      discussionOpened
                          ? DiscussionPage(store: widget.store)
                          : const SizedBox(),
                      newsOpened
                          ? NewsPage(store: widget.store)
                          : const SizedBox(),
                      SettingsPage(
                        store: widget.store,
                        appearance: widget.appearance,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _navigation(context),
    ),
  );

  Widget _navigation(BuildContext context) {
    if (context.naiFamily) {
      return NaiNavigation(
        selected: selected,
        onSelect: (v) => setState(() {
          selected = v;
          if (v == 2) discussionOpened = true;
          if (v == 3) newsOpened = true;
        }),
      );
    }
    final bar = NavigationBar(
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
          selectedIcon: _SelectedIcon(Icon(Icons.calendar_month_outlined)),
          label: '课表',
        ),
        NavigationDestination(
          icon: Icon(Icons.wb_sunny_outlined),
          selectedIcon: _SelectedIcon(Icon(Icons.wb_sunny_outlined)),
          label: '今天',
        ),
        NavigationDestination(
          icon: Icon(Icons.forum_outlined),
          selectedIcon: _SelectedIcon(Icon(Icons.forum_outlined)),
          label: '讨论',
        ),
        NavigationDestination(
          icon: CampusIcon(),
          selectedIcon: _SelectedIcon(CampusIcon()),
          label: '校园',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: _SelectedIcon(Icon(Icons.person_outline_rounded)),
          label: '我的',
        ),
      ],
    );
    if (context.meike.design != MeikeTheme.ginkgo) return bar;
    return ColoredBox(
      color: context.meike.paper,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 5),
          child: Container(
            key: const ValueKey('ginkgo-floating-navigation'),
            decoration: BoxDecoration(
              color: context.meike.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .04),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: NavigationBarTheme(
              data: Theme.of(context).navigationBarTheme.copyWith(
                backgroundColor: context.meike.surface,
              ),
              child: bar,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedIcon extends StatelessWidget {
  const _SelectedIcon(this.icon);
  final Widget icon;
  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      icon,
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
