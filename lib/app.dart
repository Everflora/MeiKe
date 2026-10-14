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
import 'ui/nai_egg_pet.dart';

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
  final navigatorKey = GlobalKey<NavigatorState>();
  final homeKey = GlobalKey<_HomeState>();
  final petKey = GlobalKey<NaiEggCompanionState>();
  final routeTracker = NaiRouteTracker();
  LocalHistoryEntry? petHistory;
  bool removingHistory = false, disposing = false, navigating = false;

  void petExpansionChanged(bool open) {
    if (disposing) return;
    if (open) {
      final route = routeTracker.current;
      if (route is ModalRoute && petHistory == null) {
        petHistory = LocalHistoryEntry(
          onRemove: () {
            petHistory = null;
            if (!removingHistory && !disposing) petKey.currentState?.dismiss();
          },
        );
        route.addLocalHistoryEntry(petHistory!);
      }
    } else {
      final entry = petHistory;
      petHistory = null;
      removingHistory = true;
      entry?.remove();
      removingHistory = false;
    }
  }

  Future<void> petNavigate(int index) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null || navigating) return;
    navigating = true;
    try {
      for (var i = 0; i < 16 && navigator.canPop(); i++) {
        final previous = routeTracker.current;
        final handled = await navigator.maybePop();
        if (!mounted || !handled) return;
        if (routeTracker.routes.contains(previous)) {
          final confirmation = routeTracker.current;
          if (confirmation != previous && confirmation is PopupRoute) {
            final answer = await confirmation.popped;
            if (answer == true && previous != null) {
              await previous.popped;
            } else {
              await Future<void>.delayed(Duration.zero);
            }
          }
          if (!mounted || routeTracker.routes.contains(previous)) return;
        }
      }
      if (!navigator.canPop()) homeKey.currentState?.selectDestination(index);
    } finally {
      navigating = false;
    }
  }

  @override
  void initState() {
    super.initState();
    appearance.load();
  }

  @override
  void dispose() {
    disposing = true;
    petHistory?.remove();
    appearance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appearance,
    builder: (context, _) => MaterialApp(
      title: '梅课',
      navigatorKey: navigatorKey,
      navigatorObservers: [routeTracker],
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            child!,
            if (appearance.theme == MeikeTheme.naiFamily &&
                appearance.eggPet &&
                MediaQuery.viewInsetsOf(context).bottom == 0)
              NaiEggCompanion(
                key: petKey,
                onSelect: petNavigate,
                onExpansionChanged: petExpansionChanged,
              ),
          ],
        ),
      ),
      home: _Home(key: homeKey, store: widget.store, appearance: appearance),
    ),
  );
}

class _Home extends StatefulWidget {
  const _Home({super.key, required this.store, required this.appearance});
  final ScheduleStore store;
  final AppearanceController appearance;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int selected = 0;
  bool discussionOpened = false;
  bool newsOpened = false;
  void selectDestination(int index) {
    if (index < 0 || index > 4) return;
    setState(() {
      selected = index;
      if (index == 2) discussionOpened = true;
      if (index == 3) newsOpened = true;
    });
  }

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
      return NaiNavigation(selected: selected, onSelect: selectDestination);
    }
    final bar = NavigationBar(
      selectedIndex: selected,
      onDestinationSelected: selectDestination,
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
