import 'dart:io';

import 'package:localsync/localsync.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'utils.dart' as utils;

void main() {
  test(
    'initialize creates a localsync.json with default values, and config getter reads it',
    () async {
      final targetDir = await Directory.systemTemp.createTemp('target');
      final target = Target(targetDir.path);

      final initialized = await target.initialize();
      expect(initialized, isTrue);

      expect(target.configFile.existsSync(), isTrue);

      final config = target.config;
      await targetDir.delete(recursive: true);
      expect(config.version, equals(1));
      expect(config.packages, equals([]));
    },
  );

  test('findConflictsForTarget finds conflicts correctly', () async {
    final targetDir = await Directory.systemTemp.createTemp('target');
    final target = Target(targetDir.path);

    final fileStructure = {
      'localsync.json': '{"version": 1, "packages": ["self-conflict"]}',

      'localsync-inbox': {
        'self-conflict': {'file1.txt': '', 'file2.txt': ''},
      },
      'self-conflict': {'file2.txt': ''},
    };
    utils.setupFiles(targetDir.path, fileStructure);

    final conflicts = await findConflictsForTarget(target.inboxPath, targetDir.path, [
      "self-conflict",
    ]);
    await targetDir.delete(recursive: true);

    expect(
      conflicts['self-conflict'],
      equals([p.join('self-conflict', 'file2.txt')]),
    );
  });

  test('findConflictsForPackage identifies conflicts correctly', () async {
    final target1 = await Directory.systemTemp.createTemp('target1');

    final fileStructure = {
      'self-conflict': {'file2.txt': ''},
      'localsync-inbox': {
        'self-conflict': {'file1.txt': '', 'file2.txt': ''},
      },
    };
    utils.setupFiles(target1.path, fileStructure);
    final packageDir = Directory(p.join(target1.path, 'self-conflict'));
    final inboxPackageDir = Directory(
      p.join(target1.path, 'localsync-inbox', 'self-conflict'),
    );
    final expectedConflictPaths = {p.join(packageDir.path, 'file2.txt')};

    final conflicts = await findConflictsForPackage(
      inboxPackageDir,
      packageDir,
    );
    await target1.delete(recursive: true);

    expect(
      Set.of(conflicts.map((file) => file.path)),
      equals(expectedConflictPaths),
    );
  });
}
