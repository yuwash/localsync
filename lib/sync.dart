import 'dart:io';
import 'package:path/path.dart' as p;
import 'dart:async';

Future<void> recursiveCopy(
  String source,
  List<String> destinations, {
  bool move = false,
  bool useCpIfAvailable = true,
}) async {
  if (move && destinations.length > 1) {
    throw ArgumentError('Cannot move to multiple destinations.');
  }
  final useCp = !move && useCpIfAvailable && await _isCpAvailable();

  for (final destination in destinations) {
    if (useCp) {
      final cpArguments = ['-arT', source, destination];
      final process = await Process.run('cp', cpArguments);
      if (process.exitCode != 0) {
        throw ProcessException(
          'cp',
          cpArguments,
          process.stderr,
          process.exitCode,
        );
      }
      continue;
    }
    final sourceDir = Directory(source);
    final Stream<FileSystemEntity> entities =
        sourceDir.existsSync() ? sourceDir.list() : Stream.fromIterable([sourceDir]);
    await for (final entity in entities) {
      final relativePath = p.relative(entity.path, from: source);
      final copyPath = p.join(destination, relativePath);

      if (entity is File) {
        final sourceFile = File(entity.path);
        final copyFile = File(copyPath);
        if (copyFile.existsSync()) {
          continue;
        } else if (move) {
          sourceFile.renameSync(copyFile.path);
        } else {
          copyFile.createSync();
          copyFile.writeAsBytesSync(sourceFile.readAsBytesSync());
          final lastModified = sourceFile.lastModifiedSync();
          copyFile.setLastModifiedSync(lastModified);
        }
      } else if (entity is Directory) {
        final targetDirectory = Directory(copyPath);
        if (!targetDirectory.existsSync()) {
          if (move) {
            entity.renameSync(copyPath);
          } else {
            targetDirectory.createSync();
            await recursiveCopy(entity.path, [
              copyPath,
            ], useCpIfAvailable: useCp);
          }
        } else {
          await recursiveCopy(
            entity.path,
            [copyPath],
            move: move,
            useCpIfAvailable: useCp,
          );
        }
      }
    }
  }
}

Future<bool> _isCpAvailable() async {
  final process = await Process.run('which', ['cp']);
  return process.exitCode == 0;
}
