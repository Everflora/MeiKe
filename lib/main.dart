import 'package:flutter/material.dart';
import 'app.dart';
import 'platform/support_directory.dart';
import 'data/schedule_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializePlatform();
  final store = await ScheduleStore.open();
  runApp(SeuTimetableApp(store: store));
}
