// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// galaxian_clocks.v -- the Galaxian core's one clock: clk_sys, 24.576 MHz (+11 ppm) from the 50 MHz oscillator
// (rtl/pll_galaxian_mod.v has the divider search).  PLL_INIT as every Tango core's clocks: the 138K's PLL does not
// lock reliably without it.  It is the framework's CLK_SYS.  The board's 12.288 / 6.144 / 3.072 / 1.536 MHz rates
// are clock enables made from it (rtl/gx/gx_ce.v); King and Balloon's 2.5 MHz speech CPU uses a fractional enable
// (rtl/gx/gx_ce_frac.v).
// TANGO_SIM: clk50 is clk_sys (a testbench drives it directly), with a short lock delay.
// Adapted from scramble-tango rtl/scramble_clocks.v (the same authors).
`default_nettype none
module galaxian_clocks (
    input  wire clk50,
    output wire clk_sys,
    output wire locked
);
`ifdef TANGO_SIM
    assign clk_sys = clk50;
    reg [3:0] lk = 4'd0;
    always @(posedge clk50) if (!lk[3]) lk <= lk + 4'd1;
    assign locked = lk[3];
`else
    wire pll_lock, pll_rst;
    wire [5:0] icpsel; wire [2:0] lpfres;
    pll_galaxian_MOD u_pll (.clkout0(clk_sys), .lock(pll_lock), .clkin(clk50),
        .reset(pll_rst), .icpsel(icpsel), .lpfres(lpfres), .lpfcap(2'b00));
    PLL_INIT u_pll_init (.CLKIN(clk50), .I_RST(1'b0), .O_RST(pll_rst),
        .PLLLOCK(pll_lock), .O_LOCK(locked), .ICPSEL(icpsel), .LPFRES(lpfres));
    defparam u_pll_init.CLK_PERIOD = 20;     // 50 MHz clkin
    defparam u_pll_init.MULTI_FAC  = 29;     // = MDIV_SEL (pll_galaxian_mod.v); inside PLL_INIT's 17..34 band
`endif
endmodule
`default_nettype wire
