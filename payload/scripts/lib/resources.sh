# payload/scripts/lib/resources.sh — ONE READER FOR "how much machine is there, and how
# much of it is left".
#
# WHAT IT OWNS. Three questions, kept apart on purpose:
#
#   resources_probe                          what this machine IS      (facts)
#   resources_budget <cores> <mem> <disk>    how wide a wave may run   (a ceiling)
#   resources_pressure <cores>               how it is doing right now (a live reading)
#
# WHY IT EXISTS (spec AC-24, wave-bionic-1.4.0-update). Fan-out width was a number a human
# guessed and then restated into every brief. It drifted, and it was wrong in both
# directions: too high on a small machine (a kernel SIGKILL, below) and needlessly low on a
# large one. The cure is to derive it once, from facts, and read it from where it was
# written — never to re-derive it from whatever the machine happens to be doing.
#
# THE ONE RULE THAT SHAPES EVERY CONSTANT HERE: MEMORY IS HARD, COMPUTE IS SOFT
# (user 2026-09-02, "1 amended"). Over-subscribing cores costs wall time and nothing else.
# Over-subscribing memory destroys work: the measured failure is a kernel SIGKILL, seven
# concurrent suites on an 8 GB machine driving free memory to ~188 MB and a suite dying
# mid-run (tests/run.sh:63-68, W7 assumption A4.2). So the memory term is measured and
# binding; the compute term is a placeholder that degenerates to `cores` until AC-32's live
# run at the wave head measures it.
#
# THE BUDGET IS A CEILING, NOT A CONTROLLER (design-ledger S6, S7). `resources_budget` is a
# PURE function of its three arguments — it opens no file, runs no command, reads no
# environment variable. That is what makes it re-derivable and auditable: the same machine
# facts always answer the same budget. `resources_pressure` is the separate live question,
# and the only thing a caller may do with it is HOLD, NARROW, or (at the kill floor) stop
# something. Pressure never raises or lowers the ceiling; a moving ceiling is precisely the
# drift class this file was written to remove.
#
# WHO READS IT. hooks/preflight-probe.sh (records probe + budget into the version-2
# attestation), the canonical-sdlc Step 0 display and the plan header it writes, the
# dispatch wall's budget arm, `session-poker.sh tick` (FILL/HOLD/NARROW/EMERGENCY), and
# doctor's resources section. Every one of them READS; none of them re-derives.
#
# BASH 3.2. No associative arrays, no `${var^^}`, no `mapfile`, and no floating-point
# arithmetic — bash has none. The two non-integer constants (1.2 GB per suite, 0.5 GB per
# tree) are converted to hundredths by `_res_hundredths` and the whole budget is computed in
# integers; awk appears exactly once, for the one genuine float comparison in
# `resources_pressure` (load_1m against cores × 1.5).
#
# EVERY CONSTANT CARRIES ITS DATUM (AC-24). A number with no provenance is the thing this
# file exists to replace, so the comment beside each assignment is part of the contract and
# tests/resources.test.sh asserts its presence.
#
# [WALL: tests/resources.test.sh]

# ─────────────────────────────────────────────────────────────────── constants

# Memory the machine must keep for itself — the OS, the editor, the agent processes, and
# the headroom between "slow" and "the kernel starts killing things".
MEM_RESERVE_GB=2       # datum: 2026-08 measurement, tests/run.sh:63-68 — the 8 GB machine
                       # died at ~188 MB free, so a 2 GB floor is the nearest round reserve
                       # that keeps the kill point out of reach.

# What one concurrent test suite costs in resident memory. THE BINDING TERM.
MEM_PER_SUITE_GB=1.2   # datum: 8 GB, 7 concurrent suites, ~188 MB free, kernel SIGKILL,
                       # tests/run.sh:63-68 — (8 − 2) GB across 7 suites is ~0.86 GB each
                       # with nothing left; 1.2 GB is that measurement with headroom.

# What one concurrent suite costs in cores. THE SOFT TERM, measured once at the wave head
# (AC-32): the whole `tests/run.sh` at 18 jobs, alone on an 18-core M5 Max, averaged 1.61
# cores over its 8m07s wall (user 279.27 s + sys 505.57 s over real 487.38 s) — the runner
# is spawn- and sleep-bound, not CPU-bound. Read as the per-suite constant the formula
# names, it makes the compute term floor(18/1.61) = 11 concurrent full suites here, which
# is the conservative side of the Batch-0 datum (six concurrent full suites starved).
CORES_PER_SUITE=1.61   # measured 2026-09-03 at BIONIC_TEST_JOBS=18, user+sys/wall over
                       # tests/run.sh at 97afec9: 784.84 s / 487.38 s
                       # (record/wave-1.4.0/step5-full-suite-report.md)

# Disk a checked-out worktree costs. Trees are cheap; this term only binds on a full disk.
DISK_PER_TREE_GB=0.5   # datum: 2026-09-02, this repo — a `git worktree add` checkout of
                       # bionic measures well under 100 MB; 0.5 GB is that rounded up five
                       # times over to cover build artefacts and a venv.

# Writers exceed suites because not every writer is running a suite at once — most of a
# writer's life is reading, editing and committing.
WRITERS_EXTRA=4        # datum: 2026-09-02 stand-up — hand-derived budget for this machine
                       # was writers 22 against suites 18, the ratio this wave is running.

# BIONIC_TEST_JOBS bounds. The floor keeps a 1-core machine from serializing to a crawl; the
# ceiling is where added width stopped paying on the measured runs.
TEST_JOBS_MIN=4        # datum: tests/run.sh:63-68 — 4 was "the width with headroom" on the
                       # 8 GB measurement, and is the documented pre-2026-08-22 default.
TEST_JOBS_MAX=24       # datum: 2026-08-22 (ef23f75) raised the default to 8 with the note
                       # that BIONIC_TEST_JOBS exists "for a machine with less or more"; 24
                       # is three times that, past any width measured to help.

# Live worktree bounds. The floor keeps the lease mechanism usable on a small disk; the
# ceiling is a sprawl guard, not a resource one.
WORKTREES_MIN=2        # datum: 2026-09-02 design-ledger C1 — a lease needs at least the
                       # tree being landed plus the next one being cut.
WORKTREES_MAX=32       # datum: 2026-09-02 stand-up — hand-derived worktrees 32 on a 1.7 TiB
                       # disk, where the disk term (3400) is meaningless and sprawl is the
                       # real limit.

# Concurrent writer bounds, same shape and the same reasoning as the worktree pair.
WRITERS_MIN=2          # datum: 2026-09-02 — one writer is not a fan-out; two is the floor
                       # at which the dispatch wall's budget arm means anything.
WRITERS_MAX=32         # datum: 2026-09-02 stand-up — the hand-derived ceiling, and the
                       # point past which an orchestrator cannot read the returns.

# ── pressure thresholds (AC-30). These decide HOLD and EMERGENCY, never the ceiling.

HOLD_FREE_MB=1024      # datum: half MEM_RESERVE_GB — the reserve is the line the budget was
                       # built to protect, so eating half of it is the warning, not the
                       # emergency.
HOLD_LOAD_FACTOR=1.5   # datum: 2026-09-02 — load_1m above 1.5 × cores is sustained
                       # oversubscription rather than a burst; below it, queueing is normal
                       # for a machine running suites.
EMERGENCY_FREE_MB=256  # datum: kill at ~188 MB (tests/run.sh:63-68) — the floor sits just
                       # above the measured kernel SIGKILL point, so the tick acts before
                       # the kernel does.

# ─────────────────────────────────────────────────────────── integer arithmetic helpers

# bash has no floats. Every non-integer constant above is converted here to HUNDREDTHS, and
# the budget arithmetic below is plain integer division on those. Two decimal places is
# enough for every constant this file has and for the measured CORES_PER_SUITE that AC-32
# will write in.
_res_hundredths() {  # <decimal string> -> integer hundredths ("1.2" -> 120, "0.5" -> 50)
  local v="$1" int frac
  case "$v" in
    *.*) int="${v%%.*}"; frac="${v#*.}" ;;
    *)   int="$v";       frac="" ;;
  esac
  [ -n "$int" ] || int=0
  frac="${frac}00"
  frac="${frac:0:2}"
  # 10# forces base ten: an unprefixed "08" is an invalid octal literal to bash.
  printf '%s' "$(( int * 100 + 10#$frac ))"
}

_res_clamp() {  # <n> <min> <max>
  local n="$1"
  [ "$n" -lt "$2" ] && n="$2"
  [ "$n" -gt "$3" ] && n="$3"
  printf '%s' "$n"
}

_res_is_uint() {  # <string> — a non-negative decimal integer and nothing else
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *)           return 0 ;;
  esac
}

# ─────────────────────────────────────────────────────────────────── resources_probe

_res_free_mb() {  # currently reclaimable memory, in MB
  # The override is what makes tests/resources.test.sh hermetic: a suite that had to wait
  # for the machine to be quiet would be a suite nobody runs. It is read here rather than
  # inside resources_pressure so the probe and the pressure reading agree.
  if [ -n "${BIONIC_PROBE_FREE_MB:-}" ]; then
    printf '%s' "${BIONIC_PROBE_FREE_MB}"
    return 0
  fi
  case "$(uname -s 2>/dev/null)" in
    Darwin)
      # free + speculative + inactive is macOS's nearest equivalent to Linux MemAvailable:
      # all three are reclaimable without swapping. `Pages free` ALONE is not the reading to
      # take — a healthy macOS keeps it small on purpose, and a HOLD on that number would
      # fire constantly on an idle machine.
      vm_stat 2>/dev/null | awk '
        /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") { ps = $(i+1); break } }
        /^Pages free:/        { f = $3 }
        /^Pages speculative:/ { s = $3 }
        /^Pages inactive:/    { n = $3 }
        END {
          gsub(/\./, "", f); gsub(/\./, "", s); gsub(/\./, "", n)
          if (ps == "" || ps + 0 == 0) ps = 4096
          printf "%d", ((f + s + n) * ps) / 1048576
        }'
      ;;
    Linux)
      # MemAvailable is the kernel's own answer and is preferred over MemFree for exactly
      # the reason above. Older kernels without it fall back to MemFree + Cached.
      awk '
        /^MemAvailable:/ { avail = $2 }
        /^MemFree:/      { free  = $2 }
        /^Cached:/       { if (cached == "") cached = $2 }
        END { printf "%d", (avail != "" ? avail : free + cached) / 1024 }' /proc/meminfo 2>/dev/null
      ;;
    *) printf '0' ;;
  esac
}

_res_load_1m() {  # one-minute load average
  if [ -n "${BIONIC_PROBE_LOAD_1M:-}" ]; then
    printf '%s' "${BIONIC_PROBE_LOAD_1M}"
    return 0
  fi
  case "$(uname -s 2>/dev/null)" in
    Darwin) sysctl -n vm.loadavg 2>/dev/null | awk '{ print $2 }' ;;
    Linux)  awk '{ print $1 }' /proc/loadavg 2>/dev/null ;;
    *)      printf '0' ;;
  esac
}

# resources_probe — the five machine facts, one line, `key=value` space-separated.
#
#   cores=<n> mem_gb=<n> disk_free_gb=<n> load_1m=<f> os=<darwin|linux>
#
# Read the answer BY KEY, never by position: this record's field order is stable today and
# a later field would be appended, but every reader in the repo (the attestation schema
# included) is written key-first for exactly that reason.
#
# disk_free_gb is measured at the CURRENT DIRECTORY, because the thing it bounds is
# worktrees, and worktrees are cut beside the repo the caller is standing in.
resources_probe() {
  local os cores mem_gb disk_free_gb load_1m

  case "$(uname -s 2>/dev/null)" in
    Darwin) os=darwin ;;
    Linux)  os=linux  ;;
    *)      os=unknown ;;
  esac

  case "$os" in
    darwin)
      cores="$(sysctl -n hw.ncpu 2>/dev/null)"
      mem_gb="$(sysctl -n hw.memsize 2>/dev/null)"
      # GiB, not GB: hw.memsize is a byte count of physical RAM, and 128 GiB is what a
      # "128 GB" machine reports. Integer division floors, which is the safe direction.
      _res_is_uint "$mem_gb" && mem_gb=$(( mem_gb / 1073741824 )) || mem_gb=0
      # -P forces the POSIX one-line-per-filesystem format, so a long device name cannot
      # wrap and shift the column this reads. -g is 1 GiB blocks; column 4 is Available.
      disk_free_gb="$(df -Pg . 2>/dev/null | tail -1 | awk '{ print $4 }')"
      ;;
    linux)
      cores="$(nproc 2>/dev/null)"
      # MemTotal is in kB; round to the nearest GiB rather than flooring, so a 16 GB machine
      # reporting 15.6 GiB of usable RAM does not budget as a 15 GB one.
      mem_gb="$(awk '/^MemTotal:/ { printf "%d", ($2 + 524288) / 1048576 }' /proc/meminfo 2>/dev/null)"
      disk_free_gb="$(df -BG -P . 2>/dev/null | tail -1 | awk '{ v = $4; sub(/G$/, "", v); print v }')"
      ;;
    *)
      cores=1; mem_gb=1; disk_free_gb=0
      ;;
  esac

  load_1m="$(_res_load_1m)"

  # A probe that cannot read a fact answers a SAFE fact, never an empty field: an empty
  # field would flow into the attestation and out the other side as a budget of nothing.
  _res_is_uint "$cores"        || cores=1
  [ "$cores" -ge 1 ]           || cores=1
  _res_is_uint "$mem_gb"       || mem_gb=1
  [ "$mem_gb" -ge 1 ]          || mem_gb=1
  _res_is_uint "$disk_free_gb" || disk_free_gb=0
  case "${load_1m:-}" in
    ''|*[!0-9.]*) load_1m=0 ;;
  esac

  printf 'cores=%s mem_gb=%s disk_free_gb=%s load_1m=%s os=%s\n' \
    "$cores" "$mem_gb" "$disk_free_gb" "$load_1m" "$os"
}

# ────────────────────────────────────────────────────────────────── resources_budget

# resources_budget <cores> <mem_gb> <disk_free_gb> — the ceiling, one line:
#
#   writers=<n> suites=<n> worktrees=<n> test_jobs=<n>
#
#   suites    = max(1, min(floor((mem_gb − MEM_RESERVE_GB) / MEM_PER_SUITE_GB),
#                          floor(cores / CORES_PER_SUITE)))
#   test_jobs = clamp(cores, TEST_JOBS_MIN, TEST_JOBS_MAX)
#   worktrees = clamp(floor(disk_free_gb / DISK_PER_TREE_GB), WORKTREES_MIN, WORKTREES_MAX)
#   writers   = clamp(suites + WRITERS_EXTRA, WRITERS_MIN, WRITERS_MAX)
#
# min over resources of "available ÷ unit cost" — the memory term measured and binding, the
# compute term soft until AC-32, the disk term bounding leases. `max(1, …)` is not
# cosmetic: a 4 GB machine's memory term is 1 and a 3 GB machine's is 0, and a budget of
# zero suites is a machine that can never prove anything.
#
# PURE. No file, no command, no environment variable — pass the probe's numbers in.
resources_budget() {
  if [ "$#" -ne 3 ]; then
    printf 'resources_budget: need <cores> <mem_gb> <disk_free_gb>, got %s argument(s)\n' "$#" >&2
    return 2
  fi
  local cores="$1" mem_gb="$2" disk_gb="$3"
  local a
  for a in "$cores" "$mem_gb" "$disk_gb"; do
    if ! _res_is_uint "$a"; then
      printf 'resources_budget: not a non-negative integer: %s\n' "$a" >&2
      return 2
    fi
  done

  local mem_avail=$(( mem_gb - MEM_RESERVE_GB ))
  [ "$mem_avail" -lt 0 ] && mem_avail=0

  local per_suite per_core per_tree
  per_suite="$(_res_hundredths "$MEM_PER_SUITE_GB")"
  per_core="$(_res_hundredths "$CORES_PER_SUITE")"
  per_tree="$(_res_hundredths "$DISK_PER_TREE_GB")"
  # A constant edited to zero would divide by zero rather than say so. Refuse instead.
  if [ "$per_suite" -le 0 ] || [ "$per_core" -le 0 ] || [ "$per_tree" -le 0 ]; then
    printf 'resources_budget: a per-unit constant is zero or negative; refusing to divide\n' >&2
    return 2
  fi

  local mem_term=$(( mem_avail * 100 / per_suite ))
  local cpu_term=$(( cores * 100 / per_core ))
  local suites="$mem_term"
  [ "$cpu_term" -lt "$suites" ] && suites="$cpu_term"
  [ "$suites" -lt 1 ] && suites=1

  local worktrees test_jobs writers
  worktrees="$(_res_clamp "$(( disk_gb * 100 / per_tree ))" "$WORKTREES_MIN" "$WORKTREES_MAX")"
  test_jobs="$(_res_clamp "$cores" "$TEST_JOBS_MIN" "$TEST_JOBS_MAX")"
  writers="$(_res_clamp "$(( suites + WRITERS_EXTRA ))" "$WRITERS_MIN" "$WRITERS_MAX")"

  printf 'writers=%s suites=%s worktrees=%s test_jobs=%s\n' \
    "$writers" "$suites" "$worktrees" "$test_jobs"
}

# ──────────────────────────────────────────────────────────────── resources_pressure

# resources_pressure <cores> — the live reading, one line:
#
#   state=<ok|hold|emergency> free_mb=<n> load_1m=<f>
#
# The two readings are echoed alongside the state so a caller can PRINT THE MEASUREMENT
# rather than the verdict alone — AC-30 requires `HOLD <measurement>`, because a HOLD with
# no number is indistinguishable from a bug.
#
# Precedence: emergency, then the memory hold, then the load hold. Memory outranks load
# because memory is what kills; a busy machine finishes late, a starved one loses work.
#
# The one float comparison in this file is the load test, and it is done in awk. Both
# readings honour BIONIC_PROBE_FREE_MB / BIONIC_PROBE_LOAD_1M so the thresholds can be
# driven from either side without waiting on a real machine to get into trouble.
resources_pressure() {
  local cores="${1:-}"
  if ! _res_is_uint "$cores" || [ "$cores" -lt 1 ]; then
    printf 'resources_pressure: need <cores> as a positive integer, got: %s\n' "${1:-}" >&2
    return 2
  fi

  local free_mb load_1m state
  free_mb="$(_res_free_mb)"
  load_1m="$(_res_load_1m)"
  _res_is_uint "$free_mb" || free_mb=0
  case "${load_1m:-}" in
    ''|*[!0-9.]*) load_1m=0 ;;
  esac

  state=ok
  if [ "$free_mb" -lt "$EMERGENCY_FREE_MB" ]; then
    state=emergency
  elif [ "$free_mb" -lt "$HOLD_FREE_MB" ]; then
    state=hold
  elif awk -v l="$load_1m" -v c="$cores" -v f="$HOLD_LOAD_FACTOR" \
         'BEGIN { exit !(l + 0 > c * f) }'; then
    state=hold
  fi

  printf 'state=%s free_mb=%s load_1m=%s\n' "$state" "$free_mb" "$load_1m"
}
