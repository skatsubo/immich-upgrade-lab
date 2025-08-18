# Immich upgrade lab

Test Immich upgrades in a sandbox to avoid surprise during a real upgrade.

[Overview](#overview) | [How to use](#how-to-use) | [Getting help](#getting-help) | [Caveats](#caveats)

## Overview

A tool/sandbox for testing Immich version upgrades.

This tool automates validation of upgrade paths: it deploys the initial version in a sandbox and performs an upgrade to the target version. (Post-upgrade e2e tests to be implemented in the future).

Step by step execution of the script:

1. Initial version.
The sandbox can be created from scratch (empty), from an existing snapshot, from data of an existing Immich instance (library, postgres).
The sandbox can be reviewed and configured or populated with assets before performing an upgrade.

- It deploys the initial version.
- You do initial setup and add some files to the sandbox.
- Then it creates a snapshot.

2. Refreshing the sandbox.

Before each upgrade test a fresh sandbox instance is created/restored from a snapshot (step 1).

3. Upgrade (to target version)

- Next, one by one, it tries requested upgrade paths in a sandbox.
  - Each time from a fresh test instance restored from snapshot.
  - Currently it tests two upgrade scenarios: (1) new version + old compose, (2) new version + new compose.
  - Apart from that, other modifications are possible in principle (e.g. testing custom changes in docker compose file) but not implemented yet.
- After each upgrade it pauses and waits until you interact with the upgraded instance (check UI and logs) to validate the upgrade outcome.

## How to use

Quick start:

1. Download [test-upgrade.sh](https://raw.githubusercontent.com/skatsubo/immich-upgrade-lab/refs/heads/main/test-upgrade.sh) from Github and make the script executable: `chmod +x path/to/test-upgrade.sh`
2. Go to an empty directory.
3. Run the script with two arguments: "from" and "to" versions for testing upgrade between. Follow the on-screen instructions.

Example:

```sh
# upgrade from v1.123.0 to v1.132.3
./test-upgrade.sh v1.123.0 v1.132.3
```

## Getting help

Check the usage instructions by providing `--help / -h` or simply run it without arguments:

```
/path/to/test-upgrade.sh --help

Immich upgrade in a sandbox

Performs upgrade from version ver1 to version ver2 in a sandbox.
It tests two upgrade scenarios: (1) new version + old compose, (2) new version + new compose.

The test instance (sandbox) can be created:
  - from scratch (empty) using default/release compose
  - from a previously created snapshot
  - using existing Immich instance's compose+data+postgres
By default, when no optional args are specified, the sandbox is created from this version's snapshot if exists, otherwise from scratch.

Both versions (from and to) are mandatory arguments.

Usage:
  ./test-upgrade.sh <ver1> <ver2>                   # Upgrade from version1 to version2
  ./test-upgrade.sh --from <ver1> --to <ver2>       # Upgrade from version1 to version2 (flags form)
  ./test-upgrade.sh <ver1> <ver2> [--args ...]      # Upgrade with extra args
  ./test-upgrade.sh --help                          # Show this help

Optional arguments:
  --from-compose <dir>    Use compose files from specified location when creating sandbox.
  --from-data <dir>       Use (copy) Immich data (library) from specified location when creating sandbox.
  --from-postgres <dir>   Use (copy) Postgres data from specified location when creating sandbox.

Examples:
  ./test-upgrade.sh v1.123.0 v1.132.3
  ./test-upgrade.sh --from v1.123.0 --to v1.132.3
```

## Caveats

This is an early version, PoC for https://github.com/immich-app/immich/discussions/20847.
