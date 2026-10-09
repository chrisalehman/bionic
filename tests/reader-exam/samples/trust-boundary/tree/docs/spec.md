# Spec — archiving landed branches

## Requirements

**REQ-1.** A landed branch's tip is kept as a tarball under `dist/`.

- **AC-1.1.** `bin/archive.sh <branch>` writes `dist/<branch>.tar` holding the files of the
  branch's tip. Fails when: the tarball is not written, or lacks a file the tip holds.
- **AC-1.2.** A branch name with a `/` in it makes one file in `dist/`, the `/` written as `-`.
  Fails when: the tarball lands in a subdirectory of `dist/`.

## Design

- **D1.** `lib/archive.sh` `archive_branch <repo> <branch> <outdir>` archives the tip of
  `<branch>` with `git archive`. `bin/archive.sh` calls it for the current checkout. (REQ-1)
