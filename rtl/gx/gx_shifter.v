// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_shifter.v -- the two 8-bit graphics shift registers (Galaxian manual p.22 zones 09-10: 74LS194 pairs 2H/2J for
// plane 1, 2K/2L for plane 0) and their direction mux (3L 74157, from the flip).
// At ce_pr: if srld, both registers load (s1 <= d_hi, s0 <= d_lo); else both shift one place toward the output end,
// filling with 0 (the 74194 serial inputs are tied low): toward bit 7 when flip = 0, toward bit 0 when flip = 1.
// raw (combinational) = flip ? {s1[0], s0[0]} : {s1[7], s0[7]}.  reset (synchronous) clears both registers.
`default_nettype none
module gx_shifter (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    input  wire       srld,
    input  wire       flip,
    input  wire [7:0] d_hi,
    input  wire [7:0] d_lo,
    output wire [1:0] raw
);
    // Internal shift registers
    reg [7:0] s1;
    reg [7:0] s0;

    // Synchronous logic
    always @(posedge clk) begin
        if (reset) begin
            s1 <= 8'd0;
            s0 <= 8'd0;
        end else if (ce_pr) begin
            if (srld) begin
                s1 <= d_hi;
                s0 <= d_lo;
            end else if (flip == 1'b0) begin
                // Shift toward bit 7 (left shift)
                s1 <= {s1[6:0], 1'b0};
                s0 <= {s0[6:0], 1'b0};
            end else begin
                // Shift toward bit 0 (right shift)
                s1 <= {1'b0, s1[7:1]};
                s0 <= {1'b0, s0[7:1]};
            end
        end
    end

    // Combinational output
    assign raw = flip ? {s1[0], s0[0]} : {s1[7], s0[7]};
endmodule
`default_nettype wire
