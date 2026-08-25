# parameterized-asynchronous-fifo
Parameterized asynchronous FIFO designed and verified in SystemVerilog
Overview
Designed and implemented a parameterized asynchronous FIFO in
SystemVerilog for reliable data transfer between independent
clock domains.
Features
- Parameterized data width and FIFO depth
- Independent read and write clock domains
- Binary and Gray-code pointers
- Two-flop CDC synchronizers
- Full and empty detection
- Reset handling
- SystemVerilog verification environment
Architecture
The FIFO uses independent read and write pointers operating in
separate clock domains. Gray-coded pointers are synchronized across
clock domains using two-stage synchronizers.
 Verification
The design will be verified using a SystemVerilog testbench covering:
- Normal read/write operation
- Simultaneous read/write
- Full condition
- Empty condition
- Reset behavior
- Boundary conditions
Tools
- SystemVerilog
- Icarus Verilog / Verilator
- GTKWave

 
Repository Structure

rtl/        - RTL source files
tb/         - Testbench
results/    - Simulation results and waveforms
