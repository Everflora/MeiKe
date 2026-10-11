import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/chat_file.dart';
import '../data/discussion_client.dart';
import 'discussion_helpers.dart';
import 'theme.dart';

class ChatFilePage extends StatefulWidget {
  const ChatFilePage({
    super.key,
    required this.client,
    required this.messageId,
    required this.name,
    required this.size,
  });
  final DiscussionClient client;
  final int messageId, size;
  final String name;
  @override
  State<ChatFilePage> createState() => _ChatFilePageState();
}

class _ChatFilePageState extends State<ChatFilePage> {
  bool busy = false;
  Uint8List? bytes;
  String? status;
  Future<void> save() async {
    if (busy) return;
    setState(() {
      busy = true;
      status = '正在下载…';
    });
    try {
      // Revalidate the message on every attempt, including after a recall.
      bytes = await widget.client.downloadFile(widget.messageId, widget.size);
      if (!mounted) return;
      setState(() => status = '请选择保存位置');
      final saved = await FilePicker.saveFile(
        fileName: widget.name,
        bytes: bytes!,
      );
      if (mounted) {
        setState(() => status = saved == null ? '已取消保存' : '已保存到所选位置');
      }
    } catch (e) {
      if (mounted) setState(() => status = message(e));
    } finally {
      bytes = null;
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('文件')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 64,
              color: context.meike.green,
            ),
            const SizedBox(height: 20),
            Text(
              widget.name,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(chatFileSize(widget.size)),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: busy ? null : save,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(busy ? '正在处理…' : '下载并保存到手机'),
            ),
            if (status != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(status!, textAlign: TextAlign.center),
              ),
          ],
        ),
      ),
    ),
  );
}
