// -----------------------------------------------------------------------------
// sync_2ff
// Two-flop synchronizer for a multi-bit Gray-coded pointer. Only one bit of a
// Gray-code value changes per increment, so synchronizing the whole bus with a
// plain 2-FF chain is CDC-safe.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module sync_2ff #(
    parameter int WIDTH = 4
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] d,
    output logic [WIDTH-1:0] q
);

    logic [WIDTH-1:0] meta;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            meta <= '0;
            q    <= '0;
        end else begin
            meta <= d;
            q    <= meta;
        end
    end

endmodule
