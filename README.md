# Parameterized Asynchronous FIFO

[![CI](https://github.com/Git-2001Abhishek/parameterized-asynchronous-fifo/actions/workflows/ci.yml/badge.svg)](https://github.com/Git-2001Abhishek/parameterized-asynchronous-fifo/actions/workflows/ci.yml)

## Overview

Designed and implemented a parameterized asynchronous FIFO in
SystemVerilog for reliable data transfer between independent
clock domains.

## Features

- Parameterized data width and FIFO depth
- Independent read and write clock domains
- Binary and Gray-code pointers
- Two-flop CDC synchronizers
- Full and empty detection
- Reset handling
- SystemVerilog verification environment
- Formal verification with SymbiYosys (both clocks fully asynchronous)
- Continuous integration (GitHub Actions)

## Architecture

```text
            write clock domain                     read clock domain
        +----------------------+               +----------------------+
 winc ->|      wptr_full       |  wptr (Gray)  |  sync_2ff (w2r)      |
        |  wbin -> waddr       |-------------->|  -> rq2_wptr         |
 wfull<-|  wgray -> wptr       |               |                      |
        +----------------------+               |     rptr_empty       |<- rinc
        |  sync_2ff (r2w)      |  rptr (Gray)  |  rbin -> raddr       |
        |  -> wq2_rptr         |<--------------|  rgray -> rptr       |-> rempty
        +----------------------+               +----------------------+
                   |  waddr, wdata, wen               |  raddr
                   v                                  v
              +------------------------------------------+
              |      fifo_mem  (2**ADDR_WIDTH x DATA)    | -> rdata
              +------------------------------------------+
```

The FIFO uses independent read and write pointers operating in
separate clock domains. Gray-coded pointers are synchronized across
clock domains using two-stage synchronizers.

| Module | Description |
| --- | --- |
| [`async_fifo.sv`](rtl/async_fifo.sv) | Top level, wires the blocks together |
| [`fifo_mem.sv`](rtl/fifo_mem.sv) | Dual-port memory: synchronous write, combinational read |
| [`wptr_full.sv`](rtl/wptr_full.sv) | Write pointer (binary + Gray) and registered `wfull` |
| [`rptr_empty.sv`](rtl/rptr_empty.sv) | Read pointer (binary + Gray) and registered `rempty` |
| [`sync_2ff.sv`](rtl/sync_2ff.sv) | Two-flop pointer synchronizer |

### Parameters

| Parameter | Default | Meaning |
| --- | --- | --- |
| `DATA_WIDTH` | 8 | Word width in bits |
| `ADDR_WIDTH` | 4 | Depth = `2**ADDR_WIDTH` (16 by default) |

### Design notes

- Pointers are `ADDR_WIDTH+1` bits wide. The extra MSB tells a full FIFO
  (same address, different wrap) apart from an empty one (identical pointers).
- **Empty**: next Gray read pointer equals the synchronized Gray write pointer.
- **Full**: next Gray write pointer equals the synchronized Gray read pointer
  with its two MSBs inverted.
- Only one bit of a Gray pointer changes per increment, so even if a
  synchronizer samples during a transition, the receiving domain sees either
  the old or the new value, never a corrupt one.
- Flags are *pessimistic*: because the opposite pointer arrives two cycles
  late, `wfull` may stay high, and `rempty` may stay high, for a couple of
  cycles longer than strictly needed. They never assert late, so the FIFO
  can't overflow or underflow.
- `rdata` is first-word-fall-through: valid whenever `rempty` is low.
- Writes while full and reads while empty are ignored.
- Each domain has its own active-low asynchronous reset (`wrst_n`, `rrst_n`).
  Reset both together to clear the FIFO: resetting only one side would leave
  the pointers inconsistent.
- The resets are asserted asynchronously, but their **deassertion must be
  synchronous** to the respective clock. In a real SoC, drive each one from a
  standard reset synchronizer in that clock domain. The FIFO doesn't include
  one, so it can share the system's reset tree.

## Verification

The self-checking testbench ([`tb/tb_async_fifo.sv`](tb/tb_async_fifo.sv))
keeps a queue-based reference model: every accepted write is pushed, every
accepted read is popped and compared with `rdata`. It also checks that the
model never holds more than `DEPTH` entries.

| # | Test | What is checked |
| --- | --- | --- |
| 1 | Reset | `rempty=1`, `wfull=0` |
| 2 | Fill to full | exactly `DEPTH` writes accepted before `wfull`; overflow write ignored |
| 3 | Drain to empty | data order, exactly `DEPTH` reads; underflow read ignored |
| 4 | Simultaneous read/write | 3 x 2000 cycles of random traffic: write-heavy, read-heavy, balanced |
| 5 | Reset mid-traffic | flags return to reset values, FIFO usable afterwards |
| 6 | Boundary / wrap-around | 4 back-to-back fill/drain cycles so both pointers wrap |

### Results

Default configuration (8-bit x 16, wclk 100 MHz, rclk 58.8 MHz) -
[`results/sim.log`](results/sim.log):

```text
writes accepted : 2006
reads accepted  : 1997      (9 words discarded by the mid-stream reset)
writes blocked by full : 1367
reads blocked by empty : 1283
TEST PASSED
```

Regression across widths, depths and clock ratios -
[`results/regression.log`](results/regression.log):

| Config | Width | Depth | wclk | rclk | Result |
| --- | --- | --- | --- | --- | --- |
| fast-write | 8 | 16 | 10 ns | 17 ns | PASS |
| fast-read | 8 | 16 | 17 ns | 10 ns | PASS |
| equal-clocks | 16 | 4 | 10 ns | 10 ns | PASS |
| 7x ratio | 32 | 8 | 6 ns | 42 ns | PASS |
| 7x ratio (reversed) | 32 | 8 | 42 ns | 6 ns | PASS |
| deep, slow write | 8 | 64 | 26 ns | 8 ns | PASS |
| minimum depth | 4 | 2 | 10 ns | 13 ns | PASS |

As a sanity check that the testbench catches real bugs, breaking the full
comparison in `wptr_full.sv` (inverting one MSB instead of two) makes the
default run fail with thousands of errors.

Waveform: writing until full, the ignored overflow write (`wdata=ff`),
and the read side starting to drain. Note the two-cycle lag of
`rq2_wptr` / `wq2_rptr` and the Gray-coded pointer values.

![FIFO fill / full waveform](results/wave_fill_full.png)

Synthesis (Yosys, generic gates, 8 x 16) - [`results/synth_stat.txt`](results/synth_stat.txt):
128 enable-flops for storage, 40 flops for pointers / flags / synchronizers,
no latches.

## Formal verification

[`formal/fifo_formal.sv`](formal/fifo_formal.sv) and
[`formal/async_fifo.sby`](formal/async_fifo.sby) check the FIFO with
SymbiYosys in **multiclock** mode. `wclk` and `rclk` are free inputs that
can toggle independently, so the solver explores every phase and frequency
relationship between the two domains, not just the handful of clock ratios
used in simulation.

Properties:

| Property | Meaning |
| --- | --- |
| No overflow | a write is never accepted while `DEPTH` words are stored |
| No underflow | a read is never accepted while the FIFO is empty |
| Data integrity and ordering | an arbitrary (solver-chosen) write number N is tracked, and the N-th accepted read must return exactly that word. Because N is free, this covers every word |
| Safe flags | `wfull = 0` implies there is space; `rempty = 0` implies there is data |
| Cover | the FIFO can hold `DEPTH` words, become full, and drain back to empty |

Results (`make formal`):

| Task | Configuration | Result |
| --- | --- | --- |
| `bmc_d2` | depth-2 FIFO, 22 steps (pointers wrap several times) | **PASS** |
| `bmc_d4` | depth-4 FIFO, 18 steps (past a full fill and drain) | **PASS** |
| `cover_d4` | depth-4 FIFO | `DEPTH` words stored and full at step 8, full → empty at step 15 |

These are **bounded** proofs: no property can fail within that many
global time steps, from reset, for any input and clock behaviour. An
unbounded (k-induction) proof would need extra invariants on the
synchronizer stages and is not done here. The data width is 1 bit in the
formal runs: the pointer and flag logic doesn't depend on it, and a free
1-bit word still exposes any lost, duplicated or reordered entry.

**Formal mutation testing** ([`scripts/formal_mutate.py`](scripts/formal_mutate.py),
[`results/formal_mutation.log`](results/formal_mutation.log)):

| Injected bug | Result |
| --- | --- |
| Write allowed while full | **caught**: overflow assertion fails |
| Read pointer advances while empty | **caught**: underflow assertion fails |
| Empty compares the current pointer instead of the next one | **caught** |
| Binary pointer sent across the clock boundary instead of Gray | **caught** |
| Full compare inverts one MSB instead of two | not caught within the bound, even on a depth-4 FIFO. The shortest overflow trace is about 25 steps (reader at pointer 2, then 5 more writes), beyond the 18-step bound, and each extra step roughly doubles z3's runtime. **Simulation catches it** (thousands of errors) |
| Single-flop synchronizer | not caught, as expected: see below |

Running this check also improved the harness. The first version only
asserted *safety*, so a too-early `wfull` went unnoticed. A
`cover (stored == DEPTH)` goal was added so that losing capacity is
detected as well.

One limit applies to both formal and simulation: they use zero-delay
models without metastability, so a missing synchronizer flop is
functionally invisible. That bug class needs structural CDC checks.

## How to run

Requires Icarus Verilog 12+ (`-g2012`).

```bash
make sim                                  # default config, writes results/sim.log + VCD
make sim ADDR_WIDTH=3 DATA_WIDTH=16 WCLK_HALF=9.0 RCLK_HALF=4.0
make regress                              # all configurations above
make wave                                 # open the VCD in GTKWave
make lint                                 # Verilator -Wall lint (clean)
make formal                               # SymbiYosys bounded proofs + cover
make formal-mutate                        # check injected bugs break the formal checks
python scripts/plot_vcd.py results/async_fifo.vcd out.png --start 60 --end 420 \
    --signals tb_async_fifo.wclk tb_async_fifo.winc tb_async_fifo.wfull
```

Without `make`:

```bash
iverilog -g2012 -o sim.vvp -s tb_async_fifo rtl/*.sv tb/tb_async_fifo.sv
vvp -n sim.vvp
```

## Tools

- SystemVerilog
- Icarus Verilog / Verilator
- Yosys (synthesis check)
- SymbiYosys + z3 (formal)
- GitHub Actions (CI)
- GTKWave / Python + matplotlib (waveforms)

## Repository Structure

```text
rtl/        - RTL source files
tb/         - Testbench
formal/     - Formal harness and SymbiYosys job
scripts/    - Regression, formal mutation and waveform-plotting scripts
results/    - Simulation and formal results, waveforms
.github/    - CI workflow
```

## References

C. E. Cummings, "Simulation and Synthesis Techniques for Asynchronous FIFO
Design", SNUG 2002.
