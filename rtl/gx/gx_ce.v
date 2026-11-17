// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_ce.v -- the board's clock rates as one-cycle enables on clk_sys (24.576 MHz = 4/3 x the board's 18.432 MHz
// crystal).  The board divides its crystal by 3 for the 6.144 MHz pixel clock 6M and runs the Z80 on 1H, 3.072 MHz
// (Galaxian manual p.22, the 18.432 MHz oscillator and its 74107 divider); the star/noise LFSR runs at 12.288 MHz
// and the pitch counter at 1.536 MHz.  One 4-bit counter makes all four, so their phases are fixed against each
// other: each enable is high on the last clk_sys cycle of its period, and every slower enable coincides with the
// faster ones.
//   ce_12m: every 2nd cycle   ce_6m: every 4th   ce_3m: every 8th   ce_1m5: every 16th
`default_nettype none
module gx_ce (
    input  wire clk,
    input  wire reset,
    output wire ce_12m,
    output wire ce_6m,
    output wire ce_3m,
    output wire ce_1m5
);
    reg [3:0] div;

    always @(posedge clk)
        if (reset) div <= 4'd0;
        else       div <= div + 4'd1;

    assign ce_12m = div[0];
    assign ce_6m  = &div[1:0];
    assign ce_3m  = &div[2:0];
    assign ce_1m5 = &div[3:0];
endmodule
`default_nettype wire
