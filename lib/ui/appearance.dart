import 'dart:convert';
import '../platform/io.dart';

import 'package:flutter/material.dart';

enum MeikeTheme {
  plum('青梅'),
  ginkgo('银杏'),
  naiFamily('奶家日常');

  const MeikeTheme(this.label);
  final String label;
}

/// Visual preferences live separately from timetable backups.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this.file);
  final File file;
  ThemeMode mode = ThemeMode.system;
  MeikeTheme theme = MeikeTheme.plum;
  bool motion = true;
  bool eggPet = true;
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
    motion = true;
    eggPet = true;
    try {
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        // Earlier versions stored only a plain ThemeMode name.
        final decoded = value.startsWith('{') ? jsonDecode(value) : null;
        motion = decoded is! Map || decoded['motion'] != false;
        eggPet = decoded is! Map || decoded['eggPet'] != false;
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

  Future<void> setMotion(bool value) => _save(newMotion: value);

  Future<void> setEggPet(bool value) => _save(newEggPet: value);

  Future<void> _save({
    ThemeMode? newMode,
    MeikeTheme? newTheme,
    bool? newMotion,
    bool? newEggPet,
  }) {
    final saved = _pending.then((_) async {
      final nextMode = newMode ?? mode;
      final nextTheme = newTheme ?? theme;
      final nextMotion = newMotion ?? motion;
      final nextEggPet = newEggPet ?? eggPet;
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode({
          'mode': nextMode.name,
          'theme': nextTheme.name,
          'motion': nextMotion,
          'eggPet': nextEggPet,
        }),
        flush: true,
      );
      mode = nextMode;
      theme = nextTheme;
      motion = nextMotion;
      eggPet = nextEggPet;
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
