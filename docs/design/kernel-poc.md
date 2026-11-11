# A kernel in AIL, with the garbage collector kept (proof of concept)

- **Status:** Proposal (design first; no code yet)
- **Date:** 2026-11-05
- **Asked by:** the designer, 2026-11-05: kernels and drivers have been
  written without a collector because "it has always been done that way";
  test whether a collected kernel works.
- **Fixed by the designer:** no no-GC mode, no 32-bit support (including wasm32).
- **Builds on:** [ADR 0820](../decisions/0820-driver-level-unsafe.md),
  [ADR 0835](../decisions/0835-native-raw-pointers-and-hw.md),
  [native-abi.md](native-abi.md). [ADR 0953](../decisions/0953-freestanding-targets-and-kernel-poc.md) records the build plan.

## The claim on trial

A small x86-64 kernel written in AIL, whose own objects live in a
garbage-collected heap, can boot, take interrupts and run user programs with
pauses short enough to be useful, and is safer to write than the C
equivalent. The PoC measures the first half and counts bug classes avoided
for the second.

## What exists and what is missing

The native collector (`compiler/rt/native/gc.ail`, ADRs 0562, 0564) is
stop-the-world mark and sweep. It is **conservative** (every word of the stack,
the saved registers and the runtime's global slots is a candidate pointer)
and **non-moving**. Its only OS dependency is `sys_mmap` for the heap
reservation and the page table (`heap.ail`), plus the stack top in global
slot 11. `std.hw` (volatile loads and stores, fences) is lowered (ADR 0835).

Missing, in build order:

| # | Gap | Where |
|---|---|---|
| G1 | Target `x64-none`: static ELF at a fixed load address, no `PT_INTERP`, entry symbol, no syscall shim | `compiler/obj/elf.ail`, `compiler/main.ail` |
| G2 | Runtime hooks replacing the OS calls: `rt_mem(n)` (heap memory), `rt_stack_top`, `rt_putc` (serial), `rt_panic` | `compiler/rt/native/` new `none.ail`, selected by target |
| G3 | Port I/O `hw.in8/16/32`, `hw.out8/16/32`; intrinsics `hlt cli sti rdtsc rdmsr wrmsr lgdt lidt ltr invlpg` and control-register moves | `lower_unsafe.ail`, `x64/asm.ail` (intrinsics only, no free-form asm: decided) |
| G4 | `@interrupt fn`: compiler-made prologue and `iretq`, saves all registers, **rejected at check time if it can allocate** (ADR 0820 step 5) | checker plus a new `lower_interrupt.ail` (ADR 0823) |
| G5 | `@layout(c)` structs for GDT, IDT, page tables, Limine requests | checker plus lowering |
| G6 | A freestanding codegen mode: no SSE or AVX in kernel code (no FP state save in interrupts), no red zone use | `x64/gen.ail` flag |

Everything else (the kernel) is ordinary AIL.

## Boot: Limine, not Multiboot2

Multiboot2 enters in 32-bit protected mode and needs a 32-bit stub to reach
long mode. The designer ruled out 32-bit, and an assembly stub is out too
(intrinsics only). Limine's protocol enters the kernel already in 64-bit
long mode, paging on, with the whole physical memory mapped at a known offset
(HHDM) and a memory map handed over. So the kernel's first instruction is AIL.
QEMU boots it from a small ISO or disk image made by the runner script. Limine
and its ISO tool are build-time test tools, never linked in.

## How the GC runs with nothing under it

1. **Heap memory.** At boot, the page allocator takes the largest usable
   region from the Limine memory map. `rt_mem(n)` hands the collector one
   contiguous reservation inside the HHDM (the collector already wants one
   region). The page allocator itself (a bitmap, raw `*T`, no GC objects)
   owns every other frame, so the collector's own bookkeeping never needs the
   collector.
2. **Roots.** Conservative scan of the kernel stack(s) from the stack pointer
   to the stack top, the saved registers, the global slots, and the **pin
   table** (below). Each kernel task has its own stack carved from the page
   allocator; the collector scans every stopped task's stack from its saved
   pointer. With one CPU first, "stop the world" is free: the collector runs
   in the scheduler's context with no other task running.
3. **No moving.** The collector never moves objects, so a pointer held in a
   register, in a hardware descriptor, or on a stack stays valid. This is why
   a conservative, non-moving collector is the right first kernel collector:
   precise or moving schemes need stack maps and write barriers the compiler
   does not have.

## Interrupts versus the collector

The rule: **an interrupt handler never allocates and never triggers a
collection.** `@interrupt fn` (G4) is checked for this. A handler does only
what it can do with static, non-collected memory:

- read or write a device register;
- push a small fixed-size record into a preallocated ring buffer (raw memory
  from the page allocator, not the GC heap);
- set a flag the scheduler reads.

The work after the handler (the "bottom half") runs in a normal kernel task,
where allocation and collection are allowed. Consequences:

- **A collection can start only in task context**, at an allocation. The
  allocation call is the safe point; there is no other. Interrupt frames are
  never mid-collection state, so the collector needs no interrupt masking
  while marking: interrupts stay enabled during a pause, handlers still run
  (they touch only non-collected memory), and the ring buffers fill.
- **What a pause costs** is therefore not interrupt latency but *bottom-half
  latency*: tick processing, packet handling and the like wait until the
  pause ends. That is the quantity to measure and the one a later incremental
  collector would attack.
- Interrupt entry uses the IST (a separate stack per vector class), so a
  handler never runs on a task stack the collector is scanning, and the CPU's
  frame push cannot clobber a red zone (also avoided by G6).
- A conservative scan sees an interrupted task's registers because the
  handler's prologue spills them onto that task's stack, inside the range
  that is scanned.

## Pinned memory: MMIO and DMA

- **MMIO** is never in the GC heap. `hw.at(addr, example)` gives a `*T` to the
  fixed address (ADR 0835); the collector ignores addresses outside its
  reservation.
- **DMA buffers** are the real hazard: the *device* holds the address, and a
  device is not a root, so a collected buffer would be freed under it. The
  rule: a DMA buffer is **not** a GC object. It is frames from the page
  allocator, owned by a small GC object (the handle) that holds the address.
  `dma.alloc(n)` returns a handle; the handle's owner calls `release()`
  explicitly (a hardware resource has an explicit lifetime), and the page
  allocator keeps a **pin table** of live DMA ranges that the collector also
  treats as roots for any collected object referenced from inside them.
  Because nothing moves and the heap is in the direct map, the physical
  address is `virt - hhdm_offset`, computed once at allocation.
- Descriptors that reference collected objects (a network ring pointing at a
  packet object) hold them alive through the pin table until the device
  reports completion.

## The PoC scope

K0 Boot: Limine ISO boots under QEMU, prints a line over COM1, exits through
the `isa-debug-exit` device with a code. Proves G1, G2, port I/O.

K1 Heap: page allocator plus the real collector over a kernel heap; an
allocation stress loop forces many collections; the heap verifier (`AIL_GC_VERIFY`
equivalent) passes. Proves the runtime runs freestanding.

K2 Interrupts: IDT, LAPIC timer at 1 kHz, ring buffer, bottom-half task.
A stress task allocates while ticks arrive. Proves G4 and the interrupt rule.

K3 Tasks and syscalls: kernel tasks with a round-robin scheduler; `syscall`
entry; a ring-3 static ELF user program using a Linux subset (`write`,
`exit`, `exit_group`, `brk`, `mmap` anonymous, `getpid`, `clock_gettime`,
`nanosleep`). The user program is built from AIL `x64-none` too (no libc).
Proves the "Linux-like" ABI claim.

K4 Driver: a virtio-blk or virtio-rng driver with a DMA ring using the pin
table. Proves the DMA rule against a real device model.

K5 Report: the measurement run below, in one JSON file.

**Second milestone, separately:** a Linux loadable module written in AIL. It
needs the in-tree kernel ABI (module entry, `kmalloc`, no libc, a build
against kernel headers) and a GC heap inside kernel memory with its own
stacks to scan, which is a different and larger runtime port. A cheaper
earlier proof of "AIL drivers" is the user-space UIO or VFIO path already
planned in ADR 0820 step 3, which needs none of the freestanding work.
Recommendation: finish K0-K5, then decide.

## Measuring pauses (AI-first output)

The kernel prints one JSON object per line on COM1, so a run is its own
trace and an agent can read it without parsing prose:

```text
{"ev":"boot","kernel":"ail-k","heap_mb":64}
{"ev":"gc","n":12,"pause_cycles":184213,"pause_us":61,"live_kb":812,"freed_kb":9210,"roots":341,"ring_dropped":0}
{"ev":"tick_lag","n":12,"max_bottom_half_delay_us":74,"irq_to_isr_cycles":412}
{"ev":"done","gcs":57,"p50_us":58,"p99_us":143,"max_us":161,"panics":0}
```

Time comes from `rdtsc`, calibrated against the LAPIC timer. The runner
(`tools/kernel/run.sh`) boots QEMU with a serial pipe, a timeout and the exit
device, extracts the JSON lines, checks `panics == 0`, and prints the
summary. Fields measured:

- GC pause (cycles and microseconds) against live heap size and root count;
- bottom-half delay behind a pause, and ISR entry latency during a pause;
- allocation rate at which the ring buffer first drops a record;
- user-program syscall round-trip (cycles).

**Caveat:** ail-linux is itself a VM on the TrueNAS box, so QEMU there runs
without KVM (TCG). TCG distorts absolute times, so use `-icount` for
repeatable runs and read the results as shape (pause against heap size, who
waits on whom), not as real-hardware microseconds. Absolute numbers need KVM or a real x86-64 box (the Mac's `hvf` cannot run x86-64 guests at speed); flag this in the report.

## Where the code goes

`examples/kernel/` holds the kernel and the user program (ordinary AIL, built
with `ail build --target x64-none --unsafe driver`). Compiler and runtime
changes G1-G6 are separate small PRs, each with the usual rule IDs and ADRs.
No kernel code goes into `compiler/`. Test harness: `tools/kernel/`.

## Risks

- **Conservative scanning and stale words.** Stack garbage can retain dead
  objects. Acceptable for a PoC; the kernel zeroes fresh task stacks.
- **Collector allocates?** It must not call the allocator it is collecting;
  it already uses its own mark stack from `sys_mmap` (`H_MARKS`), which
  becomes `rt_mem` too.
- **Hard real time.** A stop-the-world pause is unbounded in heap size. The
  PoC's honest answer is a measured curve. If bottom-half pauses are too long,
  next steps are a smaller kernel heap, per-subsystem heaps, or an incremental
  collector; none is needed to run the experiment.
- **Compiler assumptions.** The runtime uses global slots and, with threads,
  `sp()`-based cache selection. Kernel mode runs single-threaded runtime
  (`MULTI` off) first; SMP is out of scope.

## Rejected alternatives

- **A no-GC kernel mode:** rejected by the designer; it defeats the claim.
- **Multiboot2:** needs a 32-bit assembly stub.
- **A Linux module first:** needs the kernel's ABI and an embedded GC heap
  before anything is learned; the freestanding kernel isolates the question.
- **A precise or moving collector first:** needs stack maps and barriers.
- **Collecting inside interrupt handlers:** makes every handler a possible
  multi-millisecond stall and forces masking during marking.
- **GC-managed DMA buffers:** a device is not a root.
- **Free-form inline assembly for entry stubs:** decided against for now
  (intrinsics only, OQ-137); `@interrupt fn` covers the one place it is needed.
