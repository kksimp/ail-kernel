#!/usr/bin/env bash
# Run the kernel job on ail-linux from the designer's Mac, in one command (from this repo's root):
#   tools/kernel/run-remote.sh [AIL_SHA] [AIL_REPO]     (arguments go to tools/kernel/job.sh)
# KERNEL_HOST overrides the host (default kaleb@192.168.4.145, reached by ssh key).
# ail-linux can fetch kksimp/ail only, so this checkout is copied there with rsync (to ~/ail-kernel,
# without .git and reports/). The job's output goes to reports/job-last.log; its report is copied to
# reports/ and printed. The exit status is the job's (0 green, 1 RED, 2 or 255 could not run).
set -u
K=$(cd "$(dirname "$0")/../.." && pwd)
HOST=${KERNEL_HOST:-kaleb@192.168.4.145}
OPTS="-o BatchMode=yes -o ConnectTimeout=10"
mkdir -p "$K/reports"
# shellcheck disable=SC2086 # OPTS is split on purpose.
ssh $OPTS "$HOST" 'command -v rsync >/dev/null && mkdir -p ail-kernel' \
  || { echo "cannot reach $HOST over ssh, or it has no rsync" >&2; exit 2; }
# shellcheck disable=SC2086
rsync -az --delete --exclude .git --exclude reports -e "ssh $OPTS" "$K/" "$HOST:ail-kernel/" \
  || { echo "rsync to $HOST failed" >&2; exit 2; }
rev=$(git -C "$K" rev-parse --short HEAD 2>/dev/null || echo unknown)
[ -n "$(git -C "$K" status --porcelain 2>/dev/null)" ] && rev="$rev+dirty"
args=""
[ $# -gt 0 ] && args=$(printf '%q ' "$@")
echo "running the kernel job on $HOST (log: reports/job-last.log)"
# shellcheck disable=SC2086
ssh $OPTS "$HOST" "cd ail-kernel && rm -f reports/kernel-*.txt && KERNEL_REV=$rev tools/kernel/job.sh $args" \
  >"$K/reports/job-last.log" 2>&1
rc=$?
# shellcheck disable=SC2086
f=$(ssh $OPTS "$HOST" 'ls -t ail-kernel/reports/kernel-*.txt 2>/dev/null | head -1')
# shellcheck disable=SC2086
if [ -n "$f" ] && scp -q $OPTS "$HOST:$f" "$K/reports/"; then
  echo "== reports/$(basename "$f")"
  cat "$K/reports/$(basename "$f")"
else
  echo "no report came back (ssh exit $rc); the job's output:" >&2
  tail -40 "$K/reports/job-last.log" >&2
  [ "$rc" -eq 0 ] && rc=2
fi
exit "$rc"
