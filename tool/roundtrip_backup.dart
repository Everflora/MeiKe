import 'dart:io';

import 'package:seu_timetable/domain/schedule.dart';

// Validate a v1 SwiftUI/Flutter backup and re-encode it without changing IDs.
void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('用法：dart run tool/roundtrip_backup.dart 输入.json 输出.json');
    exitCode = 64;
    return;
  }
  final input = File(args[0]);
  if (input.lengthSync() > ScheduleCodec.maxBytes) {
    throw const FormatException('备份不能大于 2 MB。');
  }
  final data = ScheduleCodec.decode(input.readAsBytesSync());
  File(args[1]).writeAsBytesSync(ScheduleCodec.encode(data), flush: true);
  stdout.writeln('已验证 ${data.courses.length} 门课程，备份格式版本 ${data.version}。');
}
