import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/discussion_client.dart';
import '../data/avatar_png.dart';
import 'discussion_helpers.dart';
import 'theme.dart';

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.client,
    required this.userId,
    required this.name,
    required this.version,
    this.radius = 20,
  });
  final DiscussionClient client;
  final String userId, name, version;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      color: accent.withValues(alpha: 0.15),
      child: Center(
        child: Text(
          name.isEmpty ? '同' : name.characters.first,
          style: TextStyle(fontSize: radius * 0.8, color: accent),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius * 0.4),
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: version.isEmpty || userId.isEmpty
            ? fallback
            : Image.network(
                client.avatarUrl(userId, version),
                headers: client.imageHeaders,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

Future<Uint8List> squareAvatar(Uint8List source) async {
  if (source.length > 15 * 1024 * 1024) {
    throw const FormatException('请选择小于 15 MB 的图片。');
  }
  final codec = await ui.instantiateImageCodecWithSize(
    await ui.ImmutableBuffer.fromUint8List(source),
    getTargetSize: (width, height) => width >= height
        ? ui.TargetImageSize(width: width > 512 ? 512 : width)
        : ui.TargetImageSize(height: height > 512 ? 512 : height),
  );
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final size = image.width < image.height ? image.width : image.height;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        image,
        ui.Rect.fromLTWH(
          (image.width - size) / 2,
          (image.height - size) / 2,
          size.toDouble(),
          size.toDouble(),
        ),
        const ui.Rect.fromLTWH(0, 0, 128, 128),
        ui.Paint()..filterQuality = ui.FilterQuality.high,
      );
      final picture = recorder.endRecording();
      try {
        final avatar = await picture.toImage(128, 128);
        try {
          final bytes = await avatar.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          if (bytes == null) throw const FormatException('无法读取图片。');
          return encodeAvatarPng(
            bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
          );
        } finally {
          avatar.dispose();
        }
      } finally {
        picture.dispose();
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}

class DiscussionProfilePage extends StatefulWidget {
  const DiscussionProfilePage({
    super.key,
    required this.client,
    this.creating = false,
  });
  final DiscussionClient client;
  final bool creating;
  @override
  State<DiscussionProfilePage> createState() => _DiscussionProfilePageState();
}

class _DiscussionProfilePageState extends State<DiscussionProfilePage> {
  late final name = TextEditingController(text: widget.client.nickname);
  Uint8List? avatar;
  bool removeAvatar = false, busy = false;
  String? error;
  Future<void> pick() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await FilePicker.pickFile(type: FileType.image);
      if (result == null) return;
      final buffer = BytesBuilder(copy: false);
      await for (final chunk in result.readAsByteStream()) {
        if (buffer.length + chunk.length > 15 * 1024 * 1024) {
          throw const FormatException('请选择小于 15 MB 的图片。');
        }
        buffer.add(chunk);
      }
      final png = await squareAvatar(buffer.takeBytes());
      if (mounted) {
        setState(() {
          avatar = png;
          removeAvatar = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? e.message : '图片无法打开，请选择另一张图片。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy) return;
    if (name.text.trim().isEmpty) {
      setState(() => error = '请填写昵称。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (widget.creating) {
        await widget.client.signIn(name.text, avatar: avatar);
      } else {
        await widget.client.saveProfile(
          name.text,
          avatar: avatar,
          removeAvatar: removeAvatar,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('设置头像和昵称')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (busy) const LinearProgressIndicator(),
          const SizedBox(height: 24),
          Center(
            child: InkWell(
              onTap: busy ? null : pick,
              borderRadius: BorderRadius.circular(20),
              child: avatar != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.memory(
                        avatar!,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                      ),
                    )
                  : UserAvatar(
                      client: widget.client,
                      userId: widget.client.userId,
                      name: name.text,
                      version: removeAvatar ? '' : widget.client.avatarVersion,
                      radius: 48,
                    ),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: busy ? null : pick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('选择头像'),
            ),
          ),
          if (avatar != null || widget.client.avatarVersion.isNotEmpty)
            Center(
              child: TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        avatar = null;
                        removeAvatar = true;
                      }),
                child: const Text('恢复默认头像'),
              ),
            ),
          const SizedBox(height: 20),
          TextField(
            controller: name,
            enabled: !busy,
            maxLength: 24,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '昵称',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          const Text('头像和昵称保存在服务器，所有课程讨论室使用同一份资料。'),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(widget.creating ? '保存并进入' : '保存资料'),
          ),
        ],
      ),
    ),
  );
}
