// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_snd_bg.v -- background "swarm" sound (Galaxian manual p.22 zones 12-14: 9M DAC R15-R19, Q1/Q2, 9R 555 with
// R21 / C15, LM324 7T with R31-R33, 555s 8R / 8S / 8T with R22-R30 and C17-C19, mixer node C20), as a fixed-point
// logic model of MAME's discrete nodes (galaxian_a.cpp:178-186 DAC, :188-202 555 descs, :381-392 netlist).
// Constants: tools/gx_snd_coefs.py (--check verifies this file).
// Voltages are Q4.24 (V * 2^24); every product is shifted right by 28 (RC factors Q0.28, CV gain Q4.28).
//
// One shared multiplier, sequenced in the clocks after each ce_1m5.  Inputs dac / fs / mc1 are sampled at ce_1m5.
//   slot 0..2 (astable k = 8R, 8S, 8T; Ra 100K, Rb 470K / 330K / 220K, C 0.01 uF; with mc1 = 1, C 0.1 uF: the
//   Nichibutsu MC-1 board's C17 / C18 / C19, MCS PDF 20, so ACH / ADIS are the _MC1 factors):
//     fs[k] = 0 (555 reset, discharge on): out = 0, vc -= vc * ADIS
//     out = 1: vc += (5 V - vc) * ACH; if vc >= cv, out = 0     (charge through Ra + Rb to the threshold CV)
//     out = 0: vc -= vc * ADIS;         if vc <= cv / 2, out = 1 (discharge through Rb to the trigger CV / 2)
//     cnt[k] += out (after the step)
//   A request from ce_48k is served in slots 3-4 of the next ce_1m5 sequence, so every 48 kHz sample is exactly
//   32 steps:
//   slot 3: bg += ((cnt0 + cnt1 + cnt2) * 4.5 V / 96 - bg) * AC20   (555 high 4.5 V, energy average over the sample,
//           3 x 10K into C20, tau 333 us); cnt = 0.  9R LFO (constant-current charge of C15 from the DAC through Q2,
//           instant discharge): vl += INC[dac]; on reaching 10/3 V it drops by 5/3 V (to 5/3 V plus the overshoot).
//   slot 4: cv = clamp(vl * 1.425532 - 1.063830 V, 0, 3.5 V)     (7T, R31 / R32 47K, R33 10K; the LM324 runs on
//           +5 V (manual p.22 note 5) and its output swings to about 1.5 V below it, MAME's OP_AMP_VP_RAIL_OFFSET,
//           discrete.h:3623, so the top of the 1.31 .. 3.69 V ramp flattens at 3.5 V)
// bg (Q4.12, unsigned volts) is the C20 node, updated in slot 3.  LFO 5.66 Hz (dac 0) .. 0.80 Hz (dac 15);
// astables 139 / 190 / 267 Hz at CV 3.33 V (mc1: 13.9 / 19.0 / 26.7 Hz).
// reset (synchronous): vl = 5/3 V, cv = its CV, every vc / out / cnt / bg = 0, mc1_s = 0, no request pending.
`default_nettype none
module gx_snd_bg (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_1m5,
    input  wire        ce_48k,
    input  wire [3:0]  dac,
    input  wire [2:0]  fs,
    input  wire        mc1,
    output wire [15:0] bg
);
    // Continuous assignment for output
    assign bg = bgv[27:12];

    // Constants
    localparam signed [31:0] V5                 = 83886080;
    localparam signed [31:0] BG_VTRIG           = 27962027;
    localparam signed [31:0] BG_VTHR            = 55924053;
    localparam signed [31:0] BG_CVG             = 382663310;
    localparam signed [31:0] BG_CVOFF           = 17848102;
    localparam signed [31:0] BG_CVTOP           = 58720256;
    localparam signed [31:0] BG_ACH_8R           = 30656;
    localparam signed [31:0] BG_ADIS_8R          = 37184;
    localparam signed [31:0] BG_ACH_8S           = 40640;
    localparam signed [31:0] BG_ADIS_8S          = 52960;
    localparam signed [31:0] BG_ACH_8T           = 54608;
    localparam signed [31:0] BG_ADIS_8T          = 79424;
    localparam signed [31:0] BG_ACH_8R_MC1        = 3066;
    localparam signed [31:0] BG_ADIS_8R_MC1       = 3718;
    localparam signed [31:0] BG_ACH_8S_MC1        = 4064;
    localparam signed [31:0] BG_ADIS_8S_MC1       = 5296;
    localparam signed [31:0] BG_ACH_8T_MC1        = 5461;
    localparam signed [31:0] BG_ADIS_8T_MC1       = 7944;
    localparam signed [31:0] BG_AC20             = 16263680;
    localparam signed [31:0] CV_RESET            = 22012659;
    // Increment table
    localparam signed [31:0] BG_INC_0  = 3295;
    localparam signed [31:0] BG_INC_1  = 3135;
    localparam signed [31:0] BG_INC_2  = 2954;
    localparam signed [31:0] BG_INC_3  = 2794;
    localparam signed [31:0] BG_INC_4  = 2567;
    localparam signed [31:0] BG_INC_5  = 2407;
    localparam signed [31:0] BG_INC_6  = 2227;
    localparam signed [31:0] BG_INC_7  = 2067;
    localparam signed [31:0] BG_INC_8  = 1695;
    localparam signed [31:0] BG_INC_9  = 1535;
    localparam signed [31:0] BG_INC_10 = 1354;
    localparam signed [31:0] BG_INC_11 = 1194;
    localparam signed [31:0] BG_INC_12 = 967;
    localparam signed [31:0] BG_INC_13 = 807;
    localparam signed [31:0] BG_INC_14 = 627;
    localparam signed [31:0] BG_INC_15 = 467;

    // Internal registers
    reg [4:0] ph = 5'd0;
    reg [3:0] dac_s = 4'd0;
    reg [2:0] fs_s = 3'd0;
    reg mc1_s = 1'b0;
    reg req = 1'b0;
    reg srv = 1'b0;
    reg signed [31:0] vc0 = 32'd0;
    reg signed [31:0] vc1 = 32'd0;
    reg signed [31:0] vc2 = 32'd0;
    reg [2:0] out = 3'd0;
    reg [5:0] cnt0 = 6'd0;
    reg [5:0] cnt1 = 6'd0;
    reg [5:0] cnt2 = 6'd0;
    reg signed [31:0] vl = BG_VTRIG;
    reg signed [31:0] cv = CV_RESET;
    reg signed [31:0] bgv = 32'd0;
    reg signed [31:0] inc;

    // Multiplier inputs (32-bit signed)
    wire signed [31:0] x0 = (fs_s[0] && out[0]) ? $signed(V5) - $signed({4'b0, vc0[27:0]}) : $signed({4'b0, vc0[27:0]});
    wire signed [31:0] c0 = (fs_s[0] && out[0]) ? (mc1_s ? $signed(BG_ACH_8R_MC1) : $signed(BG_ACH_8R)) : (mc1_s ? $signed(BG_ADIS_8R_MC1) : $signed(BG_ADIS_8R));
    wire signed [31:0] x1 = (fs_s[1] && out[1]) ? $signed(V5) - $signed({4'b0, vc1[27:0]}) : $signed({4'b0, vc1[27:0]});
    wire signed [31:0] c1 = (fs_s[1] && out[1]) ? (mc1_s ? $signed(BG_ACH_8S_MC1) : $signed(BG_ACH_8S)) : (mc1_s ? $signed(BG_ADIS_8S_MC1) : $signed(BG_ADIS_8S));
    wire signed [31:0] x2 = (fs_s[2] && out[2]) ? $signed(V5) - $signed({4'b0, vc2[27:0]}) : $signed({4'b0, vc2[27:0]});
    wire signed [31:0] c2 = (fs_s[2] && out[2]) ? (mc1_s ? $signed(BG_ACH_8T_MC1) : $signed(BG_ACH_8T)) : (mc1_s ? $signed(BG_ADIS_8T_MC1) : $signed(BG_ADIS_8T));

    // xs3 calculation with proper wrapping
    wire [6:0] xsum = {1'b0, cnt0} + {1'b0, cnt1} + {1'b0, cnt2};
    wire [8:0] xs3 = {1'b0, xsum, 1'b0} + {2'b00, xsum};
    wire signed [31:0] xv = {5'b0, xs3, 18'b0};
    wire signed [31:0] x3 = $signed(xv - bgv);
    wire signed [31:0] c3 = $signed(BG_AC20);
    wire signed [31:0] x4 = $signed({4'b0, vl[27:0]});
    wire signed [31:0] c4 = $signed(BG_CVG);

    // Priority selection of multiplier inputs (32-bit signed)
    wire signed [31:0] x_sel = ph[3] ? x3 : (ph[4] ? x4 : (ph[0] ? x0 : (ph[1] ? x1 : x2)));
    wire signed [31:0] c_sel = ph[3] ? c3 : (ph[4] ? c4 : (ph[0] ? c0 : (ph[1] ? c1 : c2)));

    // Multiplier implementation
    wire signed [57:0] prod = $signed(x_sel[27:0]) * $signed({1'b0, c_sel[28:0]});
    // sign-extend the 30-bit product slice to 32 bits
    wire signed [31:0] prod_out = {{2{prod[57]}}, prod[57:28]};

    // Unused bits sink (include unused bits of x_sel and c_sel)
    wire unused = &{1'b0, prod[27:0], prod[31:28], prod[30:29], x_sel[31:28], c_sel[31:29]};

    // Slot 0 computations
    wire signed [31:0] v0_next = (fs_s[0] && out[0]) ? $signed(vc0) + prod_out : $signed(vc0) - prod_out;
    wire o0_next = (fs_s[0] == 1'b0) ? 1'b0 : (out[0] == 1'b1) ? ((v0_next >= cv) ? 1'b0 : 1'b1) : ((v0_next <= (cv >>> 1)) ? 1'b1 : 1'b0);
    wire [5:0] cnt0_next = cnt0 + {5'b0, o0_next};

    // Slot 1 computations
    wire signed [31:0] v1_next = (fs_s[1] && out[1]) ? $signed(vc1) + prod_out : $signed(vc1) - prod_out;
    wire o1_next = (fs_s[1] == 1'b0) ? 1'b0 : (out[1] == 1'b1) ? ((v1_next >= cv) ? 1'b0 : 1'b1) : ((v1_next <= (cv >>> 1)) ? 1'b1 : 1'b0);
    wire [5:0] cnt1_next = cnt1 + {5'b0, o1_next};

    // Slot 2 computations
    wire signed [31:0] v2_next = (fs_s[2] && out[2]) ? $signed(vc2) + prod_out : $signed(vc2) - prod_out;
    wire o2_next = (fs_s[2] == 1'b0) ? 1'b0 : (out[2] == 1'b1) ? ((v2_next >= cv) ? 1'b0 : 1'b1) : ((v2_next <= (cv >>> 1)) ? 1'b1 : 1'b0);
    wire [5:0] cnt2_next = cnt2 + {5'b0, o2_next};

    // Increment lookup (always_comb)
    always_comb begin
        case (dac_s)
            4'd0 : inc = BG_INC_0;
            4'd1 : inc = BG_INC_1;
            4'd2 : inc = BG_INC_2;
            4'd3 : inc = BG_INC_3;
            4'd4 : inc = BG_INC_4;
            4'd5 : inc = BG_INC_5;
            4'd6 : inc = BG_INC_6;
            4'd7 : inc = BG_INC_7;
            4'd8 : inc = BG_INC_8;
            4'd9 : inc = BG_INC_9;
            4'd10: inc = BG_INC_10;
            4'd11: inc = BG_INC_11;
            4'd12: inc = BG_INC_12;
            4'd13: inc = BG_INC_13;
            4'd14: inc = BG_INC_14;
            4'd15: inc = BG_INC_15;
            default: inc = 32'd0;
        endcase
    end

    // Slot 3 computations
    wire signed [31:0] vln = vl + inc;
    wire signed [31:0] vl_next = (vln >= BG_VTHR) ? (vln - (BG_VTHR - BG_VTRIG)) : vln;
    wire signed [31:0] bgv_next = bgv + prod_out;

    // Slot 4 computations
    wire signed [31:0] t = prod_out - BG_CVOFF;
    wire signed [31:0] cv_next = (t < 0) ? 0 : (t > BG_CVTOP) ? BG_CVTOP : t;

    // Sequential logic
    always @(posedge clk) begin
        if (reset) begin
            ph     <= 5'd0;
            dac_s  <= 4'd0;
            fs_s   <= 3'd0;
            mc1_s  <= 1'b0;
            req    <= 1'b0;
            srv    <= 1'b0;
            vc0    <= 32'd0;
            vc1    <= 32'd0;
            vc2    <= 32'd0;
            out    <= 3'd0;
            cnt0   <= 6'd0;
            cnt1   <= 6'd0;
            cnt2   <= 6'd0;
            vl     <= BG_VTRIG;
            cv     <= CV_RESET;
            bgv    <= 32'd0;
        end else begin
            ph <= {ph[3:0], ce_1m5};
            if (ce_1m5) begin
                dac_s <= dac;
                fs_s  <= fs;
                mc1_s <= mc1;
            end
            // req logic
            if (ce_48k) begin
                req <= 1'b1;
            end else if (ph[3] && req) begin
                req <= 1'b0;
            end
            // Slot 0
            if (ph[0]) begin
                vc0 <= v0_next;
                out[0] <= o0_next;
                cnt0 <= cnt0_next;
            end
            // Slot 1 (guarded)
            if (ph[1] && !ph[0]) begin
                vc1 <= v1_next;
                out[1] <= o1_next;
                cnt1 <= cnt1_next;
            end
            // Slot 2 (guarded)
            if (ph[2] && !ph[0] && !ph[1]) begin
                vc2 <= v2_next;
                out[2] <= o2_next;
                cnt2 <= cnt2_next;
            end
            // Slot 3 (guarded by req)
            if (ph[3]) begin
                srv <= req;
                if (req) begin
                    bgv <= bgv_next;
                    cnt0 <= 6'd0;
                    cnt1 <= 6'd0;
                    cnt2 <= 6'd0;
                    vl <= vl_next;
                end
            end
            // Slot 4 (guarded by srv)
            if (ph[4] && srv) begin
                cv <= cv_next;
            end
        end
    end

endmodule
`default_nettype wire
