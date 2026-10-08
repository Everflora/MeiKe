import 'package:flutter/material.dart';
import 'app.dart';
import 'data/schedule_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ScheduleStore.open();
  runApp(SeuTimetableApp(store: store));
}
