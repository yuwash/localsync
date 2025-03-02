import 'package:localsync/sync.dart' as sync;
import 'package:localsync/localsync.dart' as synctarget;
import 'dart:io';
import 'package:args/args.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) async {
  final parser =
      ArgParser()
        ..addFlag(
          'init',
          abbr: 'i',
          negatable: false,
          help: 'Initialize a target directory.',
        )
        ..addMultiOption(
          'add',
          abbr: 'a',
          help: 'Add a package to a target directory.',
        )
        ..addFlag(
          'add-all',
          abbr: 'A',
          negatable: false,
          help: 'Add all packages from all targets to each target.',
        )
        ..addFlag(
          'clean',
          abbr: 'C',
          negatable: false,
          help: 'Removes any empty package directory inside an inbox.',
        )
        ..addFlag(
          'help',
          abbr: 'h',
          negatable: false,
          help: 'Display help information.',
        )
        ..addFlag(
          'install-inbox',
          abbr: 'I',
          negatable: false,
          help: 'Install the inbox directory and package directories.',
        )
        ..addFlag(
          'sync',
          abbr: 's',
          negatable: false,
          help: 'Synchronize the target directories (copy and delete).',
        );

  ArgResults argResults;
  try {
    argResults = parser.parse(arguments);
  } catch (e) {
    print('Error: $e');
    print(parser.usage);
    exit(1);
  }

  if (argResults['help'] == true) {
    print('Usage: localsync [options] <target_folder1> <target_folder2> ...');
    print(parser.usage);
    return;
  }

  final targetPaths = argResults.rest;
  if (targetPaths.isEmpty) {
    print('No target directories specified.'); // Not an error.
    return;
  }
  if (argResults['init'] == true) {
    await initializeTargets(targetPaths);
    return;
  }
  if (argResults['install-inbox'] == true) {
    await installInboxDirectories(targetPaths);
    return;
  }

  final packagesToAdd = argResults['add'];
  final addAll = argResults['add-all'] == true;

  if (addAll) {
    await addAllPackagesToTargets(targetPaths);
  }
  await addPackagesToTargets(targetPaths, packagesToAdd);
  if (argResults['clean'] == true) {
    await cleanInboxDirectories(targetPaths);
  }
  await synchronize(targetPaths, dryRun: !argResults['sync']);
}

Future<void> initializeTargets(List<String> targetPaths) async {
  for (final targetPath in targetPaths) {
    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      print('Error: Target folder "$targetPath" does not exist.');
      continue;
    } else {
      try {
        final target = synctarget.Target(targetPath);
        final initialized = await target.initialize();
        if (initialized) {
          print('Initialized ${target.configFile.path}');
        } else {
          print('${target.configFile.path} already exists');
        }
      } catch (e) {
        print(e);
      }
    }
  }
}

Future<void> cleanInboxDirectories(List<String> targetPaths) async {
  for (final targetPath in targetPaths) {
    try {
      final target = synctarget.Target(targetPath);
      final deletedDirectories = await target.cleanInbox();
      if (deletedDirectories.isNotEmpty) {
        print('Removed empty package directories in ${target.inboxPath}:');
        deletedDirectories.forEach(print);
      } else {
        print('No empty package directories found in ${target.inboxPath}');
      }
    } catch (e) {
      print(e);
    }
  }
}

Future<void> addAllPackagesToTargets(List<String> targetPaths) async {
  final targets =
      targetPaths.map((targetPath) => synctarget.Target(targetPath)).toList();

  final allPackages = synctarget.Target.unionPackages(targets);

  for (final targetPath in targetPaths) {
    try {
      final target = synctarget.Target(targetPath);
      final addedPackages = await target.addPackages(allPackages);
      if (addedPackages.isNotEmpty) {
        print('Added $addedPackages to ${target.configFilePath}');
      } else {
        print('All packages already listed in ${target.configFilePath}');
      }
    } catch (e) {
      print(e);
    }
  }
}

Future<void> addPackagesToTargets(
  List<String> targetPaths,
  List<String> packagesToAdd,
) async {
  for (final targetPath in targetPaths) {
    try {
      final target = synctarget.Target(targetPath);
      if (packagesToAdd.isNotEmpty) {
        final addedPackages = await target.addPackages(packagesToAdd);
        if (addedPackages.isNotEmpty) {
          print('Added $addedPackages to ${target.configFilePath}');
        } else {
          print('All packages already listed in ${target.configFilePath}');
        }
      }
    } catch (e) {
      print(e);
    }
  }
}

Future<void> synchronize(List<String> targetPaths, {bool dryRun = true}) async {
  final targets =
      targetPaths.map((targetPath) => synctarget.Target(targetPath)).toList();
  if (targets.length == 0) {
    return; // Not an error but the intersection below won’t work.
  }
  final totalIntersectionPackages = synctarget.Target.intersectionPackages(
    targets,
  );
  await for (final inboxTargetPath in Stream.fromIterable(targetPaths)) {
    try {
      final inboxTarget = synctarget.Target(inboxTargetPath);
      if (!inboxTarget.inboxDir.existsSync()) {
        print('No inbox found in $inboxTargetPath, skipping.');
        continue;
      }
      bool hasConflicts = false;

      await for (final targetPath in Stream.fromIterable(targetPaths)) {
        try {
          final target = synctarget.Target(targetPath);
          final syncResult = await target.findConflicts(inboxTarget);
          if (syncResult.isNotEmpty) {
            hasConflicts = true;
            syncResult.forEach((package, files) {
              if (files.isNotEmpty) {
                final inboxPackagePath = p.join(inboxTarget.inboxPath, package);
                print('Conflicts found for $inboxPackagePath in $targetPath:');
                files.forEach(print);
              }
            });
          }
        } catch (e) {
          print(e);
        }
      }

      await for (final targetPath in Stream.fromIterable(targetPaths)) {
        try {
          final target = synctarget.Target(targetPath);
          final packageComparison = inboxTarget.comparePackages(target);
          if (packageComparison == null) {
            continue;
          }
          if (packageComparison.ourAdditional.isNotEmpty) {
            print('Difference in configured packages found:');
            print(
              '$inboxTargetPath has packages missing in $targetPath: ${packageComparison.ourAdditional}',
            );
          }
          // No need to print their additional because not relevant
          // for this step.
          // Would be printed when that becomes the inboxTarget in the
          // outer loop.
        } catch (e) {
          print(e);
        }
      }

      if (hasConflicts) {
        if (!dryRun) {
          print('Skipping copy and move due to conflicts.');
        }
        continue; // The individual conflicts were already printed.
      }

      print('Ready to sync ${inboxTarget.inboxPath}');
      if (dryRun) {
        continue;
      }

      final otherTargetPaths =
          targetPaths.where((path) => path != inboxTargetPath).toList();
      for (final package in totalIntersectionPackages) {
        final sourcePath = p.join(inboxTarget.inboxPath, package);
        if (!Directory(sourcePath).existsSync()) {
          continue;
        }

        print('Copying from $sourcePath to all targets...');
        final destinations =
            otherTargetPaths.map((path) => p.join(path, package)).toList();
        await sync.recursiveCopy(sourcePath, destinations);

        print('Moving contents of $sourcePath to its local target...');
        final inboxDestination = [p.join(inboxTargetPath, package)];
        await sync.recursiveCopy(sourcePath, inboxDestination, move: true);
      }
    } catch (e) {
      print(e);
    }
  }
}

Future<void> installInboxDirectories(List<String> targetPaths) async {
  for (final targetPath in targetPaths) {
    try {
      final target = synctarget.Target(targetPath);

      if (!target.inboxDir.existsSync()) {
        target.inboxDir.createSync();
        print('Created inbox directory: ${target.inboxPath}');
      } else {
        print('Inbox directory already exists: ${target.inboxPath}');
      }

      final createdDirectories = await target.installInbox();
      if (createdDirectories.isNotEmpty) {
        print('Created directories:');
        createdDirectories.forEach(print);
      } else {
        print('No directories created for ${target.inboxPath}');
      }
    } catch (e) {
      print(e);
    }
  }
}
