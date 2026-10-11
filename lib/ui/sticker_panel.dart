import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/chat_image.dart';
import '../data/discussion_client.dart';
import '../domain/schedule.dart';
import 'discussion_helpers.dart';
import 'theme.dart';

class StickerPanel extends StatefulWidget {
  const StickerPanel({super.key, required this.client});
  final DiscussionClient client;
  @override
  State<StickerPanel> createState() => _StickerPanelState();
}

class _StickerPanelState extends State<StickerPanel> {
  List<Json> stickers = [];
  bool busy = true;
  String? error;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.client.savedStickers();
      if (mounted) setState(() => stickers = result);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> add() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final file = await FilePicker.pickFile(type: FileType.image);
      if (file == null) return;
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in file.readAsByteStream()) {
        if (buffer.length + chunk.length > 15 * 1024 * 1024) {
          throw const FormatException('请选择小于 15 MB 的图片。');
        }
        buffer.add(chunk);
      }
      final png = await prepareChatImage(buffer.takeBytes());
      await widget.client.addSticker(bytes: png);
      final updated = await widget.client.savedStickers();
      if (mounted) setState(() => stickers = updated);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '无法添加表情包，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Json item) async {
    if (busy ||
        !await confirm(
          context,
          '移除表情包？',
          '从你的收藏中移除，已发出的消息仍会保留。',
          action: '移除',
        )) {
      return;
    }
    if (!mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.client.removeSticker(item['id'] as String);
      if (mounted) {
        setState(() => stickers.removeWhere((s) => s['id'] == item['id']));
      }
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.48,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '收藏的表情包',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  tooltip: '刷新表情包',
                  onPressed: busy ? null : load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (stickers.isEmpty && !busy && error == null)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('点＋上传，或长按聊天图片添加。'),
              ),
            Expanded(
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 100,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: stickers.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return InkWell(
                      onTap: busy ? null : add,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Semantics(
                          label: '上传表情包',
                          button: true,
                          child: const Icon(Icons.add, size: 36),
                        ),
                      ),
                    );
                  }
                  final item = stickers[index - 1];
                  return Semantics(
                    label: '收藏表情包 $index',
                    button: true,
                    child: InkWell(
                      onTap: busy ? null : () => Navigator.pop(context, item),
                      onLongPress: busy ? null : () => remove(item),
                      child: Image.network(
                        widget.client.stickerImageUrl(item['id'] as String),
                        headers: widget.client.imageHeaders,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                  );
                },
              ),
            ),
            const Text('点按发送 · 长按移除', style: TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}
