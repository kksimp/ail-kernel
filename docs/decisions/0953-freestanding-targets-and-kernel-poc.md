# 0953. Freestanding targets `x86_64-none` and `aarch64-none`, and a kernel in AIL with the collector kept

- **Status:** Proposed
- **Date:** 2026-11-05
- **Decided by:** Designer asked for the proof of concept; the build plan is AI (delegated, ADR 0076)
- **Topic:** 23 — Compiler architecture; 15 — Unsafe semantics
- **Builds on:** [ADR 0820](0820-driver-level-unsafe.md), [ADR 0835](0835-native-raw-pointers-and-hw.md), [ADR 0823](0823-lower-ail-feature-files.md), [ADR 0008](0008-isa-priority-policy.md)
- **Design note:** [kernel-poc.md](../design/kernel-poc.md)

## Context

The designer wants to write a kernel or driver in AIL with the garbage
collector, and rejects "it has always been done without one". The designer ruled
out a no-GC mode and any 32-bit target. ADR 0820 step 4 named the targets
`x64-none` and `a64-none` and left them unbuilt.

## Decision

1. **Targets.** `x86_64-none` and `aarch64-none` are new `--target` values
   (`target()` 4 and 5). Each makes a static ELF with no `PT_INTERP`, no
   syscall shim, and an entry symbol `_start` entered by a bootloader already in
   64-bit mode (Limine on x86-64, UEFI or Limine on ARM64). ADR 0008 holds: the
   x86-64 target may boot first, but nothing lands without the ARM64 twin
   compiling, and the ARM64 boot is checked on QEMU `virt` on the Mac gate.
2. **Entry.** `_start` skips `argc`/`argv`, runs `rt.init_none`, calls the
   program's `main` (the kernel's), then `rt.halt`. Code and data link at a
   fixed higher-half address; the base is an `ail build` option.
3. **Runtime hooks** live in `compiler/rt/native/none.ail`. `lower.ail` gets one
   dispatch line (ADR 0823). The hooks replace every syscall the collector
   and `print` use:
   - memory: `sys_mmap(n)` and the heap reservation take from a **static arena**
     after the globals in the ELF's zero-filled segment (default 256 MiB, an
     `ail build` option). This needs no memory map at K0-K1; a later kernel
     may hand the collector a different region with `rt.set_heap(base, n)`
     before first allocation;
   - output: the byte sink is `rt.putc`, a serial write (x86-64 COM1 port I/O,
     ARM64 PL011 MMIO);
   - exit: `rt.exit(code)` writes the QEMU `isa-debug-exit` port, or the ARM64
     semihosting exit, then halts;
   - locks and threads compile to no-ops: the runtime is single-threaded
     (`MULTI` off). SMP is out of scope.
   Files, time of day, environment, net and `proc` trap with
   `error[none.rt.1]: not available without an OS`.
4. **Scoped unsafe, not a second hatch.** The kernel package declares
   `unsafe driver` (ADR 0820). `std.hw` gains port I/O `in8/16/32`, `out8/16/32`
   and CPU intrinsics (`hlt`, `cli`, `sti`, `rdtsc`, `rdmsr`, `wrmsr`, `lgdt`,
   `lidt`, `ltr`, `invlpg`, control-register moves; ARM64 equivalents behind
   `hw.a64.*`), emitted by the in-house assemblers. Intrinsics defined by the
   systems-ABI lane are reused. No free-form asm (OQ-137).
5. **`@interrupt fn`** (ADR 0820 step 5): the compiler writes the prologue,
   saves all registers on the interrupt stack and ends with `iretq` (ARM64:
   `eret`). The checker **rejects** an interrupt function that can allocate
   or call one that can, naming the call chain (rule `unsafe.irq.1`).
6. **`@layout(c)`** is the systems-ABI lane's S3 (ADR 0952); this ADR reuses it.
7. **Code generation mode.** Freestanding targets emit no SSE/AVX and make no
   use of a red zone, so an interrupt never needs FP state save.
8. **Kernel rules** (design note): an interrupt never allocates or collects;
   DMA buffers are page-allocator frames with a GC handle and a pin table; the
   collector stays conservative and non-moving.
9. **Output.** The kernel prints one JSON object per line on the serial port
   (`boot`, `gc`, `tick_lag`, `done`); `tools/kernel/run.sh` boots QEMU and
   summarises it.
10. **Build order, each its own PR:** G1 target and entry; G2 `none.ail`;
    G3 port I/O and intrinsics; G6 codegen mode; G4 `@interrupt fn`; then the
    kernel in `examples/kernel/` (K0-K5). Spec rule IDs `native.none.*` and
    `unsafe.irq.*` are added with the PRs that implement them.

## Rejected alternatives

- **A no-GC kernel mode:** rejected by the designer.
- **Multiboot2:** needs a 32-bit stub.
- **A Linux module first:** needs the kernel's ABI and an embedded heap before
  anything is learned.
- **A precise or moving collector:** needs stack maps and barriers.
- **Collecting in interrupt handlers:** unbounded handler stalls.
- **GC-managed DMA buffers:** a device is not a root.
- **A second escape hatch for kernels (a new manifest level):** ADR 0820's
  `unsafe driver` already is the scoped boundary.

## Consequences

Freestanding builds cannot use the OS-backed parts of `std`. Native tests for
the target run only on the gate (QEMU), not as `ail test` programs. The
Windows release rule is unaffected.
