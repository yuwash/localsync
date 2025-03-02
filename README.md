# localsync

Tool for distributing files to local directories written in dart.
Copies files from the inbox into all given target directories, and then
moves the inbox contents to its local target.

## Usage

```bash
localsync <target_folder1> <target_folder2> ...
```

## Options

| Option          | Abbr. | Description                                                                  |
| --------------- | ----- | ---------------------------------------------------------------------------- |
| `--init`        | `-i`  | Initialize a target directory.                                               |
| `--add`         | `-a`  | Add a package to a target directory.                                        |
| `--add-all`     | `-A`  | Add all packages from all targets to each target.                            |
| `--help`        | `-h`  | Display help information.                                                    |
| `--install-inbox` | `-I`  | Install the inbox directory and package directories.                         |
| `--sync`        | `-s`  | Synchronize the target directories (copy and delete files, resolves conflicts). |

## Limitations

Requires manual resolution of conflicting files. It will abort when a conflict is found in any given target.

## Configuration

### `localsync.json`

Each target directory contains a `localsync.json` file that specifies the configuration for the local sync tool. The file is a JSON document with the following structure:

```json
{
  "version": 1,
  "packages": [
    "package1",
    "package2"
  ]
}
```

* `version`: Version of the file syntax.
* `packages`: Names of a packages to be synchronized which correspond to subdirectories within the targets and the inboxes.

### `localsync-inbox`

Each target directory also contains a `localsync-inbox` directory. This directory serves as the source for files that will be copied to other target directories. Before synchronization, the `localsync` tool copies the contents of the inbox directory to all other target directories. After the copy, the contents of the inbox are moved to the target directory itself.

