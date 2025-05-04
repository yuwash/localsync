import 'dart:io';

import 'package:localsync/sync.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'utils.dart' as utils;

void main() {
  test(
    'recursiveCopy copies files correctly when cp is not available',
    () async {
      final target1Dir = await Directory.systemTemp.createTemp('target1');
      final target2Dir = await Directory.systemTemp.createTemp('target2');
      final fileStructure = {
        'localsync-inbox': {
          'package1': {'file1.txt': 'content1', 'file2.txt': 'content2'},
        },
      };
      utils.setupFiles(target1Dir.path, fileStructure);
      final inboxDir = Directory(p.join(target1Dir.path, 'localsync-inbox'));
      final destinations = [target2Dir.path];

      await recursiveCopy(inboxDir.path, [
        target1Dir.path,
        target2Dir.path,
      ], useCpIfAvailable: false);

      final target2Package1File1 = File(
        p.join(target2Dir.path, 'package1', 'file1.txt'),
      );
      final target2Package1File2 = File(
        p.join(target2Dir.path, 'package1', 'file2.txt'),
      );

      expect(target2Package1File1.readAsStringSync(), equals('content1'));
      expect(target2Package1File2.readAsStringSync(), equals('content2'));

      await target1Dir.delete(recursive: true);
      await target2Dir.delete(recursive: true);
    },
  );

  test(
    'recursiveCopy preserves existing files and content in target directory',
    () async {
      final target1Dir = await Directory.systemTemp.createTemp('target1');
      final target2Dir = await Directory.systemTemp.createTemp('target2');

      // Set up initial file structure in target1 (source)
      final fileStructure1 = {
        'package1': {'file1.txt': 'content1', 'file2.txt': 'content2'},
      };
      utils.setupFiles(target1Dir.path, fileStructure1);

      // Set up initial file structure in target2 (destination)
      final fileStructure2 = {
        'package1': {
          'file2.txt': 'different content2-1',
          'file3.txt': 'content3-1',
        },
        'package2': {'file2.txt': 'content2-2'},
      };
      utils.setupFiles(target2Dir.path, fileStructure2);

      await recursiveCopy(target1Dir.path, [
        target2Dir.path,
      ], useCpIfAvailable: false);

      final target2Files = utils.getFiles(target2Dir);
      final expectedFiles = {
        p.join(target2Dir.path, 'package1', 'file1.txt'), // Added.
        p.join(target2Dir.path, 'package1', 'file2.txt'),
        p.join(target2Dir.path, 'package1', 'file3.txt'),
        p.join(target2Dir.path, 'package2', 'file2.txt'),
        // file1 not added to package2.
      };
      expect(target2Files, equals(expectedFiles));

      final target2Package1File2 = File(
        p.join(target2Dir.path, 'package1', 'file2.txt'),
      );
      expect(
        // Unchanged.
        target2Package1File2.readAsStringSync(),
        equals('different content2-1'),
      );

      await target1Dir.delete(recursive: true);
      await target2Dir.delete(recursive: true);
    },
  );

  test(
    'recursiveCopy moves files correctly when move is true',
    () async {
      final target1Dir = await Directory.systemTemp.createTemp('target1');
      final target2Dir = await Directory.systemTemp.createTemp('target2');
      final fileStructure = {
        'package1': {'file1.txt': 'content1', 'file2.txt': 'content2'},
      };
      utils.setupFiles(target1Dir.path, fileStructure);

      final destinations = [target2Dir.path];

      await recursiveCopy(target1Dir.path, destinations,
          useCpIfAvailable: false, move: true);

      final target2Package1File1 = File(
        p.join(target2Dir.path, 'package1', 'file1.txt'),
      );
      final target2Package1File2 = File(
        p.join(target2Dir.path, 'package1', 'file2.txt'),
      );

      expect(target2Package1File1.readAsStringSync(), equals('content1'));
      expect(target2Package1File2.readAsStringSync(), equals('content2'));

      expect(await target1Dir.list().toList(), []);

      await target2Dir.delete(recursive: true);
    },
  );

  test(
    'recursiveCopy moves files correctly when move is true and destination does not exist',
    () async {
      final target1Dir = await Directory.systemTemp.createTemp('target1');
      final target2ParentDir = await Directory.systemTemp.createTemp('target2Parent');
      final target2DirPath = p.join(target2ParentDir.path, 'target2');
      final fileStructure = {
        'package1': {'file1.txt': 'content1', 'file2.txt': 'content2'},
      };
      utils.setupFiles(target1Dir.path, fileStructure);

      final destinations = [target2DirPath];

      await recursiveCopy(target1Dir.path, destinations,
          useCpIfAvailable: false, move: true);

      expect(target1Dir.existsSync(), isFalse);

      final target2Package1File1 = File(
        p.join(target2DirPath, 'package1', 'file1.txt'),
      );
      final target2Package1File2 = File(
        p.join(target2DirPath, 'package1', 'file2.txt'),
      );

      final target2Dir = Directory(target2DirPath);
      expect(target2Dir.existsSync(), isTrue);
      expect(target2Package1File1.readAsStringSync(), equals('content1'));
      expect(target2Package1File2.readAsStringSync(), equals('content2'));

      await target2ParentDir.delete(recursive: true);
    },
  );
}
