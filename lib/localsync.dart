library localsync;

import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:belatuk_json_serializer/belatuk_json_serializer.dart'
    as jsonSerializer;

const supportedConfigVersion = 1;

class LocalSyncConfig {
  int version;
  List<String> packages;

  LocalSyncConfig({version, packages})
    : version = version ?? supportedConfigVersion,
      packages = packages ?? [];
}

class Target {
  final String path;
  final String configFileName = 'localsync.json';
  final String inboxDirName = 'localsync-inbox';

  Target(this.path) {
    if (!Directory(path).existsSync()) {
      throw Exception('Error: Target folder "$path" does not exist.');
    }
  }

  String get configFilePath => p.join(path, configFileName);
  File get configFile => File(configFilePath);
  String get inboxPath => p.join(path, inboxDirName);
  Directory get inboxDir => Directory(inboxPath);

  LocalSyncConfig get config => jsonSerializer.deserialize(
    this.configFile.readAsStringSync(),
    outputType: LocalSyncConfig,
  );

  Future<bool> initialize() async {
    final targetDir = Directory(this.path);
    if (this.configFile.existsSync()) {
      return false;
    }
    final config = LocalSyncConfig(version: supportedConfigVersion);
    final jsonString = jsonSerializer.serialize(config);
    this.configFile.writeAsStringSync(jsonString);
    return true;
  }

  Future<List<String>> addPackages(List<String> packageNames) async {
    final config = this.config;
    List<String> packages = config.packages ?? [];

    List<String> packagesToAdd =
        packageNames
            .where((packageName) => !packages.contains(packageName))
            .toList();
    if (!packagesToAdd.isEmpty) {
      packages.addAll(packagesToAdd);
      config.packages = packages;
      final jsonString = jsonSerializer.serialize(config);
      this.configFile.writeAsStringSync(jsonString);
    }
    return packagesToAdd;
  }

  Future<List<String>> installInbox() async {
    final inboxDir = this.inboxDir;

    if (!inboxDir.existsSync()) {
      inboxDir.createSync();
    }

    final config = this.config;
    final packages = config.packages;
    List<String> createdPackages = [];

    for (final package in packages) {
      final packageDir = Directory(p.join(inboxDir.path, package));
      if (!packageDir.existsSync()) {
        packageDir.createSync();
        createdPackages.add(packageDir.path);
      }
    }
    return createdPackages;
  }

  ({Set<String> ourAdditional, Set<String> theirAdditional})? comparePackages(
    Target other,
  ) {
    final packagesSet = this.config.packages.toSet();
    final otherPackagesSet = other.config.packages.toSet();
    final comparison = (
      ourAdditional: packagesSet.difference(otherPackagesSet),
      theirAdditional: otherPackagesSet.difference(packagesSet),
    );
    if (comparison.ourAdditional.isEmpty &&
        comparison.theirAdditional.isEmpty) {
      return null;
    }
    return comparison;
  }

  static Set<String> intersectionPackages(Iterable<Target> targets) => targets
      .map((target) => target.config.packages.toSet())
      .reduce((a, b) => a.intersection(b));

  Future<Map<String, List<String>>> findConflicts([Target? inboxTarget]) async {
    final targetDir = Directory(this.path);
    final config = this.config;
    final version = config.version;
    final packages = config.packages;
    if (version == null ||
        (version is int && version > supportedConfigVersion)) {
      throw Exception(
        'Error: Invalid or missing version in "${this.configFilePath}".',
      );
    }
    if (packages == null || packages is! List) {
      throw Exception('Error: Packages not found or not a list');
    }
    final inboxPath = (inboxTarget ?? this).inboxPath;
    final intersectionPackages =
        (inboxTarget == null)
            ? packages
            : Target.intersectionPackages([this, inboxTarget]);
    return await findConflictsForTarget(
      inboxPath,
      this.path,
      intersectionPackages,
    );
  }
}

Future<Map<String, List<String>>> findConflictsForTarget(
  String inboxPath,
  String targetPath,
  Iterable<String> packages,
) async {
  if (!Directory(inboxPath).existsSync()) {
    return {};
  }

  return Stream.fromIterable(packages)
      .map(
        (package) => (
          package: package,
          conflictingFiles: findConflictsForPackage(
            Directory(p.join(inboxPath, package)),
            Directory(p.join(targetPath, package)),
          ),
        ),
      )
      .fold({}, (result, element) {
        if (element.conflictingFiles.isEmpty) {
          return result;
        }
        result[element.package] =
            element.conflictingFiles
                .map((file) => p.relative(file.path, from: targetPath))
                .toList();
        return result;
      });
}

List<File> findConflictsForPackage(
  Directory inboxPackageDir,
  Directory packageDir,
) {
  List<File> conflictingFiles = [];
  if (!(packageDir.existsSync() && inboxPackageDir.existsSync())) {
    return conflictingFiles;
  }
  final targetFiles = packageDir.listSync().whereType<File>().toList();
  conflictingFiles.addAll(
    inboxPackageDir
        .listSync()
        .whereType<File>()
        .cast<File?>()
        .map(
          // The conflictingFiles are to be filled with the target files.
          (file) =>
              file is Null
                  ? null
                  : targetFiles
                      .where(
                        (targetFile) =>
                            p.basename(targetFile.path) ==
                            p.basename(file.path),
                      )
                      .firstOrNull,
        )
        .whereType<File>(),
  );
  conflictingFiles.addAll(
    inboxPackageDir
        .listSync()
        .whereType<Directory>()
        .map(
          (inboxSubpackageDir) => findConflictsForPackage(
            inboxSubpackageDir,
            Directory(
              p.join(packageDir.path, p.basename(inboxSubpackageDir.path)),
            ),
          ),
        )
        .fold(
          [],
          (Iterable<File> left, List<File> right) => [...left, ...right],
        ),
  );
  return conflictingFiles;
}
