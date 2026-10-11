import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

enum MeikeTheme {
  plum('青梅'),
  ginkgo('银杏');

  const MeikeTheme(this.label);
  final String label;
}

/// Visual preferences live separately from timetable backups.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this.file);
  final File file;
  ThemeMode mode = ThemeMode.system;
  MeikeTheme theme = MeikeTheme.plum;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    mode = ThemeMode.system;
    theme = MeikeTheme.plum;
    try {
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        // Earlier versions stored only a plain ThemeMode name.
        final decoded = value.startsWith('{') ? jsonDecode(value) : null;
        mode = ThemeMode.values.firstWhere(
          (m) => m.name == (decoded is Map ? decoded['mode'] : value),
          orElse: () => ThemeMode.system,
        );
        theme = MeikeTheme.values.firstWhere(
          (t) => t.name == (decoded is Map ? decoded['theme'] : null),
          orElse: () => MeikeTheme.plum,
        );
      }
    } on FileSystemException {
      mode = ThemeMode.system;
      theme = MeikeTheme.plum;
    } on FormatException {
      mode = ThemeMode.system;
      theme = MeikeTheme.plum;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setMode(ThemeMode value) => _save(newMode: value);

  Future<void> setTheme(MeikeTheme value) => _save(newTheme: value);

  Future<void> _save({ThemeMode? newMode, MeikeTheme? newTheme}) {
    final saved = _pending.then((_) async {
      final nextMode = newMode ?? mode;
      final nextTheme = newTheme ?? theme;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({'mode': nextMode.name, 'theme': nextTheme.name}),
        flush: true,
      );
      mode = nextMode;
      theme = nextTheme;
      if (!_disposed) notifyListeners();
    });
    // A failed write must not prevent a later selection from being saved.
    _pending = saved.catchError((Object _) {});
    return saved;
  }

  String get label => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}
