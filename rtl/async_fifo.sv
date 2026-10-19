// -----------------------------------------------------------------------------
// async_fifo
// Parameterized asynchronous FIFO (depth = 2**ADDR_WIDTH).
//
//   write domain : wclk / wrst_n / winc / wdata / wfull
//   read  domain : rclk / rrst_n / rinc / rdata / rempty
//
// rdata is first-word-fall-through: it shows the word at the head of the FIFO
// whenever rempty is low, and advances on a clock edge with rinc asserted.
// Writes while full and reads while empty are ignored.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module async_fifo #(
    parameter int DATA_WIDTH = 8,
    parameter int ADDR_WIDTH = 4
) (
    // write domain
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  winc,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    // read domain
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  rinc,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty
);

    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic [ADDR_WIDTH:0]   wptr, rptr;
    logic [ADDR_WIDTH:0]   wq2_rptr, rq2_wptr;

    // read pointer -> write domain
    sync_2ff #(.WIDTH(ADDR_WIDTH + 1)) u_sync_r2w (
        .clk   (wclk),
        .rst_n (wrst_n),
        .d     (rptr),
        .q     (wq2_rptr)
    );

    // write pointer -> read domain
    sync_2ff #(.WIDTH(ADDR_WIDTH + 1)) u_sync_w2r (
        .clk   (rclk),
        .rst_n (rrst_n),
        .d     (wptr),
        .q     (rq2_wptr)
    );

    fifo_mem #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) u_mem (
        .wclk  (wclk),
        .wen   (winc & ~wfull),
        .waddr (waddr),
        .wdata (wdata),
        .raddr (raddr),
        .rdata (rdata)
    );

    wptr_full #(.ADDR_WIDTH(ADDR_WIDTH)) u_wptr_full (
        .wclk     (wclk),
        .wrst_n   (wrst_n),
        .winc     (winc),
        .wq2_rptr (wq2_rptr),
        .waddr    (waddr),
        .wptr     (wptr),
        .wfull    (wfull)
    );

    rptr_empty #(.ADDR_WIDTH(ADDR_WIDTH)) u_rptr_empty (
        .rclk     (rclk),
        .rrst_n   (rrst_n),
        .rinc     (rinc),
        .rq2_wptr (rq2_wptr),
        .raddr    (raddr),
        .rptr     (rptr),
        .rempty   (rempty)
    );

endmodule
