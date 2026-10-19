// -----------------------------------------------------------------------------
// rptr_empty
// Read-domain pointer logic. The FIFO is empty when the next Gray read pointer
// equals the synchronized write pointer.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module rptr_empty #(
    parameter int ADDR_WIDTH = 4
) (
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    input  logic [ADDR_WIDTH:0]   rq2_wptr,   // write Gray pointer, synchronized
    output logic [ADDR_WIDTH-1:0] raddr,
    output logic [ADDR_WIDTH:0]   rptr,       // read Gray pointer
    output logic                  rempty
);

    logic [ADDR_WIDTH:0] rbin;
    logic [ADDR_WIDTH:0] rbin_next;
    logic [ADDR_WIDTH:0] rgray_next;
    logic                rempty_next;

    assign rbin_next   = rbin + {{ADDR_WIDTH{1'b0}}, (rinc & ~rempty)};
    assign rgray_next  = (rbin_next >> 1) ^ rbin_next;
    assign rempty_next = (rgray_next == rq2_wptr);
    assign raddr       = rbin[ADDR_WIDTH-1:0];

    always_ff @(posedge rclk or negedge rrst_n) begin
        if (!rrst_n) begin
            rbin   <= '0;
            rptr   <= '0;
            rempty <= 1'b1;
        end else begin
            rbin   <= rbin_next;
            rptr   <= rgray_next;
            rempty <= rempty_next;
        end
    end

endmodule
