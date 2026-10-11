import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seu_timetable/data/chat_file.dart';
import 'package:seu_timetable/data/discussion_client.dart';
import 'package:seu_timetable/domain/schedule.dart';
import 'package:seu_timetable/ui/chat_page.dart';
import 'package:seu_timetable/ui/chat_file_page.dart';
import 'chat_test.dart' show FakeChat, item;

final class MemoryFile extends PlatformFile {
  @override
  String get name => '课程资料.pdf';
  @override
  Uri get uri => Uri.parse('file:///test/notes.pdf');
  @override
  Never get xFile => throw UnimplementedError();
  @override
  int? lengthSync() => 4;
  @override
  Future<int?> length() async => 4;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3, 4]);
  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.value(Uint8List.fromList([1, 2, 3, 4]));
}

class MemoryPicker extends FilePickerPlatform {
  bool cancel = false, cancelSave = false;
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
  }) async => cancel ? null : MemoryFile();
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
  final attempts = <String>[];
  bool failOnce = true;
  @override
  Future<Json> sendFile(
    String room,
    String name,
    Uint8List bytes,
    String clientId,
  ) async {
    attempts.add(clientId);
    if (failOnce) {
      failOnce = false;
      throw const FormatException('网络暂时断开，请重试');
    }
    return {
      ...item(2, mine: true, body: '[文件] $name'),
      'kind': 'file',
      'media': null,
      'file': {'name': name, 'size': bytes.length},
    };
  }

  @override
  Future<Uint8List> downloadFile(int id, int expectedSize) async =>
      Uint8List.fromList([1, 2, 3, 4]);
}

class FileRequestClient extends DiscussionClient {
  FileRequestClient() : super(sessionFile: File('unused'));
  Json? captured;
  bool legacy = false;
  @override
  Future<Json> request(String method, String path, {Json? body}) async {
    captured = body;
    if (legacy) throw const FormatException('不支持的消息类型。');
    return {
      'message': {'id': 1},
    };
  }
}

void main() {
  test('文件请求保留文件字节和发送标识，旧服务提示明确', () async {
    final client = FileRequestClient();
    addTearDown(client.close);
    await client.sendFile(
      'room',
      '课程.txt',
      Uint8List.fromList([1, 2, 3]),
      'same-id',
    );
    expect(client.captured!['clientId'], 'same-id');
    expect(client.captured!['fileName'], '课程.txt');
    expect(client.captured!['kind'], 'file');
    expect(base64Decode(client.captured!['media'] as String), [1, 2, 3]);
    client.legacy = true;
    await expectLater(
      client.sendFile('room', '课程.txt', Uint8List.fromList([1]), 'same-id'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '文件服务暂未启用，请稍后再试。',
        ),
      ),
    );
  });

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
  test('分块读取保留全部字节，空文件与超限文件在发送前拒绝', () async {
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

  testWidgets('文件需确认发送，失败重试不重复，消息可下载保存且不可收藏为表情', (tester) async {
    final previous = FilePickerPlatform.instance;
    final picker = MemoryPicker();
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final client = FileChat();
    await showChat(tester, client);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(client.attempts, isEmpty);
    expect(find.byTooltip('取消文件'), findsOneWidget);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('网络暂时断开，请重试'), findsOneWidget);
    expect(find.byTooltip('取消文件'), findsOneWidget);
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(client.attempts.length, 2);
    expect(client.attempts.toSet().length, 1);
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

  testWidgets('取消文件选择或待发送文件保留文字草稿且不上传', (tester) async {
    final previous = FilePickerPlatform.instance;
    final picker = MemoryPicker()..cancel = true;
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    final client = FileChat();
    await showChat(tester, client);
    await tester.enterText(find.byType(TextField), '我的草稿');
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('我的草稿'), findsOneWidget);
    expect(client.attempts, isEmpty);
    picker.cancel = false;
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('取消文件'));
    await tester.pumpAndSettle();
    expect(find.text('我的草稿'), findsOneWidget);
    expect(client.attempts, isEmpty);
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
