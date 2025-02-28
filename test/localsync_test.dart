import 'dart:io';

import 'package:localsync/localsync.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('findConflictsForTarget finds conflicts correctly', () async {
    // Create temporary directories
    final target1 = await Directory.systemTemp.createTemp('target1');

    // Define file structure
    final fileStructure = {
      'localsync.json':
          '{"version": 1, "packages": ["conflict-with-other", "self-conflict"]}',

      'localsync-inbox': {
        'conflict-with-other': {'file1.txt': ''},
        'self-conflict': {'file2.txt': ''},
      },
      'self-conflict': {'file2.txt': ''},
    };
    // Set up the file system
    setupFiles(target1.path, fileStructure);
    final inboxDir = Directory(p.join(target1.path, 'localsync-inbox'));
    // Call findConflictsForTarget
    final conflicts = await findConflictsForTarget(target1.path, inboxDir, [
      "conflict-with-other",
      "self-conflict",
    ]);

    // Assert that conflicts are found
    expect(
      conflicts['conflict-with-other'],
      contains(
        'conflict-with-other/file1.txt: found in ${target1.path}/conflict-with-other/file1.txt',
      ),
    );
    expect(
      conflicts['self-conflict'],
      contains(
        'self-conflict/file2.txt: found in ${target1.path}/self-conflict/file2.txt',
      ),
    );

    // Clean up temporary directories
    await target1.delete(recursive: true);
  });
}

void setupFiles(String targetPath, Map<String, dynamic> fileStructure) {
  fileStructure.forEach((name, content) {
    final entityPath = p.join(targetPath, name);
    if (content is String) {
      // Create a file
      final file = File(entityPath);
      file.createSync(recursive: true);
      file.writeAsStringSync(content);
    } else if (content is Map) {
      // Create a directory
      final directory = Directory(entityPath);
      directory.createSync(recursive: true);
      content.forEach((fileName, subContent) {
        final newPath = p.join(directory.path, fileName);
        setupFiles(newPath, subContent); // Recursive call
      });
    }
  });
}
