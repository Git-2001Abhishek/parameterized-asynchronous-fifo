// -----------------------------------------------------------------------------
// tb_async_fifo
// Self-checking testbench for async_fifo. A queue-based scoreboard records
// every accepted write and checks every accepted read against it.
//
// Tests:
//   1. reset values
//   2. fill to full (exactly DEPTH writes accepted, overflow write ignored)
//   3. drain to empty (data order, underflow read ignored)
//   4. simultaneous random read/write traffic (write-heavy, read-heavy, balanced)
//   5. reset in the middle of traffic
//   6. boundary: pointer wrap-around over repeated fill/drain cycles
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_async_fifo;

    parameter int  DATA_WIDTH = 8;
    parameter int  ADDR_WIDTH = 4;
    parameter real WCLK_HALF  = 5.0;   // 100 MHz
    parameter real RCLK_HALF  = 8.5;   // ~58.8 MHz

    localparam int DEPTH = 1 << ADDR_WIDTH;
    localparam int POST_RST_WORDS = (DEPTH < 3) ? DEPTH : 3;

    logic                  wclk = 1'b0, rclk = 1'b0;
    logic                  wrst_n, rrst_n;
    logic                  winc, rinc;
    logic [DATA_WIDTH-1:0] wdata, rdata;
    logic                  wfull, rempty;

    always #(WCLK_HALF) wclk = ~wclk;
    always #(RCLK_HALF) rclk = ~rclk;

    async_fifo #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (ADDR_WIDTH)
    ) dut (
        .wclk   (wclk),
        .wrst_n (wrst_n),
        .winc   (winc),
        .wdata  (wdata),
        .wfull  (wfull),
        .rclk   (rclk),
        .rrst_n (rrst_n),
        .rinc   (rinc),
        .rdata  (rdata),
        .rempty (rempty)
    );

    // ------------------------------------------------------------------
    // Scoreboard
    // ------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] model_q [$];
    logic [DATA_WIDTH-1:0] exp_data;
    int errors   = 0;
    int n_writes = 0;
    int n_reads  = 0;
    int n_full   = 0;   // cycles spent full while a write was attempted
    int n_empty  = 0;   // cycles spent empty while a read was attempted

    always @(posedge wclk) begin
        if (wrst_n && winc) begin
            if (!wfull) begin
                model_q.push_back(wdata);
                n_writes++;
            end else begin
                n_full++;
            end
        end
        if (model_q.size() > DEPTH) begin
            $error("[%0t] overflow: model holds %0d entries", $time, model_q.size());
            errors++;
        end
    end

    always @(posedge rclk) begin
        if (rrst_n && rinc) begin
            if (!rempty) begin
                if (model_q.size() == 0) begin
                    $error("[%0t] read while model is empty (rdata=%h)", $time, rdata);
                    errors++;
                end else begin
                    exp_data = model_q.pop_front();
                    if (rdata !== exp_data) begin
                        $error("[%0t] data mismatch: got %h expected %h", $time, rdata, exp_data);
                        errors++;
                    end
                end
                n_reads++;
            end else begin
                n_empty++;
            end
        end
    end

    // ------------------------------------------------------------------
    // Helpers (stimulus is driven on the falling edge to avoid races)
    // ------------------------------------------------------------------
    task automatic check(input bit cond, input string msg);
        if (!cond) begin
            $error("[%0t] CHECK FAILED: %s", $time, msg);
            errors++;
        end
    endtask

    task automatic apply_reset();
        winc   = 1'b0;
        rinc   = 1'b0;
        wdata  = '0;
        wrst_n = 1'b0;
        rrst_n = 1'b0;
        repeat (3) @(posedge wclk);
        repeat (3) @(posedge rclk);
        model_q.delete();
        @(negedge wclk) wrst_n = 1'b1;
        @(negedge rclk) rrst_n = 1'b1;
    endtask

    // Let pointers propagate through both synchronizers.
    task automatic settle();
        repeat (4) @(posedge wclk);
        repeat (4) @(posedge rclk);
    endtask

    task automatic write_word(input logic [DATA_WIDTH-1:0] d);
        @(negedge wclk);
        winc  = 1'b1;
        wdata = d;
        @(negedge wclk);
        winc  = 1'b0;
    endtask

    task automatic drain_n(input int n);
        @(negedge rclk);
        repeat (n) begin
            check(rempty === 1'b0, "unexpected empty while draining");
            rinc = 1'b1;
            @(negedge rclk);
        end
        rinc = 1'b0;
        settle();
        check(rempty === 1'b1, "FIFO should be empty after draining");
    endtask

    // ------------------------------------------------------------------
    // Tests
    // ------------------------------------------------------------------
    task automatic test_reset();
        $display("[%0t] TEST 1: reset values", $time);
        apply_reset();
        check(rempty === 1'b1, "rempty must be 1 after reset");
        check(wfull  === 1'b0, "wfull must be 0 after reset");
    endtask

    task automatic test_fill();
        int start;
        $display("[%0t] TEST 2: fill to full", $time);
        start = n_writes;
        @(negedge wclk);
        while (!wfull) begin
            winc  = 1'b1;
            wdata = DATA_WIDTH'($urandom);
            @(negedge wclk);
        end
        winc = 1'b0;
        check(n_writes - start == DEPTH,
              $sformatf("expected %0d writes before full, got %0d", DEPTH, n_writes - start));
        // overflow attempt must be ignored
        winc  = 1'b1;
        wdata = '1;
        @(negedge wclk);
        winc  = 1'b0;
        check(wfull === 1'b1, "wfull must stay high after overflow attempt");
        check(model_q.size() == DEPTH, "overflow write must not be accepted");
        settle();
        check(rempty === 1'b0, "rempty must be 0 when FIFO is full");
    endtask

    task automatic test_drain();
        int start;
        $display("[%0t] TEST 3: drain to empty", $time);
        start = n_reads;
        @(negedge rclk);
        while (!rempty) begin
            rinc = 1'b1;
            @(negedge rclk);
        end
        rinc = 1'b0;
        check(n_reads - start == DEPTH,
              $sformatf("expected %0d reads, got %0d", DEPTH, n_reads - start));
        // underflow attempt must be ignored
        rinc = 1'b1;
        @(negedge rclk);
        rinc = 1'b0;
        check(rempty === 1'b1, "rempty must stay high after underflow attempt");
        settle();
        check(wfull === 1'b0, "wfull must be 0 when FIFO is empty");
    endtask

    task automatic test_random(input int cycles, input int wr_pct, input int rd_pct);
        $display("[%0t] TEST 4: random simultaneous traffic (%0d cycles, wr %0d%%, rd %0d%%)",
                 $time, cycles, wr_pct, rd_pct);
        fork
            begin
                repeat (cycles) begin
                    @(negedge wclk);
                    winc  = ($urandom_range(99) < wr_pct);
                    wdata = DATA_WIDTH'($urandom);
                end
                @(negedge wclk) winc = 1'b0;
            end
            begin
                repeat (cycles) begin
                    @(negedge rclk);
                    rinc = ($urandom_range(99) < rd_pct);
                end
                @(negedge rclk) rinc = 1'b0;
            end
        join
        // drain whatever is left
        settle();
        @(negedge rclk);
        while (!rempty) begin
            rinc = 1'b1;
            @(negedge rclk);
        end
        rinc = 1'b0;
        settle();
        check(model_q.size() == 0, $sformatf("%0d words left in model after drain", model_q.size()));
    endtask

    task automatic test_reset_midstream();
        $display("[%0t] TEST 5: reset during traffic", $time);
        repeat (DEPTH / 2 + 1) write_word(DATA_WIDTH'($urandom));
        settle();
        check(rempty === 1'b0, "FIFO should hold data before reset");
        apply_reset();
        check(rempty === 1'b1, "rempty must be 1 after mid-stream reset");
        check(wfull  === 1'b0, "wfull must be 0 after mid-stream reset");
        // FIFO must be fully usable afterwards
        repeat (POST_RST_WORDS) write_word(DATA_WIDTH'($urandom));
        settle();
        drain_n(POST_RST_WORDS);
    endtask

    task automatic test_wraparound();
        $display("[%0t] TEST 6: pointer wrap-around (4 x fill/drain)", $time);
        repeat (4) begin
            test_fill();
            test_drain();
        end
    endtask

    initial begin
        $dumpfile("results/async_fifo.vcd");
        $dumpvars(0, tb_async_fifo);
        $display("async_fifo: DATA_WIDTH=%0d DEPTH=%0d wclk=%0.1fns rclk=%0.1fns",
                 DATA_WIDTH, DEPTH, 2*WCLK_HALF, 2*RCLK_HALF);

        test_reset();
        test_fill();
        test_drain();
        test_random(2000, 70, 40);   // write-heavy: many full events
        test_random(2000, 40, 70);   // read-heavy: many empty events
        test_random(2000, 50, 50);   // balanced
        test_reset_midstream();
        test_wraparound();

        $display("--------------------------------------------------");
        $display("writes accepted : %0d", n_writes);
        $display("reads accepted  : %0d", n_reads);
        $display("writes blocked by full : %0d", n_full);
        $display("reads blocked by empty : %0d", n_empty);
        if (errors == 0) $display("TEST PASSED");
        else             $display("TEST FAILED: %0d error(s)", errors);
        $display("--------------------------------------------------");
        $finish;
    end

    initial begin
        #10ms;
        $fatal(1, "timeout");
    end

endmodule
