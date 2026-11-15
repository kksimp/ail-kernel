# Status (2026-11-15)

Resumed against ail v0.1.0 (released 2026-11-15). The pause noted on
2026-11-11 is over.

## Done
- Design: [docs/design/kernel-poc.md](docs/design/kernel-poc.md). ADR 0953
  (freestanding targets, Proposed) is in kksimp/ail.
- Compiler slice G1-G3 (`x86_64-none` target and entry, serial/arena runtime,
  port I/O): ail branch `claude/project-thread-tf8k0t`, v0.1.0 plus the
  freestanding-target patch. A copy is in `patches/`.
- K0 example: `examples/kernel/k0.ail` (two JSON lines on COM1, then exit).
- Runner: `tools/kernel/job.sh` (on ail-linux), `run-remote.sh` (from the
  Mac), `mkiso.sh` (Limine ISO), `run.sh` (QEMU boot and trace summary).

**Nothing has been compiled or booted** until the first job report in
`reports/` says otherwise. No GC pause numbers exist.

## Not done
- `aarch64-none` twin (ADR 0008 lockstep).
- `@interrupt fn` (G4), `@layout(c)` (G5), no-SIMD mode (G6).
- Milestones K1-K5.

## Caveat
ail-linux has no KVM, so QEMU runs under TCG: its timings show shape only.

## How to run
From this repository's root on the Mac:

```sh
tools/kernel/run-remote.sh            # ail commit from .ail-version
tools/kernel/run-remote.sh SHA        # another ail commit
```

It copies this checkout to ail-linux, runs the job, and prints the report
(also saved as `reports/kernel-<sha8>.txt`). The last line is `KERNEL DONE`;
any `RED` line is a failure.
