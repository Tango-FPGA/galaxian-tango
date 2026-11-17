// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_vid_addr.v -- video addressing (Galaxian manual p.22 zones 06-08, 10): the flip XORs (7486: 8HB..128HB,
// 1VF..128VF), the object-RAM read address (5E/4E, 6J 74157), the V + HPOSI adder (4N/5N 74283) and its latch 2M
// (74273), the sprite flip-y XOR (1M), the video-RAM read address, the sprite code latch 4L (74273), the colour latch
// (6R 74175; 8 bits kept), the shifter load gate and the per-8-pixel latch 6P (74377).
//
// All outputs marked (c) are combinational from h, v, the flips and the latches below; the RAM read addresses are
// never re-registered (the RAMs register them).  hposi is the object-RAM read data, vram_q the video-RAM read data.
//   col[4:0] = (hflip & ~h[8]) ? ~h[7:3] : h[7:3]        (8HB..128HB; flip-x only in the display)
//   vf[7:0]  = vflip ? ~v : v                            (1VF..128VF)
//   hf8 = col[0], vf1 = vf[0]                            (c, star blink)
//   objram_va (c): display (h[8] = 0): {2'b00, col, h[2]}  -- column scroll byte (h[2] = 0) or colour byte (1);
//     blanking, sprite n = h[6:4]: {2'b01, h[3] & h[1], n, h[2], h[1]}  -- 0x40 + 4n + {h[2],h[1]}, or for
//     h[3] = h[1] = 1 the shell/missile entry 0x60 + 4n + 2h[2] + 1 (MAME galaxian_v.cpp:105-140, 195-213).
//   sum = vf + hposi (8 bits); msld_n (c) = (sum != 8'hFF)  (shell/missile match, MAME :143).
//   m2 (2M): if vblank, m2 <= 0; else at vpl, m2 <= sum.
//   ol (4L): at objd, ol <= hposi  (ol[5:0] sprite code, ol[6] flip-x, ol[7] flip-y).
//   cl (colour latch): at coll, cl <= hposi; col5 = cl[5]  (Moon Quasar bank).
//   m1 = m2[3:0] ^ {4{h[8] & ol[7]}}  (sprite flip-y, blanking only); gfx_row (c) = m1[2:0]; vhalf = m1[3].
//   vram_va (c) = {m2[7:4], vhalf, col}  (row * 32 + column; MAME :182-193).
//   gfx_code (c) = h[8] ? {ol[5:0], vhalf, ol[6] ^ h[3]} : vram_q  (sprite: 4 cells of 8x8, left/right by 8H).
//   srld (c) = ld & (cblank_n | m2[7:4] == 4'hF): every /LD in the display; in blanking only when the sprite row
//     matches, MAME ((V + vpos) & 0xf0) == 0xf0 (:142).  In VBLANK lines m2 = 0, so nothing loads.
//   6P, at ld_stb: hflip2x <= h[8] ? ol[6] : hflip;  hflip1x <= ~h[8] & hflip;  cblnx <= cblank_n;
//     c256hnx <= ~h[8];  cd <= cl[2:0].
// ce_pr is not used: every capture is on a strobe that already contains its enable.  The board's 6R keeps 3 bits;
// cl latches all 8 so that bit 5 can serve the Moon Quasar bank; cl[7:6] and cl[4:3] are unused.
// reset (synchronous): m2, ol, cl and 6P cleared.
`default_nettype none
module gx_vid_addr (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    input  wire [8:0] h,
    input  wire [7:0] v,
    input  wire       hflip,
    input  wire       vflip,
    input  wire       vblank,
    input  wire       cblank_n,
    input  wire       vpl,
    input  wire       objd,
    input  wire       coll,
    input  wire       ld,
    input  wire       ld_stb,
    input  wire [7:0] hposi,
    input  wire [7:0] vram_q,
    output wire [7:0] objram_va,
    output wire [9:0] vram_va,
    output wire       msld_n,
    output wire [7:0] gfx_code,
    output wire [2:0] gfx_row,
    output wire       srld,
    output wire       col5,
    output reg        hflip2x,
    output reg        hflip1x,
    output reg        cblnx,
    output reg        c256hnx,
    output reg  [2:0] cd,
    output wire       hf8,
    output wire       vf1
);
    // internal combinational signals
    wire [4:0] col;
    wire [7:0] vf;
    wire [7:0] sum;
    wire [3:0] m1;
    wire vhalf;

    // registers
    reg [7:0] m2 = 8'd0;
    reg [7:0] ol = 8'd0;
    reg [7:0] cl = 8'd0;

    // unused inputs sink
    wire unused_ok = &{1'b0, ce_pr, h[0], cl[7:6], cl[4:3]};

    // combinational logic
    assign col = (hflip && ~h[8]) ? ~h[7:3] : h[7:3];
    assign vf = vflip ? ~v : v;
    assign sum = vf + hposi;
    assign m1 = m2[3:0] ^ {4{h[8] & ol[7]}};
    assign vhalf = m1[3];
    assign hf8 = col[0];
    assign vf1 = vf[0];
    assign objram_va = h[8] ? {2'b01, h[3] & h[1], h[6:4], h[2], h[1]} : {2'b00, col, h[2]};
    assign msld_n = (sum != 8'hFF);
    assign gfx_row = m1[2:0];
    assign vram_va = {m2[7:4], vhalf, col};
    assign gfx_code = h[8] ? {ol[5:0], vhalf, ol[6] ^ h[3]} : vram_q;
    assign srld = ld & (cblank_n | (m2[7:4] == 4'hF));
    assign col5 = cl[5];

    // sequential logic
    always @(posedge clk) begin
        if (reset) begin
            m2 <= 8'd0;
            ol <= 8'd0;
            cl <= 8'd0;
            hflip2x <= 1'b0;
            hflip1x <= 1'b0;
            cblnx <= 1'b0;
            c256hnx <= 1'b0;
            cd <= 3'd0;
        end else begin
            // m2
            if (vblank)
                m2 <= 8'd0;
            else if (vpl)
                m2 <= sum;
            // ol
            if (objd)
                ol <= hposi;
            // cl
            if (coll)
                cl <= hposi;
            // 6P updates
            if (ld_stb) begin
                hflip2x <= h[8] ? ol[6] : hflip;
                hflip1x <= ~h[8] & hflip;
                cblnx <= cblank_n;
                c256hnx <= ~h[8];
                cd <= cl[2:0];
            end
        end
    end
endmodule
`default_nettype wire
