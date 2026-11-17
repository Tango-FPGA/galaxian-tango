// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_hv.v -- Galaxian video timing (Galaxian manual p.22 zone 05: 6C, 3A, 4A, 5A, 6A, 6F, 5C, 5D, 3D): the 9-bit H
// counter, 8-bit V counter, syncs and blanks, advanced on ce_pr (the 6.144 MHz pixel clock's rising edge).
// 384 x 264 raster, 60.606 Hz.
//
// h counts 0..255 (h[8] = 0, the 256 visible pixels), then 0x180..0x1FF (h[8] = 1, horizontal blanking), then 0.
// hsync: high for h 0x1B0..0x1CF (32 pixels).
// v_inc (combinational): ce_pr while h = 0x1AF; on it v advances 0..255, then 0x1F8..0x1FF (the 9-bit v9), then 0:
// 264 lines.  vsync = v9[8] (low byte 248..255).
// vblank (5C): set when v steps 239 -> 240, cleared when v steps 15 -> 16 (224 visible lines); vblank_rise
// (combinational) = v_inc while v = 239.
// hblank_ff (3D, the HBLANK flop that gates the CPU WAIT): high for h 0x182..0x1F9.  At ce_pr: if the next h is below
// 256 it clears; else if h[1:0] = 2'b01 it takes ~&h[6:3]; else it holds.
// cblank_n = ~vblank & ~h[8].
// reset (synchronous, system reset only): h = 0, v9 = 0, vblank = 1, hsync = 0, hblank_ff = 0.
`default_nettype none
module gx_hv (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    output reg  [8:0] h,
    output wire [7:0] v,
    output wire       vsync,
    output reg        hsync,
    output reg        vblank,
    output reg        hblank_ff,
    output wire       cblank_n,
    output wire       v_inc,
    output wire       vblank_rise
);

    // Internal register for the 9-bit V counter
    reg [8:0] v9;

    // Combinational outputs
    assign v          = v9[7:0];
    assign vsync      = v9[8];
    assign cblank_n   = ~vblank & ~h[8];
    assign v_inc      = ce_pr & (h == 9'h1AF);
    assign vblank_rise= v_inc & (v9[7:0] == 8'hEF);

    always @(posedge clk) begin
        if (reset) begin
            h          <= 9'h0;
            v9         <= 9'h0;
            hsync      <= 1'b0;
            vblank     <= 1'b1;
            hblank_ff  <= 1'b0;
        end else if (ce_pr) begin
            // Next H value
            reg [8:0] next_h;
            reg next_hsync;
            reg next_hblank_ff;
            reg [8:0] next_v9;
            reg next_vblank;

            if (h == 9'hFF) next_h = 9'h180; // wrap to 384
            else             next_h = h + 9'b1;

            // H-sync update
            if (h == 9'h1AF) next_hsync = 1'b1;
            else if (h == 9'h1CF) next_hsync = 1'b0;
            else                 next_hsync = hsync;

            // H-blank flop update
            if (next_h[8] == 1'b0) begin
                next_hblank_ff = 1'b0;
            end else if (h[1:0] == 2'b01) begin
                next_hblank_ff = ~(&h[6:3]);
            end else begin
                next_hblank_ff = hblank_ff;
            end

            // V counter update
            if (v_inc) begin
                if (v9 == 9'hFF) next_v9 = 9'h1F8; // wrap to 504
                else             next_v9 = v9 + 9'b1;
            end else begin
                next_v9 = v9;
            end

            // V-blank update
            if (v_inc) begin
                if (v9[7:0] == 8'hEF) next_vblank = 1'b1;
                else if (v9[7:0] == 8'h0F) next_vblank = 1'b0;
                else next_vblank = vblank;
            end else begin
                next_vblank = vblank;
            end

            // Register updates
            h          <= next_h;
            hsync      <= next_hsync;
            hblank_ff  <= next_hblank_ff;
            v9         <= next_v9;
            vblank     <= next_vblank;        end
    end

endmodule
`default_nettype wire
