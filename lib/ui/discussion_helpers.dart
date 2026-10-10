import 'package:flutter/material.dart';

String message(Object error) =>
    error is FormatException ? error.message : '暂时无法连接，请稍后重试。';

Future<String?> discussionText(
  BuildContext context,
  String title,
  String label, {
  int maxLength = 300,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextDialog(title: title, label: label, maxLength: maxLength),
);

class _TextDialog extends StatefulWidget {
  const _TextDialog({
    required this.title,
    required this.label,
    required this.maxLength,
  });
  final String title, label;
  final int maxLength;
  @override
  State<_TextDialog> createState() => _TextDialogState();
}

class _TextDialogState extends State<_TextDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: controller,
      autofocus: true,
      maxLength: widget.maxLength,
      decoration: InputDecoration(labelText: widget.label),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (controller.text.trim().isNotEmpty) {
            Navigator.pop(context, controller.text.trim());
          }
        },
        child: const Text('确定'),
      ),
    ],
  );
}
