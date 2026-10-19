#!/bin/sh
# Runs the testbench across several width / depth / clock-ratio configurations.
# Usage (from anywhere):  sh scripts/regress.sh
set -e
cd "$(dirname "$0")/.."
mkdir -p results

RTL="rtl/sync_2ff.sv rtl/fifo_mem.sv rtl/wptr_full.sv rtl/rptr_empty.sv rtl/async_fifo.sv"
LOG=results/regression.log
: > "$LOG"
fail=0

run_cfg() {
    # $1=name $2=DATA_WIDTH $3=ADDR_WIDTH $4=WCLK_HALF $5=RCLK_HALF
    iverilog -g2012 -o results/reg.vvp -s tb_async_fifo \
        -Ptb_async_fifo.DATA_WIDTH="$2" -Ptb_async_fifo.ADDR_WIDTH="$3" \
        -Ptb_async_fifo.WCLK_HALF="$4" -Ptb_async_fifo.RCLK_HALF="$5" \
        $RTL tb/tb_async_fifo.sv
    out=$(vvp -n results/reg.vvp)
    if echo "$out" | grep -q "TEST PASSED"; then res=PASS; else res=FAIL; fail=1; fi
    cfg=$(echo "$out" | grep "^async_fifo:")
    printf "%-20s %-55s %s\n" "$1" "${cfg#async_fifo: }" "$res" | tee -a "$LOG"
}

run_cfg fast-write          8  4  5.0  8.5
run_cfg fast-read           8  4  8.5  5.0
run_cfg equal-clocks-d4    16  2  5.0  5.0
run_cfg ratio-7x-d8        32  3  3.0 21.0
run_cfg ratio-7x-rev-d8    32  3 21.0  3.0
run_cfg depth64-slow-write  8  6 13.0  4.0
run_cfg depth2-min          4  1  5.0  6.5

rm -f results/reg.vvp
exit $fail
