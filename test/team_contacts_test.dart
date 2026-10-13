import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/discussion_client.dart';
import 'package:seu_timetable/data/team_client.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/team_contacts_page.dart';

class ContactClient extends DiscussionClient {
  ContactClient() : super(sessionFile: File('unused-contacts-session'));
  Json contacts = {'qq': '', 'wechat': '', 'email': ''};
  bool failLoad = false;
  final writes = <Json>[];
  @override
  Future<Json> request(String method, String path, {Json? body}) async {
    if (method == 'GET') {
      if (failLoad) throw const FormatException('加载失败');
      return {'contacts': contacts};
    }
    writes.add(body!);
    contacts = {...body};
    return {'contacts': contacts};
  }
}

void main() {
  testWidgets('QQ微信邮箱均可留空，填写一个或清空其他字段可保存', (tester) async {
    final fake = ContactClient();
    addTearDown(fake.close);
    for (final value in ['', 'student@example.com']) {
      await tester.pumpWidget(
        MaterialApp(
          home: TeamContactsPage(
            key: ValueKey(value),
            client: TeamClient(fake),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '邮箱（选填）'), value);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(fake.writes.last, {'qq': '', 'wechat': '', 'email': value});
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('加载失败不允许空表单覆盖服务器联系方式', (tester) async {
    final fake = ContactClient()..failLoad = true;
    addTearDown(fake.close);
    await tester.pumpWidget(
      MaterialApp(home: TeamContactsPage(client: TeamClient(fake))),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
          .onPressed,
      isNull,
    );
    expect(fake.writes, isEmpty);
    expect(find.text('重试'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
