library localsync;

import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;

const supportedConfigVersion = 1;

Future<Map<String, List<String>>> findConflicts(String targetPath) async {
  final targetDir = Directory(targetPath);
  if (!targetDir.existsSync()) {
    throw Exception('Error: Target folder "$targetPath" does not exist.');
  }

  final configFile = File(p.join(targetDir.path, 'localsync.json'));
  if (!configFile.existsSync()) {
    throw Exception(
      'Error: localsync.json not found in "$targetPath". Please run --init first.',
    );
  }

  final configString = await configFile.readAsString();
  final config = jsonDecode(configString);
  final version = config['version'];
  final packages = config['packages'] as List<dynamic>?;
  if (version == null || (version is int && version > supportedConfigVersion)) {
    throw Exception(
      'Error: Invalid or missing version in localsync.yml in "$targetPath".',
    );
  }
  if (packages == null || packages is! List) {
    throw Exception('Error: Packages not found or not a list');
  }
  return await findConflictsForTarget(
    targetPath,
    Directory(p.join(targetPath, 'localsync-inbox')),
    packages.cast<String>(),
  );
}

Future<void> initializeTarget(String targetPath) async {
  final targetDir = Directory(targetPath);
  if (!targetDir.existsSync()) {
    throw Exception('Error: Target folder "$targetPath" does not exist.');
  }

  final configFile = File(p.join(targetDir.path, 'localsync.json'));
  if (!configFile.existsSync()) {
    final yamlContent = {'version': supportedConfigVersion};
    final yamlString = jsonEncode(yamlContent);
    configFile.writeAsStringSync(yamlString);
    print('Initialized localsync.json in $targetPath');
  } else {
    print('localsync.json already exists in $targetPath');
  }
}

Future<void> addPackageToTarget(String targetPath, String packageToAdd) async {
  final targetDir = Directory(targetPath);
  if (!targetDir.existsSync()) {
    throw Exception('Error: Target folder "$targetPath" does not exist.');
  }

  final configFile = File(p.join(targetDir.path, 'localsync.json'));
  if (!configFile.existsSync()) {
    throw Exception(
      'Error: localsync.json not found in "$targetPath". Please run --init first.',
    );
  }

  final configString = await configFile.readAsString();
  final config = jsonDecode(configString);

  List<dynamic> packages = (config['packages'] as List<dynamic>?) ?? [];

  if (!packages.contains(packageToAdd)) {
    packages.add(packageToAdd);
    config['packages'] = packages = packages;

    final jsonString = jsonEncode(config);
    configFile.writeAsStringSync(jsonString);
    print('Added package "$packageToAdd" to $targetPath/localsync.json');
  } else {
    print(
      'Package "$packageToAdd" already exists in $targetPath/localsync.json',
    );
  }
}

Future<Map<String, List<String>>> findConflictsForTarget(
  // Changed return type
  String targetPath,
  Directory inboxDir,
  List<String> packages,
) async {
  if (!inboxDir.existsSync()) {
    return {};
  }

  return Stream.fromIterable(packages)
      .asyncMap((package) async {
        List<String> conflictingFiles = [];
        final packageDir = Directory('${inboxDir.path}/$package');
        if (!packageDir.existsSync()) {
          return conflictingFiles;
        }

        List<FileSystemEntity> filesToCheck = [];
        try {
          filesToCheck = packageDir.listSync(
            recursive: true,
            followLinks: false,
          );
        } catch (e) {
          print("Error listing files in $packageDir: $e");
          return conflictingFiles;
        }

        for (final entity in filesToCheck) {
          if (entity is File) {
            final relativePath = entity.path.replaceFirst(
              packageDir.path + Platform.pathSeparator,
              '',
            );
            final conflictLocations = await findConflictsForPackage(
              targetPath,
              relativePath,
              package,
              packages,
            );
            if (conflictLocations.isNotEmpty) {
              conflictingFiles.add(
                '${package}/$relativePath: found in ${conflictLocations.join(', ')}',
              );
            }
          }
        }
        return conflictingFiles;
      })
      .fold<Map<String, List<String>>>({}, (previousValue, element) {
        previousValue[packages.first] = element;
        return previousValue;
      });
}

Future<List<String>> findConflictsForPackage(
  String currentTargetPath,
  String relativePath,
  String package,
  List<String> packages,
) async {
  List<String> conflictLocations = [];

  for (final targetPath in Directory.current
      .listSync()
      .whereType<Directory>()
      .map((e) => e.path)
      .where((path) => path != currentTargetPath)) {
    final targetDir = Directory(targetPath);
    if (!targetDir.existsSync()) {
      continue;
    }

    final configFile = File('${targetPath}/localsync.json');
    if (!configFile.existsSync()) {
      continue;
    }

    final configString = await configFile.readAsString();
    final config = jsonDecode(configString);
    final targetPackages = config['packages'] as List<dynamic>?;

    if (targetPackages == null ||
        targetPackages is! List ||
        !targetPackages.contains(package)) {
      continue;
    }

    final potentialConflictFile = File(
      p.join(targetPath, package, relativePath),
    );
    if (potentialConflictFile.existsSync()) {
      conflictLocations.add('$targetPath/$package/$relativePath');
    }
  }

  return conflictLocations;
}
