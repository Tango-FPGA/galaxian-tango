// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_addr_dec.v -- main CPU address decode (Galaxian manual p.22 zone 03: 8E 74139, 8P / 8N / 8M 74138), with the
// family's per-game maps (MAME galaxian.cpp:1730-1750 galaxian_map_base, :1804-1809 victoryc_map, :1826-1840
// mooncrst_map_base, :1874-1880 porter_map, :2949-2956 kingball_map).
// Combinational; every output is an active-high level.  The WEN qualification of writes is applied outside.
//
// sel = ~mreq_n & (map_moon ? a[15:14] == 2'b10 : a[15:14] == 2'b01)   (8E's half-decoder output feeding the 138s)
// blk = a[13:11], the 2K block inside the selected 16K:
//   0 CPU RAM, 1K mirrored at +0x400 (7N / 7P 2114 x2); ram_2k (Portman) makes a[10] a RAM address bit (2K).
//   1 nothing.   2 video RAM (vram_req = 8P Y2: sel & rfsh_n, any cycle type; rd / wr qualified below).
//   3 object RAM.   4 IN0 read / 9M write.   5 IN1 read / 9L write.   6 DIP read / 9N write.
//   7 watchdog clear (read) / 9J pitch write.
// 8P is enabled by RFSH, so vram_req is never active in a refresh cycle; 8N / 8M decode RD / WR, which are both
// high during refresh, so no read or write output is active then either.
// rom_rd = ~mreq_n & ~rd_n & (rom_4fff ? a < 0x5000 : a < 0x4000)   (Portman's ROM extends to 4FFF, MAME porter_map).
// Victory (ram_vic): a separate 2K RAM at 8000-87FF, ram_a = {1, a[10:0]}.  Otherwise ram_a = {0, ram_2k & a[10],
// a[9:0]}.
`default_nettype none
module gx_addr_dec (
    input  wire [15:0] a,
    input  wire        mreq_n,
    input  wire        rd_n,
    input  wire        wr_n,
    input  wire        rfsh_n,
    input  wire        map_moon,
    input  wire        rom_4fff,
    input  wire        ram_2k,
    input  wire        ram_vic,
    output wire        rom_rd,
    output wire        ram_rd,
    output wire        ram_wr,
    output wire [11:0] ram_a,
    output wire        vram_req,
    output wire        vram_rd,
    output wire        vram_wr,
    output wire        obj_rd,
    output wire        obj_wr,
    output wire        in0_oe,
    output wire        in1_oe,
    output wire        dip_oe,
    output wire        wdr,
    output wire        drv_we,
    output wire        snd_we,
    output wire        lat_we,
    output wire        pitch_we
);

    // Internal signals
    wire        mreq, rd, wr;
    wire        sel;
    wire [2:0]  blk;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0]  b;
    /* verilator lint_on UNUSEDSIGNAL */
    wire        vic;
    wire        rom_area;
    wire        ram_sel;
    // wire        vram_req; // output already defined

    // Compute control signals
    assign mreq = ~mreq_n;
    assign rd   = ~rd_n;
    assign wr   = ~wr_n;

    // Selector for 16-K region based on map_moon
    assign sel = mreq & (map_moon ? (a[15:14] == 2'b10) : (a[15:14] == 2'b01));

    // 2-K block inside the selected 16-K
    assign blk = a[13:11];

    // One-hot decode of blk when sel is 1
    assign b[0] = sel & (blk == 3'b000);
    /* verilator lint_off UNUSEDSIGNAL */
    assign b[1] = sel & (blk == 3'b001);
    /* verilator lint_on UNUSEDSIGNAL */
    assign b[2] = sel & (blk == 3'b010);
    assign b[3] = sel & (blk == 3'b011);
    assign b[4] = sel & (blk == 3'b100);
    assign b[5] = sel & (blk == 3'b101);
    assign b[6] = sel & (blk == 3'b110);
    assign b[7] = sel & (blk == 3'b111);

    // VIC RAM selection
    assign vic = ram_vic & mreq & (a[15:11] == 5'b10000);

    // ROM area detection
    assign rom_area = rom_4fff ? ((a[15:14]==2'b00) | (a[15:12]==4'b0100)) : (a[15:14]==2'b00);

    // RAM block selection
    assign ram_sel = b[0] | vic;

    // Outputs
    assign rom_rd = mreq & rd & rom_area;
    assign ram_rd = ram_sel & rd;
    assign ram_wr = ram_sel & wr;

    // RAM address
    assign ram_a = vic ? {1'b1, a[10:0]} : {1'b0, (ram_2k & a[10]), a[9:0]};

    // Video RAM request
    assign vram_req = b[2] & rfsh_n;
    assign vram_rd  = vram_req & rd;
    assign vram_wr  = vram_req & wr;

    // Object RAM
    assign obj_rd = b[3] & rd;
    assign obj_wr = b[3] & wr;

    // Input enable outputs
    assign in0_oe = b[4] & rd;
    assign in1_oe = b[5] & rd;
    assign dip_oe = b[6] & rd;
    assign wdr    = b[7] & rd;

    // Write-enable outputs
    assign drv_we   = b[4] & wr;
    assign snd_we   = b[5] & wr;
    assign lat_we   = b[6] & wr;
    assign pitch_we = b[7] & wr;

endmodule
`default_nettype wire
