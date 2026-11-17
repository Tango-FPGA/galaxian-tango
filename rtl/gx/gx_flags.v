// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_flags.v -- the game byte (MiSTer's mod byte, .mra index 1) decoded to the per-game board flags.
// (mod values: Arcade-Galaxian.sv:308-330; layouts :409-445; rotation :437 and MAME's
// ROT270 sets).  Combinational.  Codes 12..FF decode as 00 (Galaxian).
//   mod  game(s)                  differences from Galaxian (00)
//   00   galaxian and its clones  --
//   01   mooncrgx                 gfx_mode MOONCR, rot_ccw
//   02   azurian                  bullet_az, layout AZ
//   03   blkhole, 04 catacomb     --
//   05   Portman (porter)         map_moon, nmi_q0, rom_mode 3, rom_4fff, ram_2k, gfx_mode PISCES, mix_moon,
//                                 layout POR, porter (gfx planes and CLUT one image block higher)
//   06   devilfsg                 irq_int, rom_mode 1, gfx_mode DEVIL, layout DEV, rot_ccw
//   07   kingball(j)              map_moon (NMI ON stays Q1), mix_moon, kb, stars_disp 0
//   08   mrdonight, cleansweep    layout MRDO
//   09   omegab                   rot_ccw
//   0A   orbitron                 rom_mode 2, layout ORB, rot_ccw
//   0B   pisces, omni, piscesb    gfx_mode PISCES, pisces (coin on IN0 bit 1)
//   0C   uniwars and clones       gfx_mode PISCES
//   0D   victorycb                ram_vic, stars_disp 0, layout VIC, rot_ccw
//   0E   warofbug(u)              layout WOB
//   0F   moonqsr                  map_moon, nmi_q0, mq_dec, gfx_mode MQSR, mix_moon, mix_mc1 (rotation: MAME ROT90, as
//                                 Galaxian)
//   10   tripledr                 layout DEV
//   11   luctoday                 layout DEV, rot_ccw
// gfx_mode: 0 GAL, 1 MOONCR, 2 DEVIL, 3 PISCES, 4 MQSR.  layout: 0 GAL, 1 AZ, 2 ORB, 3 DEV, 4 MRDO, 5 VIC, 6 WOB,
// 7 POR.  rom_mode: 0 none, 1 Devil Fish, 2 Orbitron, 3 Portman.  mix_mc1: the sound of Nichibutsu's MC-1 board
// (MCS PDF 20), with mix_moon: gx_snd_mix board MC1, gx_snd_bg's C17-C19 0.1 uF and gx_snd_hit's FLASH (mc1).
`default_nettype none
module gx_flags (
    input  wire [7:0] mod,
    output reg        map_moon,
    output reg        nmi_q0,
    output reg        irq_int,
    output reg  [1:0] rom_mode,
    output reg        rom_4fff,
    output reg        ram_2k,
    output reg        ram_vic,
    output reg        mq_dec,
    output reg  [2:0] gfx_mode,
    output reg        stars_disp,
    output reg        mix_moon,
    output reg        mix_mc1,
    output reg        bullet_az,
    output reg        kb,
    output reg  [3:0] layout,
    output reg        pisces,
    output reg        porter,
    output reg        rot_ccw
);
    always @* begin
        map_moon = 1'b0; nmi_q0 = 1'b0; irq_int = 1'b0; rom_mode = 2'd0; rom_4fff = 1'b0; ram_2k = 1'b0;
        ram_vic = 1'b0; mq_dec = 1'b0; gfx_mode = 3'd0; stars_disp = 1'b1; mix_moon = 1'b0; mix_mc1 = 1'b0;
        bullet_az = 1'b0; kb = 1'b0; layout = 4'd0; pisces = 1'b0; porter = 1'b0; rot_ccw = 1'b0;
        case (mod)
            8'h01: begin gfx_mode = 3'd1; rot_ccw = 1'b1; end
            8'h02: begin bullet_az = 1'b1; layout = 4'd1; end
            8'h05: begin map_moon = 1'b1; nmi_q0 = 1'b1; rom_mode = 2'd3; rom_4fff = 1'b1; ram_2k = 1'b1;
                         gfx_mode = 3'd3; mix_moon = 1'b1; layout = 4'd7; porter = 1'b1; end
            8'h06: begin irq_int = 1'b1; rom_mode = 2'd1; gfx_mode = 3'd2; layout = 4'd3; rot_ccw = 1'b1; end
            8'h07: begin map_moon = 1'b1; mix_moon = 1'b1; kb = 1'b1; stars_disp = 1'b0; end
            8'h08: begin layout = 4'd4; end
            8'h09: begin rot_ccw = 1'b1; end
            8'h0A: begin rom_mode = 2'd2; layout = 4'd2; rot_ccw = 1'b1; end
            8'h0B: begin gfx_mode = 3'd3; pisces = 1'b1; end
            8'h0C: begin gfx_mode = 3'd3; end
            8'h0D: begin ram_vic = 1'b1; stars_disp = 1'b0; layout = 4'd5; rot_ccw = 1'b1; end
            8'h0E: begin layout = 4'd6; end
            8'h0F: begin map_moon = 1'b1; nmi_q0 = 1'b1; mq_dec = 1'b1; gfx_mode = 3'd4; mix_moon = 1'b1;
                         mix_mc1 = 1'b1; end
            8'h10: begin layout = 4'd3; end
            8'h11: begin layout = 4'd3; rot_ccw = 1'b1; end
            default: ;
        endcase
    end
endmodule
`default_nettype wire
