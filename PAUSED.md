# PAUSED (2026-11-11)

Paused until ail 0.1.0 is released (Kaleb's call). No jobs are scheduled.

## Where it stands
- Design, ADR 0953 (Proposed), runner scripts and the first compiler slice (G1 `x86_64-none` target and entry, G2 serial/arena runtime, G3 port I/O prims) are written.
- **Nothing has ever been compiled or booted.** No GC pause numbers exist.
- Not done: `aarch64-none` twin (ADR 0008 lockstep), `@interrupt fn`, no-SIMD mode, milestones K1-K5.
- Timing caveat: ail-linux has no KVM, so QEMU timings show shape only.

## First step on resume
1. In kksimp/ail, rebase `claude/project-thread-egc4ma` (or apply `patches/ail-compiler-x86_64-none.patch`) onto the then-current main as a compiler-only branch; drop the kernel files from it.
2. Adapt `tools/kernel/job.sh` so the kernel files come from this repo and the compiler from the ail checkout (it currently assumes both in one tree).
3. Run the job on ail-linux (qemu, xorriso, limine were installed 2026-11-09): build `k0.elf`, readelf, then boot. Fix whatever is RED.
