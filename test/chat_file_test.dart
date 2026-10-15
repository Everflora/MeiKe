import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/chat_file.dart';
import 'package:seu_timetable/data/discussion_client.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/chat_page.dart';
import 'package:seu_timetable/ui/chat_file_page.dart';
import 'chat_test.dart' show FakeChat, item;

class MemoryPicker extends FilePickerPlatform {
  bool cancelSave = false;
  FileType? selectedType;
  String? savedName;
  Uint8List? savedBytes;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    selectedType = type;
    return null;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedBytes = bytes;
    return cancelSave ? null : Uri.parse('file:///test/saved.pdf');
  }
}

class FileChat extends FakeChat {
  @override
  Future<Json> messages(
    String room, {
    int? after,
    int? before,
    bool wait = false,
  }) {
    if (after != null) {
      return super.messages(room, after: after, before: before, wait: wait);
    }
    return Future.value({
      'messages': [
        {
          ...item(1, mine: true, body: '[文件] 课程资料.pdf'),
          'kind': 'file',
          'file': {'name': '课程资料.pdf', 'size': 4},
        },
      ],
      'cursor': 1,
      'before': null,
    });
  }

  @override
  Future<Uint8List> downloadFile(int id, int expectedSize) async =>
      Uint8List.fromList([1, 2, 3, 4]);
}

void main() {
  test('文件名允许中文，拒绝路径、控制字符及过长 UTF-8 名称', () {
    expect(chatFileName('  实验报告.pdf  '), '实验报告.pdf');
    for (final name in [
      '../a',
      r'dir\file.txt',
      'bad\r\nname',
      '',
      '..',
      '字' * 81,
    ]) {
      expect(() => chatFileName(name), throwsFormatException);
    }
  });
  test('分块读取保留全部字节，空文件与超限文件在读取时拒绝', () async {
    expect(
      await readChatFile(
        Stream.fromIterable([
          [1, 2],
          [3, 4],
        ]),
      ),
      [1, 2, 3, 4],
    );
    await expectLater(
      readChatFile(const Stream.empty()),
      throwsFormatException,
    );
    await expectLater(
      readChatFile(Stream.value(Uint8List(maxChatFileBytes + 1))),
      throwsFormatException,
    );
  });

  Future<void> showChat(WidgetTester tester, FileChat client) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          client: client,
          room: DiscussionRoom({
            'roomKey': 'demo',
            'name': '课程',
            'teachers': [],
            'attendingClassNames': [],
            'arrangements': [],
          }),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() {
      client.close();
    });
  }

  testWidgets('上传入口移除，历史文件仍可下载且不可收藏为表情', (tester) async {
    final previous = FilePickerPlatform.instance;
    final picker = MemoryPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final client = FileChat();
    await showChat(tester, client);
    expect(find.byTooltip('发送图片'), findsOneWidget);
    expect(find.byTooltip('表情'), findsOneWidget);
    expect(find.byTooltip('更多'), findsNothing);
    expect(find.byTooltip('取消文件'), findsNothing);
    expect(find.text('课程资料.pdf'), findsOneWidget);
    await tester.longPress(find.text('课程资料.pdf'));
    await tester.pumpAndSettle();
    expect(find.text('添加到表情包'), findsNothing);
    Navigator.of(tester.element(find.text('撤回消息'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('课程资料.pdf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载并保存到手机'));
    await tester.pumpAndSettle();
    expect(picker.savedName, '课程资料.pdf');
    expect(picker.savedBytes, [1, 2, 3, 4]);
    expect(find.text('已保存到所选位置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('图片入口只打开图片选择器，取消后保留文字草稿', (tester) async {
    final previous = FilePickerPlatform.instance;
    final picker = MemoryPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final client = FileChat();
    await showChat(tester, client);
    await tester.enterText(find.byType(TextField), '我的草稿');
    await tester.tap(find.byTooltip('发送图片'));
    await tester.pumpAndSettle();
    expect(picker.selectedType, FileType.image);
    expect(find.text('我的草稿'), findsOneWidget);
    expect(find.byTooltip('取消文件'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('小屏大字模式下长文件名仍可滚动到保存按钮', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = FileChat();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: ChatFilePage(
          client: client,
          messageId: 1,
          name: '${'实验资料' * 18}.pdf',
          size: 4,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(FilledButton));
    expect(find.byType(FilledButton).hitTestable(), findsOneWidget);
  });
}
