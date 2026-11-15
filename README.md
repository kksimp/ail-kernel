# ail-kernel

A proof of concept for writing a kernel or driver in AIL with the garbage collector on. **Status: resumed against ail v0.1.0; nothing compiled or booted yet.** See [STATUS.md](STATUS.md).

Licence: AGPL-3.0 (see LICENSE), private, like the other app repos.

## Layout
- `docs/design/kernel-poc.md`: the design (GC with no OS, interrupts, DMA pinning, milestones K0-K5).
- ADR 0953 (freestanding targets, Proposed) lives in kksimp/ail, because it changes the language/compiler: `docs/decisions/0953-freestanding-targets-and-kernel-poc.md` on branch `claude/project-thread-tf8k0t`.
- `examples/kernel/k0.ail`: boot example (serial output).
- `tools/kernel/job.sh`: the job on ail-linux (stage-2 compiler, k0 for `x86_64-none`, Linux regression, ISO and boot).
- `tools/kernel/run-remote.sh`: runs that job from the Mac and fetches the report into `reports/` (ignored by git).
- `tools/kernel/mkiso.sh`, `tools/kernel/run.sh`: Limine ISO maker and QEMU runner.
- `patches/ail-compiler-x86_64-none.patch`: the compiler changes the kernel needs (freestanding `x86_64-none` target, runtime, port I/O). They belong in kksimp/ail and are kept here for reference only.
- `.ail-version`: the ail commit the kernel builds with: a commit of the ail branch `claude/project-thread-tf8k0t`, which is v0.1.0 plus the freestanding-target patch.

## Running
From the repository root on the Mac: `tools/kernel/run-remote.sh` (see [STATUS.md](STATUS.md)).

Imported from kksimp/ail `claude/project-thread-egc4ma` at f8e517f2 (based on main 3896938b). History of the three source commits stays there.
