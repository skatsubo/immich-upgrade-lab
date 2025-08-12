# Immich upgrade lab

Test Immich upgrades in a sandbox to avoid surprise during a real upgrade.

[Overview](#overview) | [How to use](#how-to-use) | [Getting help](#getting-help) | [Caveats](#caveats)

## Overview

A tool/sandbox for testing Immich version upgrades.

This tool automates validating upgrade paths:
- It deploys the baseline (initial) version.
- You do initial setup and add some files to that baseline setup.
- Then it creates a backup.
- Next, one by one, it tries requested upgrade paths.
  - Each time from a fresh baseline instance restored from backup.
  - Currently it tests two upgrade scenarios: (1) new version + old compose, (2) new version + new compose.
  - Apart from that, other modifications are possible in principle (e.g. testing custom changes in docker compose file) but not implemented yet.
- After each upgrade it pauses and waits until you interact with the upgraded instance (check UI and logs) to validate the upgrade outcome.

## How to use

1. Download [test-upgrade.sh](https://raw.githubusercontent.com/skatsubo/immich-upgrade-lab/refs/heads/main/test-upgrade.sh) from Github and make the script executable: `chmod +x path/to/test-upgrade.sh`
2. Go to an empty directory.
3. Run the script with two arguments: "from" and "to" versions for testing upgrade between.

Example:

```sh
# test upgrade from v1.123.0 to v1.132.3
./test-upgrade.sh v1.123.0 v1.132.3
```

## Getting help

Check the usage instructions by providing `--help / -h` or simply run it without arguments:

```
/path/to/test-upgrade.sh --help

Immich upgrade in a sandbox

Performs upgrade from version ver1 to version ver2 in a sandbox.
It tests two scenarios: (1) new version + old compose, (2) new version + new compose.

Usage:
  ./test-upgrade.sh <ver1> <ver2>                # Test upgrades from version1 to version2
  ./test-upgrade.sh --from <ver1> --to <ver2>    # Test upgrades from version1 to version2 (flags form)
  ./test-upgrade.sh --help                       # Show this help

Example:
  ./test-upgrade.sh v1.123.0 v1.132.3
  ./test-upgrade.sh --from v1.123.0 --to v1.132.3
```

## Caveats

This is an early version, PoC for https://github.com/immich-app/immich/discussions/20847.
