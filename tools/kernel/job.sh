#!/usr/bin/env bash
# The kernel job (K0; ADR 0953 in kksimp/ail). Runs on ail-linux (Linux x86-64); the Mac starts it
# with tools/kernel/run-remote.sh.
# Usage: tools/kernel/job.sh [AIL_SHA] [AIL_REPO]
#   AIL_SHA   the ail commit to build with (default: this repo's .ail-version)
#   AIL_REPO  a clone of kksimp/ail on this host (default: $HOME/ail; cloned if missing)
# Steps: a detached worktree of AIL_REPO at AIL_SHA, the stage-2 compiler, k0.ail for x86_64-none
# (readelf), the normal Linux target (examples/hello.ail), then, if qemu-system-x86_64, xorriso and
# limine exist, an ISO (mkiso.sh) booted under QEMU (run.sh). Failures are `RED ...` lines with a log
# tail. The last line is KERNEL DONE. The report is $W/report.txt, copied to reports/kernel-<sha8>.txt.
# Exit status: 0 green, 1 any RED.
set -u
K=$(cd "$(dirname "$0")/../.." && pwd)
SHA=${1:-$(tr -d '[:space:]' 2>/dev/null <"$K/.ail-version")}
REPO=${2:-$HOME/ail}
W=$(mktemp -d); export TMPDIR=$W; R=$W/report.txt; WT=$W/ail
red=0; sha8=$(printf '%.8s' "${SHA:-none}")
say() { echo "$*" | tee -a "$R"; }
# fail WHAT [LOG]: a RED line, then the log's tail.
fail() { red=1; say "RED $1"; [ -n "${2:-}" ] && [ -f "$2" ] && tail -40 "$2" | tee -a "$R"; }
finish() {
  say "KERNEL DONE"
  mkdir -p "$K/reports" && cp "$R" "$K/reports/kernel-$sha8.txt"
  exit "$red"
}
cleanup() { [ -d "$WT" ] && { git -C "$REPO" worktree remove --force "$WT" 2>/dev/null; git -C "$REPO" worktree prune 2>/dev/null; }; }
trap cleanup EXIT

say "== host $(uname -sm) ail ${SHA:-?} kernel ${KERNEL_REV:-$(git -C "$K" rev-parse --short HEAD 2>/dev/null || echo unknown)} $(date -u +%FT%TZ)"
[ -n "$SHA" ] || { fail "no AIL_SHA given and no .ail-version"; finish; }
if [ ! -d "$REPO/.git" ]; then
  git clone -q "${AIL_URL:-git@github.com:kksimp/ail.git}" "$REPO" >"$W/clone.log" 2>&1 || { fail "clone ail into $REPO" "$W/clone.log"; finish; }
fi
git -C "$REPO" fetch -q origin >"$W/fetch.log" 2>&1 || say "-- warning: git fetch failed; using local objects"
full=$(git -C "$REPO" rev-parse --verify -q "$SHA^{commit}") || { fail "ail commit $SHA not found in $REPO" "$W/fetch.log"; finish; }
sha8=${full:0:8}
git -C "$REPO" worktree add -q --detach "$WT" "$full" >"$W/wt.log" 2>&1 || { fail "worktree at $sha8" "$W/wt.log"; finish; }

cd "$WT" || { fail "cd $WT"; finish; }
./ail build compiler/main.ail -o "$W/stage2" >"$W/s2.log" 2>&1 || { fail "stage2 build" "$W/s2.log"; finish; }
export AIL_ROOT=$WT
"$W/stage2" build "$K/examples/kernel/k0.ail" --target x86_64-none -o "$W/k0.elf" >"$W/k0.log" 2>&1 \
  || { fail "build k0" "$W/k0.log"; finish; }
say "-- k0.elf $(wc -c <"$W/k0.elf") bytes"
readelf -lh "$W/k0.elf" 2>&1 | head -30 | tee -a "$R"

# Regression: the normal Linux target still builds and runs.
if "$W/stage2" build examples/hello.ail -o "$W/hello" >"$W/h.log" 2>&1 && "$W/hello" >"$W/hello.txt" 2>&1; then
  head -2 "$W/hello.txt" | tee -a "$R"
  [ -f examples/hello.out ] && ! cmp -s examples/hello.out "$W/hello.txt" && fail "hello output differs from examples/hello.out" "$W/hello.txt"
else
  fail "hello (linux target)" "$W/h.log"
fi

if command -v qemu-system-x86_64 >/dev/null && command -v xorriso >/dev/null && command -v limine >/dev/null; then
  if "$K/tools/kernel/mkiso.sh" "$W/k0.elf" "$W/k0.iso" >"$W/iso.log" 2>&1 && [ -f "$W/k0.iso" ]; then
    "$K/tools/kernel/run.sh" "$W/k0.iso" 60 >"$W/boot.log" 2>&1; rc=$?
    tee -a "$R" <"$W/boot.log"
    [ "$rc" -eq 0 ] || { red=1; say "RED boot (run.sh exit $rc)"; }
  else
    fail "mkiso" "$W/iso.log"
  fi
else
  say "SKIP boot: need qemu-system-x86_64, xorriso, limine"
fi
finish
