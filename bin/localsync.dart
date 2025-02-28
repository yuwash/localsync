import 'package:localsync/localsync.dart' as localsync;
import 'dart:io';

const initFlag = '--init';
const addFlagLong = '--add';
const addFlagShort = '-a';

void main(List<String> arguments) async {
  if (arguments.isEmpty) {
    print('Usage: localsync <target_folder1> <target_folder2> ...');
    print('       localsync --init <target_folder1> <target_folder2> ...');
    print(
      '       localsync --add <package> <target_folder1> <target_folder2> ...',
    );
    return;
  }

  if (arguments.first == initFlag) {
    final targetPaths = arguments.sublist(1);
    if (targetPaths.isEmpty) {
      print('Usage: localsync $initFlag <target_folder1> <target_folder2> ...');
      return;
    }
    for (final targetPath in targetPaths) {
      final targetDir = Directory(targetPath);
      if (!targetDir.existsSync()) {
        print('Error: Target folder "$targetPath" does not exist.');
        continue; // Or exit(1); if you prefer exiting the entire process
      } else {
        try {
          await localsync.initializeTarget(targetPath);
        } catch (e) {
          print(e);
        }
      }
    }
  } else if (arguments.first == addFlagLong ||
      arguments.first == addFlagShort) {
    if (arguments.length < 3) {
      print(
        'Usage: localsync $addFlagLong <package> <target_folder1> <target_folder2> ...',
      );
      return;
    }

    final packageToAdd = arguments[1];
    final targetPaths = arguments.sublist(2);

    for (final targetPath in targetPaths) {
      final targetDir = Directory(targetPath);
      if (!targetDir.existsSync()) {
        print('Error: Target folder "$targetPath" does not exist.');
        continue; // Or exit(1); if you prefer exiting the entire process
      } else {
        try {
          await localsync.addPackageToTarget(targetPath, packageToAdd);
        } catch (e) {
          print(e);
        }
      }
    }
  } else {
    for (final targetPath in arguments) {
      try {
        final syncResult = await localsync.findConflicts(targetPath);
        if (syncResult.isNotEmpty) {
          print('Conflicts found in $targetPath/localsync-inbox:');
          syncResult.forEach((target, files) {
            if (files.isNotEmpty) {
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
  }
}
