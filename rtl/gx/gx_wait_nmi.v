// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_wait_nmi.v -- the main CPU's WAIT, the video-RAM write enable, NMI / INT and the watchdog (Galaxian manual p.22
// zone 02: 6S 7474 x2, 3R 7402, 6T 74393 first half, 8L 7400, 6N 7402; zone 05: 6F second half).
//
//
// WAIT: on the board 6S samples NOR(/VRAM, HBLANK) on 1H rising and is cleared by /VBLANK; its /Q is the Z80's
// /WAIT, so a video-RAM access during the visible part of a line waits until the HBLANK window (h 0x182..0x1F9).
// Here wait_req is sampled at ce_wait (1H falling, half a CPU cycle after ce_cpu): the T80 asserts MREQ_n from the
// T1->T2 edge, so its first sample point is mid-T2, and HBLANK changes only on 2H rising, so the sampled value equals
// the board's.  The main T80se is built with T2Write = 1, so writes wait as well as reads.
//   wait_n = ~(wait_req & ~vblank) & ~cpu_hold      (cpu_hold: hi-score / OSD pause)
// WEN (combinational): the board's second 6S gates the 8M write strobes, so a waited video-RAM write commits only in
// the blanking window: wen = ~(vram_req & ~hblank_ff & ~vblank).
// NMI (6F second half: D = GND, CK = VBLANK, PR = NMI ON): q is preset while nmi_on = 0 and cleared by vblank_rise.
// Devil Fish routes the same flop to INT instead (irq_int).
// Watchdog (6T first half, CKA = VBLANK rising, CLR = a read of 7800 / B800): counts vblank_rise; bit 3 drives the
// game reset, and 6T is not cleared by that reset, so a watchdog reset lasts 8 frames (counts 8..15) and then
// releases.  cpu_hold and wd_off stop the count (a paused CPU cannot service the watchdog).
// game_reset (combinational) = reset | wd[3]: to the T80 and the 9N / 9L / 9M latch clears.
// reset (synchronous, system reset): wait_req = 0, q = 1, wd = 0.
`default_nettype none
module gx_wait_nmi (
    input  wire clk,
    input  wire reset,
    input  wire ce_wait,
    input  wire vram_req,
    input  wire hblank_ff,
    input  wire vblank,
    input  wire vblank_rise,
    input  wire nmi_on,
    input  wire irq_int,
    input  wire wdr,
    input  wire cpu_hold,
    input  wire wd_off,
    output wire wait_n,
    output wire wen,
    output wire nmi_n,
    output wire int_n,
    output wire game_reset
);
    reg       wait_req;
    reg       q;
    reg [3:0] wd;

    always @(posedge clk)
        if (reset)        wait_req <= 1'b0;
        else if (ce_wait) wait_req <= vram_req & ~hblank_ff & ~vblank;

    always @(posedge clk)
        if (reset || !nmi_on) q <= 1'b1;
        else if (vblank_rise) q <= 1'b0;

    always @(posedge clk)
        if (reset || wdr)                            wd <= 4'd0;
        else if (vblank_rise && !cpu_hold && !wd_off) wd <= wd + 4'd1;

    assign wait_n     = ~(wait_req & ~vblank) & ~cpu_hold;
    assign wen        = ~(vram_req & ~hblank_ff & ~vblank);
    assign nmi_n      = irq_int ? 1'b1 : q;
    assign int_n      = irq_int ? q : 1'b1;
    assign game_reset = reset | wd[3];
endmodule
`default_nettype wire
