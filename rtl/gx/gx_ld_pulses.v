// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_ld_pulses.v -- the video load/latch strobes and the 3D shell-match flop (Galaxian manual p.22 zone 05 bottom:
// 74LS139 decoders 4C/4D, 5D 7410, 5C 7474 (2nd half), 3D 7474 (1st half)).
//
// The board gates 4D(1st) with h1d, 1H delayed half a pixel by 5C on /6MHZ, so its outputs change in the middle of a
// pixel: their active (rising) edges fall on ce_pf.  The strobes are decoded from h directly; that gives the same
// pulses.  "h" is the H count during the pixel whose closing ce_pf / ce_pr edge is the event.
//   vpl    = ce_pf & h[2:0] == 3'b001                       4D Y0      /VPL      (MAME galaxian_v.cpp:171)
//   coll   = ce_pf & h[2:0] == 3'b101                       4D Y2      /COL L    (:172)
//   objd   = ce_pf & h[8] & h[3:0] == 4'b0011               4C Y2      /OBJ DATA L (:175)
//   mstb   = ce_pf & h[8] & h[3:0] == 4'b1011               4C Y3      3D clock, MSLD latched (:117)
//   ld     = h[2:0] == 3'b111 (level)                       5D         /LD       (:173)
//   ld_stb = ce_pr & ld
//   cntr_clr = ce_pr & ~h[8] & h[3:0] == 4'b0111 & ~c256hnx 4D(2nd) Y0, 74163 synchronous clear (:174)
//   cntr_ld  = ce_pr &  h[8] & h[3:0] == 4'b0111            4D(2nd) Y2 /CNTR LD (:176)
//   sld    = ce_pf & h[8] & h[3:0] == 4'hF & h[6:4] != 3'b111 & ~q3d   4C(2nd) Y1  /SLD (:177)
//   mld    = ce_pf & h == 9'h1FF & ~q3d                     4C(2nd) Y0 /MLD      (:178)
// q3d (3D, D = MSLD, CK = 4C Y3, PR = /VBLANK): if vblank, q3d <= 1; else at mstb, q3d <= msld_n.  So no sld/mld
// fires on a VBLANK line, and a shell (missile) loads only when V + its vpos = 0xFF at h = 0x18B + 16n (0x1FB).
// h1d (5C, debug only): at ce_pf, h1d <= h[0].
// Per blanking line the strobes fire at: vpl 0x181 + 8k; coll 0x185 + 8k; objd 0x183 + 16n; mstb 0x18B + 16n;
// cntr_ld 0x187 + 16n; sld 0x18F + 16n (n = 0..6, on a match); mld 0x1FF (on a match).
// reset (synchronous): q3d = 1, h1d = 0.
`default_nettype none
module gx_ld_pulses (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    input  wire       ce_pf,
    input  wire [8:0] h,
    input  wire       vblank,
    input  wire       msld_n,
    input  wire       c256hnx,
    output wire       vpl,
    output wire       coll,
    output wire       objd,
    output wire       mstb,
    output wire       ld,
    output wire       ld_stb,
    output wire       cntr_clr,
    output wire       cntr_ld,
    output wire       sld,
    output wire       mld,
    output reg        h1d
);

    // Internal register for 3D shell-match state
    reg q3d;

    // Combinational outputs
    assign vpl     = ce_pf & (h[2:0] == 3'b001);
    assign coll    = ce_pf & (h[2:0] == 3'b101);
    assign objd    = ce_pf & h[8] & (h[3:0] == 4'b0011);
    assign mstb    = ce_pf & h[8] & (h[3:0] == 4'b1011);
    assign ld      = (h[2:0] == 3'b111);
    assign ld_stb  = ce_pr & ld;
    assign cntr_clr = ce_pr & ~h[8] & (h[3:0] == 4'b0111) & ~c256hnx;
    assign cntr_ld  = ce_pr & h[8] & (h[3:0] == 4'b0111);
    assign sld     = ce_pf & h[8] & (h[3:0] == 4'hF) & (h[6:4] != 3'b111) & ~q3d;
    assign mld     = ce_pf & (h == 9'h1FF) & ~q3d;

    // Sequential logic
    always @(posedge clk) begin
        if (reset) begin
            q3d <= 1'b1;
            h1d <= 1'b0;
        end else begin
            // q3d update
            if (vblank) begin
                q3d <= 1'b1;
            end else if (mstb) begin
                q3d <= msld_n;
            end
            // h1d update
            if (ce_pf) begin
                h1d <= h[0];
            end
        end
    end

endmodule
`default_nettype wire
