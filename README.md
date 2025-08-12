# immich-upgrade-lab

A tool/sandbox for testing Immich version upgrades.

Test Immich upgrades in a sandbox to avoid surprise during a real upgrade.

This tool automates validating upgrade paths:
- It deploys the baseline (initial) version.
- You do initial setup and add some files to that baseline setup.
- Then it creates a backup.
- Next, one by one, it tries requested upgrade paths.
  - Each time from a fresh baseline instance restored from backup.
  - Apart from the version change, other modifications are possible as well, e.g. for testing changes in docker compose file.
- After each upgrade it pauses and waits until you interact with the upgraded instance (UI, logs) to validate the upgrade outcome.
