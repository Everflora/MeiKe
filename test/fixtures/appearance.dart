import 'dart:io';

import 'package:seu_timetable/ui/appearance.dart';

Future<void> savePlumTheme(Directory directory) async {
  final appearance = AppearanceController(
    File('${directory.path}/appearance.txt'),
  );
  try {
    await appearance.setTheme(MeikeTheme.plum);
  } finally {
    appearance.dispose();
  }
}
