import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

Future<String> supportDirectory() async => '/meike';

Future<void> initializePlatform() async {
  final loader = FontLoader('MeikeWebSans')
    ..addFont(rootBundle.load('web-fonts/NotoSansSC.ttf'));
  await loader.load();
}

void openExternalPage(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty) return;
  web.window.open(uri.toString(), '_blank', 'noopener,noreferrer');
}
