import 'dart:io';

import 'package:path/path.dart' as p;

getFiles(Directory directory) => Set.from(
  directory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .map((entity) => entity.path)
      .toList(),
);

void setupFiles(String targetPath, Map<String, dynamic> fileStructure) {
  fileStructure.forEach((name, content) {
    final entityPath = p.join(targetPath, name);
    if (content is String) {
      final file = File(entityPath);
      file.createSync(recursive: true);
      file.writeAsStringSync(content);
    } else if (content is Map<String, dynamic>) {
      final directory = Directory(entityPath);
      directory.createSync(recursive: true);
      setupFiles(entityPath, content);
    }
  });
}
