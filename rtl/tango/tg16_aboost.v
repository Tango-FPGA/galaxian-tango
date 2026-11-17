// SPDX-License-Identifier: GPL-3.0-or-later
//==============================================================================
// tg16_aboost.v -- the "Master Audio Boost" stage, MiSTer's way. One channel. Copied from tg16-tango rtl/tango/tg16_aboost.v (the same authors).
//
// MiSTer (TurboGrafx16_MiSTer TurboGrafx16.sv, "Master Audio Boost,No,2x,4x" = CONF_STR 117, status[19:18]): the mixed 16-bit sample
// audio[17:2] goes through compr() (615-634), a KNEE COMPRESSOR on the magnitude (sign-magnitude, so the curve is odd-symmetric):
//     v  = |inp|;  v < x ? v * a : (v - x) / f + b;     b = x * a;   x = (32767 * (f - 1)) / (f * a - 1) + 1  (integer division)
//     2x: a = 2, f = 4 -> x = 14044, b = 28088;   4x: a = 4, f = 8 -> x = 7400, b = 29600      (status[19] ? 4x : 2x)
// All arithmetic is 16-bit unsigned (a 16-bit reg receives every sub-expression), the divisions are floor shifts. The compressor sits on
// the level AFTER the PSG filter and the x 5/16 stage (tg16_psg_filter.v's output = AUDIO_L/R of a HuCard on MiSTer without boost).
//
//   sel 0  "5.6x (+15 dB)"  the donor's rule, extended: gain a = 45/8 = 5.625 (14.99 dB); the donor's two settings both have f = 2a (slope
//                           above the knee = 1/(2a), half of "1/a"), and its knee x is the input at which the compressed line reaches exactly
//                           full scale at full-scale input (a*x + (32767 - x)/f = 32767  =>  x = 32767 (f-1)/(a f - 1)), plus the donor's "+1".
//                           a = 45/8, f = 45/4:  x = floor(10747576 / 1993 = 5392.66) + 1 = 5393;  b = (45 * 5393) >> 3 = 30335;
//                           below the knee (45 v) >> 3, above it (4 (v - 5393)) / 45 (floor, done as a multiply by 93207 >> 22, exact for
//                           every 4 (v - 5393) <= 109500, checked over the whole domain) + 30335.
//   sel 1  "4x"             the donor's v2 (status[19] = 1) -- VERBATIM, including its overflow for |inp| >= 32744 (see docs: unreachable here)
//   sel 2  "2x"             the donor's v1 (status[19:18] = 1) -- verbatim, same remark for |inp| >= 32764
//   sel 3  "No"             the sample unchanged
// +15 dB alone has a final safety clamp to 32767 (reachable only for |inp| >= 32744, which the PSG filter cannot produce: its output is
// within +-10240 by construction). Pipelined (4 clk_sys stages, no feedback): audio changes once per 32 clocks, the latency is inaudible.
//==============================================================================
`default_nettype none
module tg16_aboost (
    input  wire        clk,
    input  wire [1:0]  sel,
    input  wire [15:0] x,
    output reg  [15:0] y = 16'd0
);
    // ---- the donor's localparams, TurboGrafx16.sv 615-625 verbatim
    localparam [3:0] comp_f1 = 4;
    localparam [3:0] comp_a1 = 2;
    localparam       comp_x1 = ((32767 * (comp_f1 - 1)) / ((comp_f1 * comp_a1) - 1)) + 1;
    localparam       comp_b1 = comp_x1 * comp_a1;
    localparam [3:0] comp_f2 = 8;
    localparam [3:0] comp_a2 = 4;
    localparam       comp_x2 = ((32767 * (comp_f2 - 1)) / ((comp_f2 * comp_a2) - 1)) + 1;
    localparam       comp_b2 = comp_x2 * comp_a2;
    // ---- +15 dB (derived, see header)
    localparam [15:0] X15 = 16'd5393;
    localparam [15:0] B15 = 16'd30335;          // (45 * 5393) >> 3
    localparam [16:0] K15 = 17'd93207;          // ceil(2^22 / 45)

    // stage 1: magnitude (the donor's first line)
    reg        s1_neg = 1'b0;  reg [15:0] s1_v = 16'd0, s1_x = 16'd0;  reg [1:0] s1_sel = 2'd3;
    always @(posedge clk) begin
        s1_neg <= x[15];
        s1_v   <= x[15] ? (~x) + 1'd1 : x;
        s1_x   <= x;  s1_sel <= sel;
    end
    // stage 2: the donor's v1 / v2 (lines 631-632), and the +15 dB pieces
    reg        s2_neg = 1'b0;  reg [15:0] s2_v1 = 16'd0, s2_v2 = 16'd0, s2_lin = 16'd0, s2_t = 16'd0, s2_x = 16'd0, s2_v = 16'd0;  reg [1:0] s2_sel = 2'd3;
    wire [20:0] p45 = {s1_v, 5'd0} + {s1_v, 3'd0} + {s1_v, 2'd0} + {5'd0, s1_v};    // 45 * v
    always @(posedge clk) begin
        s2_neg <= s1_neg;  s2_x <= s1_x;  s2_sel <= s1_sel;  s2_v <= s1_v;
        s2_v1  <= (s1_v < comp_x1[15:0]) ? (s1_v * comp_a1) : (((s1_v - comp_x1[15:0]) / comp_f1) + comp_b1[15:0]);
        s2_v2  <= (s1_v < comp_x2[15:0]) ? (s1_v * comp_a2) : (((s1_v - comp_x2[15:0]) / comp_f2) + comp_b2[15:0]);
        s2_lin <= p45[18:3];
        s2_t   <= (s1_v < X15) ? 16'd0 : (s1_v - X15);
    end
    // stage 3: (4 t) / 45 as a multiply and a shift
    reg        s3_neg = 1'b0;  reg [15:0] s3_v1 = 16'd0, s3_v2 = 16'd0, s3_lin = 16'd0, s3_x = 16'd0, s3_v = 16'd0;  reg [15:0] s3_q = 16'd0;  reg [1:0] s3_sel = 2'd3;
    wire [33:0] qm = {s2_t, 2'd0} * K15;
    always @(posedge clk) begin
        s3_neg <= s2_neg;  s3_x <= s2_x;  s3_sel <= s2_sel;  s3_v <= s2_v;
        s3_v1 <= s2_v1;  s3_v2 <= s2_v2;  s3_lin <= s2_lin;
        s3_q   <= qm[33:22];
    end
    // stage 4: select, the +15 dB knee, its safety clamp, the sign (the donor's last line: inp[15] ? ~(v-1) : v)
    wire [16:0] hi15 = {1'b0, B15} + {1'b0, s3_q};
    wire [15:0] m15  = (s3_v < X15) ? s3_lin : (hi15[16] || hi15[15]) ? 16'd32767 : hi15[15:0];
    reg  [15:0] m;
    always @* case (s3_sel)
        2'd0:    m = m15;
        2'd1:    m = s3_v2;
        2'd2:    m = s3_v1;
        default: m = s3_v;
    endcase
    always @(posedge clk) y <= (s3_sel == 2'd3) ? s3_x : (s3_neg ? ~(m - 1'd1) : m);
endmodule
`default_nettype wire
