#!/usr/bin/env bash
# Boot an AIL kernel image under QEMU and summarise its JSON-lines trace.
# Usage: tools/kernel/run.sh IMAGE.iso [TIMEOUT_S]   (runs on Kaleb's machines, not in cloud containers)
# The kernel prints one JSON object per line on COM1 and exits through the
# isa-debug-exit device: the exit status is (code << 1) | 1, so success (code 0) is 1.
set -u
img=${1:?usage: run.sh IMAGE.iso [TIMEOUT_S]}
secs=${2:-60}
out=$(mktemp)
trap 'rm -f "$out"' EXIT
accel=tcg
[ -w /dev/kvm ] && accel=kvm
timeout "$secs" qemu-system-x86_64 -accel "$accel" -m 256M -cdrom "$img" \
  -display none -no-reboot -serial "file:$out" \
  -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
  $( [ "$accel" = tcg ] && echo "-icount shift=auto" )
rc=$?
grep '^{' "$out"
python3 -I - "$out" "$rc" "$accel" <<'PY'
import json, sys
ev = [json.loads(l) for l in open(sys.argv[1]) if l.startswith("{")]
done = [e for e in ev if e.get("ev") == "done"]
gcs = [e for e in ev if e.get("ev") == "gc"]
print(json.dumps({"ev": "run", "qemu_rc": int(sys.argv[2]), "accel": sys.argv[3],
                  "gc_events": len(gcs), "done": bool(done),
                  "panics": done[-1].get("panics") if done else None}))
sys.exit(0 if done and done[-1].get("panics") == 0 and sys.argv[2] == "1" else 1)
PY
