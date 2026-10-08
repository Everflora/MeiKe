import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/schedule.dart';

class ScheduleStore extends ChangeNotifier {
  ScheduleStore(this.file);
  final File file;
  ScheduleData _data = ScheduleData();
  ScheduleData get data => _data;
  bool canWrite = true;
  bool busy = false;
  String? loadError;
  static Future<ScheduleStore> open() async {
    final support = await getApplicationSupportDirectory();
    final store = ScheduleStore(File('${support.path}/KeJian/schedule.json'));
    await store.load();
    return store;
  }

  Future<void> load() async {
    try {
      await file.parent.create(recursive: true);
      if (await file.exists()) {
        if (await file.length() > ScheduleCodec.maxBytes) {
          throw const FormatException('本地课表超过 2 MB。');
        }
        _data = ScheduleCodec.decode(await file.readAsBytes());
      }
    } catch (e) {
      canWrite = false;
      loadError = '无法读取本地课表，原文件已保留。请先导出原始数据，再通过导入有效备份恢复。\n${friendlyError(e)}';
    }
    notifyListeners();
  }

  Future<void> replace(
    ScheduleData candidate, {
    bool recovering = false,
  }) async {
    if (busy) throw const FormatException('正在保存，请稍候。');
    busy = true;
    notifyListeners();
    final temp = File('${file.path}.tmp');
    try {
      if (!canWrite && !recovering) {
        throw const FormatException('请先导出原始数据，再导入有效备份恢复。');
      }
      final error = candidate.validationError();
      if (error != null) throw FormatException(error);
      final bytes = ScheduleCodec.encode(candidate);
      if (bytes.length > ScheduleCodec.maxBytes) {
        throw const FormatException('课表数据超过 2 MB，请减少备注或安排数量。');
      }
      await file.parent.create(recursive: true);
      if (!canWrite && await file.exists()) {
        await file.copy('${file.parent.path}/unreadable-${newId()}.json');
      }
      // Rename a fully flushed sibling file on the same filesystem. On iOS and
      // Android this replaces the destination atomically; never delete it first.
      await temp.writeAsBytes(bytes, flush: true);
      await temp.rename(file.path);
      _data = candidate.copy();
      canWrite = true;
      loadError = null;
    } finally {
      if (await temp.exists()) await temp.delete();
      busy = false;
      notifyListeners();
    }
  }

  Future<void> saveCourse(Course course) async {
    final candidate = data.copy();
    final c = course.copy()
      ..name = course.name.trim()
      ..teacher = course.teacher.trim()
      ..location = course.location.trim();
    final index = candidate.courses.indexWhere((item) => item.id == c.id);
    if (index < 0) {
      candidate.courses.add(c);
    } else {
      candidate.courses[index] = c;
    }
    await replace(candidate);
  }

  Future<void> deleteCourse(String id) async {
    final candidate = data.copy()..courses.removeWhere((c) => c.id == id);
    await replace(candidate);
  }

  Future<Uint8List> exportBytes() async =>
      canWrite ? ScheduleCodec.encode(data) : file.readAsBytes();
}

String friendlyError(Object error) =>
    error is FormatException ? error.message : '操作失败：$error';
