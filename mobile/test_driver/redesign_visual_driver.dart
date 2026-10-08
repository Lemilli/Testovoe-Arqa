import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^(qa-)?(android|ios)-[a-z0-9-]+$').hasMatch(name)) {
        return false;
      }
      final directory = name.startsWith('qa-')
          ? Directory(
              Platform.environment['ARQA_QA_DIR'] ??
                  '${Directory.systemTemp.path}/arqa-redesign-qa',
            )
          : Directory('../docs/screenshots');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
