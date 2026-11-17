// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_latch_259.v -- one 74LS259 8-bit addressable latch, as the Galaxian board uses it for 9N (control), 9L (sound)
// and 9M (driver / background DAC) (Galaxian manual p.22 zones 05, 11-12).
// The CPU writes one bit at a time: a (A2..A0) picks the bit, d (D0) is its value.
// At each clk edge: if clr (the game /RESET, high = clear) all eight bits clear; else if we (the decoded write level)
// q[a] <= d; else q holds.  clr wins over we.
`default_nettype none
module gx_latch_259 (
    input  wire       clk,
    input  wire       clr,
    input  wire       we,
    input  wire [2:0] a,
    input  wire       d,
    output reg  [7:0] q
);

    // Synchronous logic for the 74LS259 latch
    always @(posedge clk) begin
        if (clr) begin
            q <= 8'b0;
        end else if (we) begin
            // Update only the selected bit, keep others
            q <= (q & ~(8'b1 << a)) | ({7'b0, d} << a);
        end
        // else: hold (no assignment needed)
    end

endmodule
`default_nettype wire
