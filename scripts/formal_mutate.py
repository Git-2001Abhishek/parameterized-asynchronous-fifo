#!/usr/bin/env python3
"""
Check that the FIFO formal properties catch real bugs: inject one bug at a
time into the RTL and run the bounded proof plus the cover task, on a
depth-2 FIFO (16 / 30 steps) or a depth-4 FIFO (18 / 30 steps). A mutant is
caught if the proof fails or a cover goal becomes unreachable.

Two mutants are EXPECTED to survive, for documented reasons:
  * a single-flop synchronizer behaves identically in a zero-delay model,
    because neither formal nor simulation models metastability (catching it
    is the job of structural CDC checks);
  * the full-flag bug only becomes unsafe after ~25 steps, beyond the
    bound. The simulation testbench does catch it.

Optional arguments select mutants by name, e.g.  formal_mutate.py "full compare"

Usage (from the repository root):  python scripts/formal_mutate.py
Tool names can be overridden with SBY, YOSYS, SMTBMC environment variables.
"""
import io
import os
import re
import shutil
import subprocess
import sys

RTL = ["sync_2ff.sv", "fifo_mem.sv", "wptr_full.sv", "rptr_empty.sv", "async_fifo.sv"]

MUTATIONS = [
    # With 2-bit Gray pointers this bug is merely pessimistic, so depth 4 is
    # used. Even then the shortest overflow trace (reader at pointer 2, then
    # 5 more writes) is ~25 steps, beyond the 18-step bound.
    ("full compare inverts one MSB (expected survivor: beyond bound)", "wptr_full.sv",
     "{2'b11, {(ADDR_WIDTH-1){1'b0}}}", "{2'b01, {(ADDR_WIDTH-1){1'b0}}}", 2),
    ("write allowed while full", "async_fifo.sv",
     ".wen   (winc & ~wfull),", ".wen   (winc),"),
    ("read pointer advances while empty", "rptr_empty.sv",
     "rbin + {{ADDR_WIDTH{1'b0}}, (rinc & ~rempty)}", "rbin + {{ADDR_WIDTH{1'b0}}, rinc}"),
    ("empty compares current pointer, not next", "rptr_empty.sv",
     "assign rempty_next = (rgray_next == rq2_wptr);", "assign rempty_next = (rptr == rq2_wptr);"),
    ("binary pointer sent across instead of Gray", "wptr_full.sv",
     "            wptr  <= wgray_next;", "            wptr  <= wbin_next;"),
    ("single-flop synchronizer (expected survivor)", "sync_2ff.sv",
     "            q    <= meta;", "            q    <= d;"),
]
EXPECTED_SURVIVORS = {"single-flop synchronizer (expected survivor)",
                      "full compare inverts one MSB (expected survivor: beyond bound)"}

SBY = """[tasks]
bmc
cover

[options]
bmc:   mode bmc
bmc:   depth {DEPTH}
cover: mode cover
cover: depth 30
multiclock on

[engines]
smtbmc z3

[script]
read -formal sync_2ff.sv fifo_mem.sv wptr_full.sv rptr_empty.sv async_fifo.sv
read -formal -DADDR_W={ADDR_W} fifo_formal.sv
prep -top fifo_formal

[files]
""" + "\n".join(RTL + ["fifo_formal.sv"]) + "\n"


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    sby = os.environ.get("SBY", "sby").split()
    tools = []
    if "YOSYS" in os.environ:
        tools += ["--yosys", os.environ["YOSYS"]]
    if "SMTBMC" in os.environ:
        tools += ["--smtbmc", os.environ["SMTBMC"]]
    work = os.path.join("formal", "mutants")
    survivors = 0
    only = sys.argv[1:]          # optional: run only mutants whose name contains these words
    for mut in MUTATIONS:
        name, fname, old, new = mut[:4]
        addr_w = mut[4] if len(mut) > 4 else 1
        if only and not any(w in name for w in only):
            continue
        shutil.rmtree(work, ignore_errors=True)
        os.makedirs(work)
        for f in RTL:
            src = io.open(os.path.join("rtl", f), encoding="utf-8").read()
            if f == fname:
                if old not in src:
                    sys.exit("mutation '%s' does not apply - RTL changed?" % name)
                src = src.replace(old, new, 1)
            io.open(os.path.join(work, f), "w", encoding="utf-8", newline="\n").write(src)
        shutil.copy(os.path.join("formal", "fifo_formal.sv"), work)
        io.open(os.path.join(work, "m.sby"), "w", newline="\n").write(
            SBY.replace("{ADDR_W}", str(addr_w)).replace("{DEPTH}", "16" if addr_w == 1 else "18"))
        out = subprocess.run(sby + tools + ["-f", "m.sby"], cwd=work,
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True).stdout
        res = dict(re.findall(r"\[m_(bmc|cover)\] DONE \((\w+), rc=\d+\)", out))
        killed = "FAIL" in res.values()
        expected = name in EXPECTED_SURVIVORS
        if not killed and not expected:
            survivors += 1
        verdict = "killed" if killed else ("survived (expected)" if expected else "SURVIVED")
        print("%-62s %-20s bmc: %-5s cover: %s" % (name, verdict,
              res.get("bmc", "ERROR"), res.get("cover", "ERROR")))
    shutil.rmtree(work, ignore_errors=True)
    print("-" * 74)
    n = len(MUTATIONS) - len(EXPECTED_SURVIVORS)
    print("%d / %d mutants caught (plus %d expected survivors)" % (n - survivors, n, len(EXPECTED_SURVIVORS)))
    sys.exit(1 if survivors else 0)


if __name__ == "__main__":
    main()
