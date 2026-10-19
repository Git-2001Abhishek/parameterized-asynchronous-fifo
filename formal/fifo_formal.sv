// -----------------------------------------------------------------------------
// fifo_formal
// Formal harness for async_fifo (SymbiYosys, multiclock mode: wclk and rclk
// are free inputs that toggle independently, so every possible phase and
// frequency relationship between the two clocks is explored).
//
// Properties
//   1. No overflow : a write is never accepted while DEPTH words are stored
//   2. No underflow: a read is never accepted while the FIFO is empty
//   3. Data integrity and ordering: an arbitrary-but-fixed write number N is
//      tracked; the N-th accepted read must return exactly the N-th written
//      word. Because N is unconstrained, this covers every word.
//   4. Flags are never wrong in the unsafe direction:
//        wfull  == 0  ->  fewer than DEPTH words stored
//        rempty == 0  ->  at least one word stored
//
// Resets: both domains are reset together at the start (as required by the
// design), and may be asserted together again at any later time.
// -----------------------------------------------------------------------------
`ifndef ADDR_W
  `define ADDR_W 2
`endif

module fifo_formal #(
    parameter int DATA_WIDTH = 1,
    parameter int ADDR_WIDTH = `ADDR_W
) (
    input  logic                  wclk,
    input  logic                  rclk,
    input  logic                  rst_n,
    input  logic                  winc,
    input  logic                  rinc,
    input  logic [DATA_WIDTH-1:0] wdata
);

    localparam int DEPTH = 1 << ADDR_WIDTH;
    localparam int CW    = 5;              // counter width for the bookkeeping

    logic [DATA_WIDTH-1:0] rdata;
    logic                  wfull, rempty;

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .wclk   (wclk),
        .wrst_n (rst_n),
        .winc   (winc),
        .wdata  (wdata),
        .wfull  (wfull),
        .rclk   (rclk),
        .rrst_n (rst_n),
        .rinc   (rinc),
        .rdata  (rdata),
        .rempty (rempty)
    );

    // reset at the start of every trace
    logic init = 1'b1;
    always @($global_clock) begin
        init <= 1'b0;
        if (init) assume (!rst_n);
    end

    // ------------------------------------------------------------------
    // Bookkeeping: number of accepted writes / reads
    // ------------------------------------------------------------------
    logic [CW-1:0] n_wr, n_rd;

    always @(posedge wclk or negedge rst_n)
        if (!rst_n)              n_wr <= '0;
        else if (winc && !wfull) n_wr <= n_wr + 1'b1;

    always @(posedge rclk or negedge rst_n)
        if (!rst_n)               n_rd <= '0;
        else if (rinc && !rempty) n_rd <= n_rd + 1'b1;

    logic [CW-1:0] stored;
    assign stored = n_wr - n_rd;

    // keep the bookkeeping counters from wrapping inside the proof depth
    always @(*) assume (n_wr < {CW{1'b1}});

    // ------------------------------------------------------------------
    // Tracked word
    // ------------------------------------------------------------------
    (* anyconst *) logic [CW-1:0] track_n;
    logic [DATA_WIDTH-1:0] track_data;
    logic                  track_written;

    always @(posedge wclk or negedge rst_n)
        if (!rst_n) begin
            track_written <= 1'b0;
            track_data    <= '0;
        end else if (winc && !wfull && n_wr == track_n) begin
            track_written <= 1'b1;
            track_data    <= wdata;
        end

    // ------------------------------------------------------------------
    // Properties (checked at every global time step)
    // ------------------------------------------------------------------
    always @(*) begin
        if (rst_n && !init) begin
            // 1 / 2: the stored count stays within 0 .. DEPTH
            assert (stored <= DEPTH);
            assert (n_rd <= n_wr);

            // 4: flags only err on the safe side
            if (!wfull)  assert (stored < DEPTH || !rst_n);
            if (!rempty) assert (stored != 0);

            // 3: the tracked word comes out unchanged and in order
            if (rinc && !rempty && n_rd == track_n) begin
                assert (track_written);
                assert (rdata == track_data);
            end
        end
    end

    // ------------------------------------------------------------------
    // Cover: show the FIFO can actually hold DEPTH words, fill up and drain
    // again (a too-early wfull would make the second cover unreachable)
    // ------------------------------------------------------------------
    logic was_full;
    always @(posedge wclk or negedge rst_n)
        if (!rst_n)     was_full <= 1'b0;
        else if (wfull) was_full <= 1'b1;

    always @(*) begin
        if (rst_n) begin
            cover (wfull);
            cover (stored == DEPTH);          // full capacity is usable
            cover (was_full && rempty && n_rd == DEPTH);
        end
    end

endmodule
