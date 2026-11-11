#!/usr/bin/env bash
# KERNEL lane job (G1/G2/G3, ADR 0953). Usage: job.sh SHA [REPO] on an idle ail-linux (x86-64).
# ready-check, stage-2 build, compile examples/kernel/k0.ail for x86_64-none, then (if limine+xorriso+qemu exist)
# make an ISO and boot it. Last line is KERNEL DONE. Copy $W/report.txt back as kernel-<sha8>.txt.
set -u
SHA=${1:?sha}; REPO=${2:-$HOME/ail}
W=$(mktemp -d); export TMPDIR=$W; R=$W/report.txt
say() { echo "$*" | tee -a "$R"; }
cd "$REPO" || exit 2
git fetch -q origin 2>/dev/null
git worktree add -q --detach "$W/new" "$SHA" || { echo "worktree failed"; exit 2; }
cd "$W/new"
say "== host $(uname -sm) $SHA $(date -u +%FT%TZ)"
tools/gate/ready-check.sh origin/main 2>&1 | tail -15 | tee -a "$R"
./ail build compiler/main.ail -o "$W/stage2" >"$W/s2.log" 2>&1 || { say "RED stage2 build"; tail -40 "$W/s2.log" | tee -a "$R"; say "KERNEL DONE"; exit 1; }
AIL_ROOT="$W/new" "$W/stage2" build examples/kernel/k0.ail --target x86_64-none -o "$W/k0.elf" >"$W/k0.log" 2>&1 \
  || { say "RED build k0"; tail -40 "$W/k0.log" | tee -a "$R"; say "KERNEL DONE"; exit 1; }
say "-- k0.elf $(wc -c <"$W/k0.elf") bytes"; readelf -lh "$W/k0.elf" 2>&1 | head -30 | tee -a "$R"
# Regression: the normal Linux target still builds and runs.
AIL_ROOT="$W/new" "$W/stage2" build examples/hello.ail -o "$W/hello" >"$W/h.log" 2>&1 && "$W/hello" | head -2 | tee -a "$R" || say "RED hello (linux target)"
if command -v qemu-system-x86_64 >/dev/null && command -v xorriso >/dev/null; then
  tools/kernel/mkiso.sh "$W/k0.elf" "$W/k0.iso" 2>&1 | tail -5 | tee -a "$R"
  [ -f "$W/k0.iso" ] && tools/kernel/run.sh "$W/k0.iso" 30 2>&1 | tee -a "$R"
else say "SKIP boot: need qemu-system-x86_64, xorriso, limine"; fi
say "KERNEL DONE"
