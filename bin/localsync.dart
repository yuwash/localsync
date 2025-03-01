import 'package:localsync/sync.dart' as sync;
import 'package:localsync/localsync.dart' as target;
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
  await addPackagesToTargets(targetPaths, packagesToAdd);
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
        final target = target.Target(targetPath);
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

Future<void> addPackagesToTargets(
  List<String> targetPaths,
  List<String> packagesToAdd,
) async {
  for (final targetPath in targetPaths) {
    try {
      final target = target.Target(targetPath);
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
  await for (final inboxTargetPath in Stream.fromIterable(targetPaths)) {
    try {
      final inboxTarget = target.Target(inboxTargetPath);
      bool hasConflicts = false;

      await for (final targetPath in Stream.fromIterable(targetPaths)) {
        try {
          final target = target.Target(targetPath);
          final syncResult = await target.findConflicts(inboxTarget);
          if (syncResult.isNotEmpty) {
            hasConflicts = true;
            syncResult.forEach((package, files) {
              if (files.isNotEmpty) {
                final inboxPackagePath = p.join(inboxTargetPath, package);
                print('Conflicts found for $inboxPackagePath in $targetPath:');
                files.forEach(print);
              }
            });
          } else {
            print('Ready to sync $targetPath');
          }
        } catch (e) {
          print(e);
        }
      }

      if (!dryRun) {
        if (!hasConflicts) {
          final inboxPath = inboxTarget.inboxPath;
          print('Copying from $inboxPath to all targets...');
          final destinations =
              targetPaths.where((path) => path != inboxTargetPath).toList();
          await sync.recursiveCopy(inboxPath, destinations);

          print('Moving contents of $inboxPath to its local target...');
          final inboxDestination = [inboxTargetPath];
          await sync.recursiveCopy(inboxTarget.inboxPath, inboxDestination, doMove: true);
        } else {
          print('Skipping copy and move due to conflicts.');
        }
      }
    } catch (e) {
      print(e);
    }
  }
}

Future<void> installInboxDirectories(List<String> targetPaths) async {
  for (final targetPath in targetPaths) {
    try {
      final target = target.Target(targetPath);

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
