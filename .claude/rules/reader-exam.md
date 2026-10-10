---
paths:
  - "tests/reader-exam/**"
  - "payload/context/checks-*.md"
  - "agents-src/blocks/checks-*.md"
  - "agents-src/templates/context/checks-*.md.tmpl"
---

# The reader exam

`tests/reader-exam/` holds defects that really got past a reader, rebuilt small, and the
protocol for sitting them (its `README.md`).

- **An escaped defect becomes a sample before the wave that found it closes.** When a
  defect is found that a reader was dealt and passed (a later reader, the walk, the audit or
  a user found it instead), add it under `tests/reader-exam/samples/` before that wave's
  close-out, with a row in the README naming the record it came from. Close-out does not pass
  over it: the sample is the only way the next change to a checks file is held to it. The
  defect must be one the priority table sends to fix at an honest rating; one it would defer or
  note at any honest rating is no sample.
- **A sample is passed on a declaration.** A defect sample passes only when the reader's record
  carries a `finding:` line naming the planted defect's file at a severity and reach the
  priority table sends to fix; a record that only describes the defect, or rates it where the
  table defers or notes it, fails (`score.sh`, spec D22). The key's `finding-file:` and
  `finding-rating:` lines say which.
- **A changed checks file is sat again.** `tests/exam/reader-exam.sh` is red when one of the
  three checks files it names differs from the hashes of the latest sitting, and when that
  sitting lacks a `met` result for any sample. An edit to a checks file's block or template
  changes the file too. The fix is a sitting, appended to `sittings.md`, never a hash retyped
  by hand: a hash with no readers behind it is the pin lying. When the files change in a wave
  whose sitting is a later row's, the sitting carries one `stale:` line naming the old and the new
  hash of each file that changed, and the pin passes as history until that sitting is sat; an
  unmarked drift stays red.
- **A sample gives nothing away.** No comment, file name or commit message in the sample
  names its defect; the sample's own name stays behind when it is materialized, and
  `materialize.sh` refuses a destination whose path names it.
