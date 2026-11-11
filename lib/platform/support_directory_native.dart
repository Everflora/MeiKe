import 'package:path_provider/path_provider.dart';

Future<String> supportDirectory() async =>
    (await getApplicationSupportDirectory()).path;

Future<void> initializePlatform() async {}

void openExternalPage(String url) {}
