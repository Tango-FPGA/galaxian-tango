// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_linebuf_ctl.v -- sprite line-buffer control (Galaxian manual p.22 zones 10-13: 4T/5T 74LS163 counter, the
// 27LS00 256 x 5 RAM's address/data/write, 1U 74174 read latch).
// The RAM itself is outside (port A write: lb_addr/lb_d/lb_we; port B read: lb_addr -> lb_q, registered, so the data
// of the address presented in d0 is valid in d1).  Contents are stored in true polarity {col[2:0], vid[1:0]}.
//
// Counter cnt (74163, synchronous clear and load, clocked by 6MHZ), at ce_pr:
//   cntr_clr -> 0 (first /LD of the display, h = 7, so cnt = 0 at h = 8, screen x = 0);
//   else cntr_ld -> hposi (sprite X, object-RAM entry 0x43 + 4n, at h = 0x187 + 16n);
//   else cnt + 1.
// lb_addr (c) = hflip1x ? ~cnt : cnt  (display read mirrored under screen flip-x; hflip1x = 0 in blanking).
// 1U, at ce_pf: {rc, rv} <= lb_q  (the stored pixel of this pixel's lb_addr).
// Write, once per pixel, in the clk after ce_pf (lb_we = ce_pf):
//   display window (c256hnx = 1): lb_d = 0, the buffer is cleared as it is read (MAME galaxian_v.cpp:569-571);
//   blanking: lb_d = {cmb_col, cmb_vid}, the combine of this pixel's shifter output with the stored pixel (rv/rc are
//   this address's contents at that point: a read-modify-write, first-written sprite pixel wins), except at
//   lb_addr 0..15, which always get 0 (the 16-pixel sprite clip, MAME :564-567).
// reset (synchronous): cnt, rv, rc, lb_we = 0.
`default_nettype none
module gx_linebuf_ctl (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    input  wire       ce_pf,
    input  wire       cntr_clr,
    input  wire       cntr_ld,
    input  wire       c256hnx,
    input  wire       hflip1x,
    input  wire [7:0] hposi,
    input  wire [4:0] lb_q,
    input  wire [1:0] cmb_vid,
    input  wire [2:0] cmb_col,
    output wire [7:0] lb_addr,
    output reg        lb_we,
    output wire [4:0] lb_d,
    output reg  [1:0] rv,
    output reg  [2:0] rc
);
    reg [7:0] cnt;

    always @(posedge clk) begin
        if (reset) begin
            cnt <= 8'd0;
            lb_we <= 1'b0;
            rv <= 2'b0;
            rc <= 3'b0;
        end else begin
            if (ce_pr) begin
                if (cntr_clr) begin
                    cnt <= 8'd0;
                end else if (cntr_ld) begin
                    cnt <= hposi;
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
            lb_we <= ce_pf;
            if (ce_pf) begin
                rc <= lb_q[4:2];
                rv <= lb_q[1:0];
            end
        end
    end

    assign lb_addr = hflip1x ? ~cnt : cnt;
    assign lb_d = (c256hnx || (lb_addr[7:4] == 4'd0)) ? 5'd0 : {cmb_col, cmb_vid};

endmodule
`default_nettype wire
