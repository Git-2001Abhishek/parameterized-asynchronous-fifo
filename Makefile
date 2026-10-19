# Icarus Verilog flow. Override parameters on the command line, e.g.
#   make sim ADDR_WIDTH=3 DATA_WIDTH=16 WCLK_HALF=9.0 RCLK_HALF=4.0
#   make formal      SymbiYosys bounded proofs + cover (formal/async_fifo.sby)
#   make formal-mutate  check that injected bugs break the formal checks

DATA_WIDTH ?= 8
ADDR_WIDTH ?= 4
WCLK_HALF  ?= 5.0
RCLK_HALF  ?= 8.5

RTL = rtl/sync_2ff.sv rtl/fifo_mem.sv rtl/wptr_full.sv rtl/rptr_empty.sv rtl/async_fifo.sv
TB  = tb/tb_async_fifo.sv

PARAMS = -Ptb_async_fifo.DATA_WIDTH=$(DATA_WIDTH) -Ptb_async_fifo.ADDR_WIDTH=$(ADDR_WIDTH) \
         -Ptb_async_fifo.WCLK_HALF=$(WCLK_HALF) -Ptb_async_fifo.RCLK_HALF=$(RCLK_HALF)

SBY ?= sby

PYTHON ?= python3

.PHONY: sim regress lint formal formal-mutate wave clean

sim:
	mkdir -p results
	iverilog -g2012 -Wall -o results/sim.vvp -s tb_async_fifo $(PARAMS) $(RTL) $(TB)
	vvp -n results/sim.vvp | tee results/sim.log
	@grep -q "TEST PASSED" results/sim.log || (echo "simulation FAILED"; exit 1)

regress:
	sh scripts/regress.sh

lint:
	verilator --lint-only -Wall --top-module async_fifo $(RTL)

formal:
	cd formal && $(SBY) -f async_fifo.sby

formal-mutate:
	SBY="$(SBY)" $(PYTHON) scripts/formal_mutate.py > results/formal_mutation.log; status=$$?; cat results/formal_mutation.log; exit $$status

wave:
	gtkwave results/async_fifo.vcd &

clean:
	rm -f results/*.vvp results/*.vcd
	rm -rf formal/async_fifo_*/
