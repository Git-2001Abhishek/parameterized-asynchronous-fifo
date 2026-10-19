// -----------------------------------------------------------------------------
// fifo_mem
// Dual-port storage: synchronous write in the write-clock domain,
// asynchronous (combinational) read addressed from the read-clock domain.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module fifo_mem #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wclk,
    input  logic                  wen,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
);

    localparam int DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge wclk) begin
        if (wen)
            mem[waddr] <= wdata;
    end

    assign rdata = mem[raddr];

endmodule
