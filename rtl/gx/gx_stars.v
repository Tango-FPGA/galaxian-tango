// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_stars.v -- the star field and the noise source (Galaxian manual p.22 zones 15-16A: A1/B1 74LS164 + 2D 7474
// (1st half) = 17-bit LFSR, 3B 7486 feedback, 3C 7420 / 1C 7474 / 6D clock gating, 2A 7430 + 4P 7410 star enable,
// 2B 74366 inverting drivers onto R68-R73, 2D (2nd half) NOISE);
// MAME galaxian_v.cpp:800-938, galaxian_a.cpp:224-237,369-371.
//
// LFSR u[16:0]: u[0] = A1 QA (newest) .. u[7] = A1 QH, u[8..15] = B1 QA..QH, u[16] = 2D Q.
//   step: u <= {u[15:0], u[4] ^ ~u[16]}.  stars_on = 0 holds u at 0 (A1/B1/2D CLR).
//   This is MAME's stars_init register reversed (MAME bit k = u[16-k]; "bit 12 XOR NOT bit 0").
// Clock gating: sclk = ce_12m & c256hnx & ~vsync (two per pixel, 256 pixels x 256 lines).
//   1C: q1, q2 held 0 while vsync; at sclk q1 <= 1, q2 <= q1.  u steps at sclk & (hflip | q2), q2 before the edge:
//   2 x 65536 steps per frame, minus 2 when hflip = 0 (MAME :844-852).
// star_en (c) = stars_disp & (&u[7:0]) & ~u[16] & (hf8 ^ vf1) & stars_off_n  (2A sees A1's eight outputs, 4P the
//   2D output; MAME "upper 8 bits = 1 and low bit = 0" :814-815, "V1 ^ H8" :893).
// Drive levels (c), through the inverting 74366, {100 ohm bit, 150 ohm bit} per gun:
//   star_r = {~u[9], ~u[8]}, star_g = {~u[11], ~u[10]}, star_b = {~u[13], ~u[12]}  (MAME (~shiftreg & 0x1f8) >> 3).
// noise (2D 2nd half, CK = 2V): at v_inc & v[1:0] == 2'b01 (2V rising), noise <= ~u[16].  With stars_on = 0 noise
//   stays 1.
// star_* are read by gx_colour in d0 of the next pixel, after both of the pixel's steps.
// reset (synchronous): u = 0, q1 = q2 = 0, noise = 1.
`default_nettype none
module gx_stars (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_12m,
    input  wire       v_inc,
    input  wire [1:0] v,
    input  wire       stars_on,
    input  wire       hflip,
    input  wire       vsync,
    input  wire       c256hnx,
    input  wire       hf8,
    input  wire       vf1,
    input  wire       stars_off_n,
    input  wire       stars_disp,
    output wire       star_en,
    output wire [1:0] star_r,
    output wire [1:0] star_g,
    output wire [1:0] star_b,
    output reg        noise
);
    // Internal registers
    reg [16:0] u;
    reg q1, q2;

    // Combinational helper
    wire sclk = ce_12m & c256hnx & ~vsync;

    // Sequential logic
    always @(posedge clk) begin
        if (reset) begin
            u <= 17'b0;
            q1 <= 1'b0;
            q2 <= 1'b0;
            noise <= 1'b1;
        end else begin
            // Update q1 and q2
            if (vsync) begin
                q1 <= 1'b0;
                q2 <= 1'b0;
            end else if (sclk) begin
                q2 <= q1;
                q1 <= 1'b1;
            end

            // Update u
            if (!stars_on) begin
                u <= 17'b0;
            end else if (sclk && (hflip || q2)) begin
                u <= {u[15:0], u[4] ^ ~u[16]};
            end

            // Update noise
            if (v_inc && (v == 2'b01)) begin
                noise <= ~u[16];
            end
        end
    end

    // Combinational outputs
    assign star_en = stars_disp & (&u[7:0]) & ~u[16] & (hf8 ^ vf1) & stars_off_n;
    assign star_r  = {~u[9], ~u[8]};
    assign star_g  = {~u[11], ~u[10]};
    assign star_b  = {~u[13], ~u[12]};

endmodule
`default_nettype wire
