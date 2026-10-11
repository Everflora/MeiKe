import 'dart:io';

import 'package:flutter/material.dart';

/// Visual preferences live separately from timetable backups.
class AppearanceController extends ChangeNotifier {
  AppearanceController(this.file);
  final File file;
  ThemeMode mode = ThemeMode.system;
  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> load() async {
    try {
      if (await file.exists()) {
        final value = (await file.readAsString()).trim();
        mode = ThemeMode.values.firstWhere(
          (m) => m.name == value,
          orElse: () => ThemeMode.system,
        );
      }
    } on FileSystemException {
      mode = ThemeMode.system;
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> setMode(ThemeMode value) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(value.name, flush: true);
    mode = value;
    if (!_disposed) notifyListeners();
  }

  String get label => switch (mode) {
    ThemeMode.system => '跟随系统',
    ThemeMode.light => '浅色',
    ThemeMode.dark => '深色',
  };
}
