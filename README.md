# ail-kernel

A proof of concept for writing a kernel or driver in AIL with the garbage collector on. **Status: PAUSED until ail 0.1.0 is released.** See [PAUSED.md](PAUSED.md).

Licence: AGPL-3.0 (see LICENSE), private, like the other app repos.

## Layout
- `docs/design/kernel-poc.md`: the design (GC with no OS, interrupts, DMA pinning, milestones K0-K5).
- ADR 0953 (freestanding targets, Proposed) lives in kksimp/ail, because it changes the language/compiler: `docs/decisions/0953-freestanding-targets-and-kernel-poc.md` on branch `claude/project-thread-egc4ma`.
- `examples/kernel/k0.ail`: boot example (serial output).
- `tools/kernel/{run,mkiso,job}.sh`: QEMU runner, Limine ISO maker, ail-linux job script.
- `patches/ail-compiler-x86_64-none.patch`: the compiler changes the kernel needs (freestanding `x86_64-none` target, runtime, port I/O). These belong in `kksimp/ail` and are kept here for reference only.
- `.ail-version`: the ail commit that carries those compiler changes (branch `claude/project-thread-egc4ma`, never compiled).

Imported from kksimp/ail `claude/project-thread-egc4ma` at f8e517f2 (based on main 3896938b). History of the three source commits stays there.
