// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_snd_hit.v -- HIT sound (Galaxian manual p.22 zones 14-15: R89 / D1 into C21, 7R 4066 switched by NOISE,
// R35-R39, C22 / C23 / C24, LM324 7T multiple-feedback band-pass), as a fixed-point logic model. Topology and values
// per MAME galaxian_a.cpp:277-285 (galaxian_bandpass_desc) and :416-426 (RCDISC5 + OP_AMP_FILTER band-pass), with
// the schematic's R89 1K charge path, which MAME leaves out.
// Constants: tools/gx_snd_coefs.py (--check verifies this file). Voltages Q4.24; every product >>> 28.
//
// mc1 = 1: the Nichibutsu MC-1 board (MCS PDF 20, printed p.19), whose FLASH branch is the same C21 charge path and
// 4066 but no band-pass: the 4066 output goes through R35 150K straight onto the mixer node. C21 then discharges
// through R35 and the node (HIT_ADIS_MC1, tau (150K + 1.2K) x 2.2 uF = 0.333 s), and v_flash, the 4066 output
// (noise ? v21 : 0), is the source the mixer takes behind R35. v_hit is computed in both modes.
//
// Once per ce_48k, in the five clocks after it, with hit / noise / mc1 sampled at ce_48k and one shared multiplier:
//   slot 0: C21 charge: u = hit ? 3.3 V : 0 (TTL 4.0 V less the diode); if u > v21, v21 += (u - v21) * ACH
//           (R89 1K x C21 2.2 uF, tau 2.2 ms)
//   slot 1: C21 discharge while the switch is closed: if noise, v21 -= v21 * ADIS (R35 + R36 = 172K, tau 0.378 s;
//           mc1: ADIS_MC1)
//   slot 2: x0 = noise ? v21 : 0 (switch open: the input is 0); acc = B0 * (x0 - x2)
//   slot 3: acc += NA1 * y1
//   slot 4: acc += NA2 * y2; y = acc >>> 28, clipped to the op-amp's swing: the LM324 runs on +5 V (manual p.22
//           note 5) and reaches about 1.5 V below it, so 0 .. 3.5 V, i.e. -2.0 V .. +1.5 V around the 2.0 V bias;
//           the clipped value is the fed-back state (MAME disc_flt.hxx:398-403, :437, discrete.h:3623);
//           v_hit = 2.0 V + y; v_flash = x0 (the 4066 output of slot 2).
// The band-pass (R1 = R35 150K, R2 = R36 22K, R4 = R37 470K, C22 = C23 0.01 uF): f0 167.6 Hz, Q 2.47, centre gain
// -1.567; bilinear at 48 kHz: y[n] = b0 (x[n] - x[n-2]) - a1 y[n-1] - a2 y[n-2], coefficients Q2.28.
// v_hit: Q4.12 signed volts (0 .. 3.5 V), updated in slot 4. v_flash: Q4.12 signed volts (0 .. 3.3 V), updated in
// slot 4.
// reset (synchronous): v21 = 0, filter state 0, v_hit = 2.0 V, v_flash = 0.
`default_nettype none
module gx_snd_hit (
    input  wire               clk,
    input  wire               reset,
    input  wire               ce_48k,
    input  wire               hit,
    input  wire               noise,
    input  wire               mc1,
    output wire signed [15:0] v_hit,
    output wire signed [15:0] v_flash
);
    // Internal registers
    reg [4:0] ph;
    reg hit_s;
    reg noise_s;
    reg mc1_s;

    reg signed [31:0] v21;
    reg signed [31:0] x0;
    reg signed [31:0] x1;
    reg signed [31:0] x2;
    reg signed [31:0] y1;
    reg signed [31:0] y2;

    reg signed [63:0] acc;

    reg signed [15:0] vout;
    reg signed [15:0] vfl;

    // Constants (fixed point values)
    localparam signed [31:0] U_DIODE     = 55364813;
    localparam signed [31:0] HIT_ACH     = 2530000;
    localparam signed [31:0] HIT_ADIS    = 14784;
    localparam signed [31:0] HIT_ADIS_MC1 = 16811;
    localparam signed [31:0] HIT_B0      = -1855686;
    localparam signed [31:0] HIT_NA1     = 534373333;
    localparam signed [31:0] HIT_NA2     = -266066495;
    localparam signed [31:0] HIT_VB      = 33554432;
    localparam signed [31:0] HIT_VTOP    = 58720256;
    localparam signed [31:0] YMIN = -HIT_VB;
    localparam signed [31:0] YMAX = HIT_VTOP - HIT_VB;

    // Derived constant for slot 1 discharge
    wire signed [31:0] D = mc1_s ? HIT_ADIS_MC1 : HIT_ADIS;

    // Switch output used in slot 2
    wire signed [31:0] xin = noise_s ? v21 : 32'd0;
    // Input to multiplier from hit
    wire signed [31:0] u = hit_s ? U_DIODE : 32'd0;

    // Single-multiplication implementation
    reg signed [31:0] mx32;
    reg signed [31:0] my32;

    always @* begin
        if (ph[0]) begin
            mx32 = u - v21;
            my32 = HIT_ACH;
        end
        else if (ph[1]) begin
            mx32 = v21;
            my32 = D;
        end
        else if (ph[2]) begin
            mx32 = xin - x2;
            my32 = HIT_B0;
        end
        else if (ph[3]) begin
            mx32 = y1;
            my32 = HIT_NA1;
        end
        else begin
            mx32 = y2;
            my32 = HIT_NA2;
        end
    end

    wire signed [27:0] mx_lsb = mx32[27:0];
    wire signed [31:0] my32_s = $signed(my32);

    wire signed [58:0] prod = $signed(mx_lsb) * $signed(my32_s);

    wire signed [31:0] P = {prod[58], prod[58:28]};

    wire signed [63:0] prod64 = {prod[58], prod[58], prod[58], prod[58], prod[58], prod[58:0]};

    wire signed [63:0] s  = acc + prod64;
    wire signed [31:0] yr = s[59:28];
    wire signed [31:0] yr_clipped = (yr < YMIN) ? YMIN : (yr > YMAX) ? YMAX : yr;
    wire signed [31:0] vsum = HIT_VB + yr_clipped;
    wire signed [15:0] vout_next  = vsum[27:12];
    wire signed [15:0] vfl_next   = x0[27:12];

    wire unused;
    assign unused = &{1'b0, mx32[31:28], s[63:60], s[27:0], prod[27:0], vsum[31:28], vsum[11:0]};

    always @(posedge clk) begin
        if (reset) begin
            ph   <= 5'd0;
            hit_s <= 1'b0;
            noise_s <= 1'b0;
            mc1_s <= 1'b0;
            v21 <= 32'd0;
            x0  <= 32'd0;
            x1  <= 32'd0;
            x2  <= 32'd0;
            y1  <= 32'd0;
            y2  <= 32'd0;
            acc <= 64'd0;
            vout <= 16'h2000;
            vfl  <= 16'd0;
        end
        else begin
            if (ph[0]) begin
                if (u > v21) v21 <= v21 + P;
            end
            if (ph[1]) begin
                if (noise_s) v21 <= v21 - P;
            end
            if (ph[2]) begin
                x0 <= xin;
                acc <= prod64;
            end
            if (ph[3]) begin
                acc <= acc + prod64;
            end
            if (ph[4]) begin
                y2 <= y1;
                y1 <= yr_clipped;
                x2 <= x1;
                x1 <= x0;
                vout <= vout_next;
                vfl  <= vfl_next;
            end
            ph <= {ph[3:0], ce_48k};
            hit_s <= ce_48k ? hit : hit_s;
            noise_s <= ce_48k ? noise : noise_s;
            mc1_s <= ce_48k ? mc1 : mc1_s;
        end
    end

    assign v_hit   = vout;
    assign v_flash = vfl;

endmodule
`default_nettype wire
