import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/discussion_client.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/chat_page.dart';
import 'package:seu_timetable/ui/discussion_profile.dart';

Json item(int id, {String body = '同学的消息', bool mine = false}) => {
  'id': id,
  'userId': 'demo-user',
  'name': '演示同学',
  'avatarVersion': '',
  'body': body,
  'created': 1791500000,
  'mine': mine,
  'recalled': false,
  'clientId': 'demo-$id',
};

class FakeChat extends DiscussionClient {
  FakeChat() : super(sessionFile: File('unused-session.json'));
  final polls = <Completer<Json>>[];
  String? sent;
  @override
  bool get signedIn => true;
  @override
  Future<Json> messages(
    String room, {
    int? after,
    int? before,
    bool wait = false,
  }) {
    if (after == null) {
      return Future.value({
        'messages': [item(1)],
        'cursor': 1,
        'before': null,
      });
    }
    final pending = Completer<Json>();
    polls.add(pending);
    return pending.future;
  }

  @override
  Future<Json> sendMessage(String room, String content, String clientId) async {
    sent = content;
    return item(2, body: content, mine: true);
  }
}

void main() {
  test('聊天增量去重并更新撤回、昵称，保持消息顺序', () {
    final merged = mergeChatMessages(
      [item(2), item(1)],
      [
        {...item(1), 'recalled': true, 'body': '', 'name': '新昵称'},
        item(3),
        item(2),
      ],
    );
    expect(merged.map((m) => m['id']), [1, 2, 3]);
    expect(merged.first['recalled'], isTrue);
    expect(merged.first['name'], '新昵称');
  });

  testWidgets('宽图居中裁剪为服务器使用的 128 像素 PNG', (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 384, 128),
        Paint()..color = Colors.red,
      );
      canvas.drawRect(
        const Rect.fromLTWH(128, 0, 128, 128),
        Paint()..color = Colors.green,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(384, 128);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final png = await squareAvatar(bytes!.buffer.asUint8List());
      final codec = await ui.instantiateImageCodec(png);
      final output = (await codec.getNextFrame()).image;
      expect(output.width, 128);
      expect(output.height, 128);
      final rgba = await output.toByteData();
      final offset = (64 * 128 + 64) * 4;
      expect(rgba!.getUint8(offset + 1), greaterThan(rgba.getUint8(offset)));
      expect(png[24], 8);
      expect(png[25], anyOf(2, 6));
      output.dispose();
      codec.dispose();
      image.dispose();
      picture.dispose();
    });
  });

  testWidgets('小屏键盘下直接发消息，自动收消息且发送回执不重复', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final client = FakeChat();
    final room = DiscussionRoom({
      'roomKey': 'demo',
      'name': '演示课程',
      'teachers': ['教师'],
      'attendingClassNames': ['班级'],
      'arrangements': [],
    });
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(client: client, room: room),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('同学的消息'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '直接发送的消息');
    await tester.tap(find.widgetWithText(FilledButton, '发送'));
    await tester.pumpAndSettle();
    expect(client.sent, '直接发送的消息');
    expect(find.text('直接发送的消息'), findsOneWidget);
    client.polls.first.complete({
      'messages': [
        item(2, body: '直接发送的消息', mine: true),
        item(3, body: '实时收到的消息'),
      ],
      'cursor': 3,
      'before': null,
    });
    await tester.pumpAndSettle();
    expect(find.text('直接发送的消息'), findsOneWidget);
    expect(find.text('实时收到的消息'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    client.polls.last.complete({'messages': [], 'cursor': 3, 'before': null});
    await tester.pump();
    client.close();
  });
}
