// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_pix_combine.v -- sprite-over-tile and sprite-over-sprite priority: the 7400/7408/7420 gate network in front of
// the 6M colour latch and the line-buffer data inputs (Galaxian manual p.22 zones 11-12).  Combinational.
//
// raw: shifter pixel; cd: 6P colour (tile column colour in the display, sprite colour in blanking);
// rv/rc: the stored line-buffer pixel and colour (1U).
//   vid = (rv != 0) ? rv : raw
//   col = (rc != 0) ? rc : ((raw != 0) ? cd : 3'd0)
// The pixel and the colour have separate priorities: a stored colour wins even when the stored pixel is 0, and a
// stored pixel wins even when its colour is 0.  In blanking this is the line-buffer write-back (the first-written
// sprite pixel wins, so lower sprite numbers have priority; MAME galaxian_v.cpp:569-572); in the display it puts the
// sprite over the tile.
`default_nettype none
module gx_pix_combine (
    input  wire [1:0] raw,
    input  wire [2:0] cd,
    input  wire [1:0] rv,
    input  wire [2:0] rc,
    output wire [1:0] vid,
    output wire [2:0] col
);

    // Combinational logic
    assign vid = (rv != 2'b00) ? rv : raw;
    assign col = (rc != 3'b000) ? rc : ((raw != 2'b00) ? cd : 3'b000);


endmodule
`default_nettype wire
