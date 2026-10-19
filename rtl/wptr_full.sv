// -----------------------------------------------------------------------------
// wptr_full
// Write-domain pointer logic. Keeps a binary pointer (memory address) and a
// Gray pointer (sent to the read domain). The FIFO is full when the next Gray
// write pointer equals the synchronized read pointer with its two MSBs inverted.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module wptr_full #(
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [ADDR_WIDTH:0]   wq2_rptr,   // read Gray pointer, synchronized
    output logic [ADDR_WIDTH-1:0] waddr,
    output logic [ADDR_WIDTH:0]   wptr,       // write Gray pointer
    output logic                  wfull
);

    logic [ADDR_WIDTH:0] wbin;
    logic [ADDR_WIDTH:0] wbin_next;
    logic [ADDR_WIDTH:0] wgray_next;
    logic                wfull_next;

    assign wbin_next  = wbin + {{ADDR_WIDTH{1'b0}}, (winc & ~wfull)};
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;
    assign wfull_next = (wgray_next == (wq2_rptr ^ {2'b11, {(ADDR_WIDTH-1){1'b0}}}));
    assign waddr      = wbin[ADDR_WIDTH-1:0];

    always_ff @(posedge wclk or negedge wrst_n) begin
        if (!wrst_n) begin
            wbin  <= '0;
            wptr  <= '0;
            wfull <= 1'b0;
        end else begin
            wbin  <= wbin_next;
            wptr  <= wgray_next;
            wfull <= wfull_next;
        end
    end

endmodule
