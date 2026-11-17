// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_missile.v -- the shell and missile counters (Galaxian manual p.22 zone 10: 4S/5S and 4R/5R 74LS161, 5P 7474,
// 4P 7410).  Each counter is loaded with an H offset during blanking, counts across the display, and shows its
// object while the count is in the window.  MAME galaxian_v.cpp:76-100,1182-1196.
// Per counter (c, arm): shell loads on sld, missile on mld (both ce_pf strobes):
//   if load: c <= hposi, arm <= 1;
//   else at ce_pf, if cblnx: c <= c + 1, and if c == LAST or c == 8'hFF then arm <= 0  (5P cleared at the end of the
//   run, so a counter that wraps cannot show a second run).
//   out (c) = arm & win(c): changes on the ce_pf edge, as the 4P output does.
// Galaxian: win(c) = c[7:2] == 6'h3F (FC..FF, 4 pixels), LAST = 8'hFF.
// bullet_az (Azurian): win(c) = c[7:1] == 7'h7D (FA, FB, 2 pixels), LAST = 8'hFB (MAME scramble_draw_bullet,
//   galaxian_v.cpp:1227-1240).  The clear on the wrap (c == 8'hFF) matters only here: a counter loaded with FC..FF
//   wraps before it reaches FA and shows nothing, as MAME clips x = 249 - hpos < 0.
// The output for pixel h is output pixel P(h): a shell shows at screen x = 251 - hpos .. 254 - hpos.
// reset (synchronous): both counters and arms cleared.
`default_nettype none
module gx_missile (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pf,
    input  wire       cblnx,
    input  wire       sld,
    input  wire       mld,
    input  wire [7:0] hposi,
    input  wire       bullet_az,
    output wire       shell,
    output wire       missile
);
    // Registers
    reg [7:0] cs, cm;
    reg as, am;

    // Combinational helpers
    wire [7:0] last = bullet_az ? 8'hFB : 8'hFF;
    wire win_cs = bullet_az ? (cs[7:1] == 7'h7D) : (cs[7:2] == 6'h3F);
    wire win_cm = bullet_az ? (cm[7:1] == 7'h7D) : (cm[7:2] == 6'h3F);

    // Combinational outputs
    assign shell   = as & win_cs;
    assign missile = am & win_cm;

    // Sequential logic
    always @(posedge clk) begin
        if (reset) begin
            cs <= 8'h00;
            cm <= 8'h00;
            as <= 1'b0;
            am <= 1'b0;
        end else begin
            // Shell channel
            if (sld) begin
                cs <= hposi;
                as <= 1'b1;
            end else if (ce_pf && cblnx) begin
                cs <= cs + 8'h01;
                if (cs == last || cs == 8'hFF)
                    as <= 1'b0;
            end

            // Missile channel
            if (mld) begin
                cm <= hposi;
                am <= 1'b1;
            end else if (ce_pf && cblnx) begin
                cm <= cm + 8'h01;
                if (cm == last || cm == 8'hFF)
                    am <= 1'b0;
            end
        end
    end

endmodule
`default_nettype wire
