// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_ce_frac.v -- fractional clock enable: ce is high for exactly NUM of every DEN clocks of clk, spread as evenly
// as a first-order accumulator spreads them.  Default: King and Balloon's 2.5 MHz speech CPU from the 24.576 MHz
// system clock, NUM / DEN = 625 / 6144 (exact against the nominal 24.576 MHz).
// Copied from scramble-tango rtl/tango/scr_ce_frac.v (the same authors).
module gx_ce_frac #(
    parameter integer W = 18,
    parameter [W-1:0] NUM = 18'd625,
    parameter [W-1:0] DEN = 18'd6144
) (
    input  wire clk,
    input  wire reset,
    output reg  ce
);
    reg [W-1:0] acc;

    // initial values for simulation
    initial begin
        acc = 0;
        ce  = 0;
    end

    always @(posedge clk) begin
        if (reset) begin
            acc <= 0;
            ce  <= 0;
        end else begin
            reg [W:0] sum;
            sum = {1'b0, acc} + {1'b0, NUM};
            if (sum >= {1'b0, DEN}) begin
                acc <= sum[W-1:0] - DEN;      // sum - DEN < DEN, so it fits in W bits
                ce  <= 1'b1;
            end else begin
                acc <= sum[W-1:0];
                ce  <= 1'b0;
            end
        end
    end

endmodule
