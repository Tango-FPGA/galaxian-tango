// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_kb_filter.v -- King & Balloon speech-board output filter at 48 kHz (KB p15, drawing 02-70103).
//
// The circuit after the IC15 TL081 ladder buffer: R28 2.2K / C11 0.033 uF, then a unity-gain Sallen-Key on IC16a
// (R29 = R30 = 2.2K, C12 0.068 uF to the output, C13 0.0033 uF to ground), then a second one on IC16b (R31 = R32 =
// 3.3K, C16 0.1 uF, C17 0.0033 uF).  R28/C11 is loaded by R29, so the first two form one third-order section;
// tools/gx_kb_filter.py derives it by nodal analysis.  Analog poles: real 2524.6 Hz; pairs 4500.2 Hz Q 1.129 and
// 2654.9 Hz Q 2.752.  DC gain 1, peak +7.35 dB at 2.54 kHz.
//
// Discretisation: bilinear transform per section, prewarped at each section's pole magnitude, DC gain exactly 1
// (tools/gx_kb_filter.py: response table, coefficients and a bit-exact model of this module).
//
// Arithmetic: a real section and two biquads in Direct Form I, signals Q6.18 (24 bits), coefficients Q2.16
// (18 bits), one shared 26 x 18 multiplier.  With k = 1 + a1 + a2:
//   real:   acc = k * 2 (x[n] + x[n-1])          - a1 * 4 y[n-1]
//   biquad: acc = k * (x[n] + 2 x[n-1] + x[n-2]) - a1 * 4 y[n-1] - a2 * 4 y[n-2]
//   y[n] = sat24((acc + 2^17) >>> 18)
// Each ce_48k samples x and starts 13 clk steps: three per section to multiply-accumulate (st[1:0] = 0..2), one
// to round and store (st[1:0] = 3), then step 12 shifts the histories and updates y.  The output follows the input
// sample by 13 clk.
//
// x, y: signed Q5.11 volts (1 LSB = 1/2048 V, range -16 .. +16 V).  The resonant peaks take the output beyond the
// 0 .. 4.6875 V DAC range: a full-scale step peaks at 6.78 V, the speech data reach 9.13 V, and the bound from
// the impulse response's L1 norm is -4.9 .. +9.6 V, inside the +/-12 V op-amp supplies.  The saturation at the
// Q5.11 range is never reached.
`default_nettype none
module gx_kb_filter (
    input  wire               clk,
    input  wire               reset,
    input  wire               ce_48k,
    input  wire signed [15:0] x,
    output reg  signed [15:0] y
);
    // tools/gx_kb_filter.py: NA1 = -a1, NA2 = -a2 (Q2.16)
    localparam signed [17:0] K0 = 18'sd18733, NA1_0 = 18'sd46803;                      // a2 = 0
    localparam signed [17:0] K1 = 18'sd17728, NA1_1 = 18'sd87453,  NA2_1 = -18'sd39645;
    localparam signed [17:0] K2 = 18'sd7379,  NA1_2 = 18'sd116056, NA2_2 = -18'sd57899;

    reg signed [23:0] x0, x1;            // input history, Q6.18
    reg signed [23:0] ya0, ya1, ya2;     // real section output: new, n-1, n-2 (biquad 1's input history)
    reg signed [23:0] yb0, yb1, yb2;     // biquad 1 output (biquad 2's input history)
    reg signed [23:0] yc0, yc1, yc2;     // biquad 2 output
    reg signed [45:0] acc;
    reg        [3:0]  st;
    reg               busy;

    // operand and coefficient for step st
    reg signed [25:0] u;
    reg signed [17:0] c;
    always @* begin
        u = 26'sd0;
        c = 18'sd0;
        case (st)
            4'd0:  begin u = ({{2{x0[23]}}, x0} + {{2{x1[23]}}, x1}) <<< 1;                   c = K0;    end
            4'd1:  begin u = {{2{ya1[23]}}, ya1} <<< 2;                                      c = NA1_0; end
            4'd4:  begin u = {{2{ya0[23]}}, ya0} + ({{2{ya1[23]}}, ya1} <<< 1) + {{2{ya2[23]}}, ya2};
                         c = K1;    end
            4'd5:  begin u = {{2{yb1[23]}}, yb1} <<< 2;                                      c = NA1_1; end
            4'd6:  begin u = {{2{yb2[23]}}, yb2} <<< 2;                                      c = NA2_1; end
            4'd8:  begin u = {{2{yb0[23]}}, yb0} + ({{2{yb1[23]}}, yb1} <<< 1) + {{2{yb2[23]}}, yb2};
                         c = K2;    end
            4'd9:  begin u = {{2{yc1[23]}}, yc1} <<< 2;                                      c = NA1_2; end
            4'd10: begin u = {{2{yc2[23]}}, yc2} <<< 2;                                      c = NA2_2; end
            default: ;
        endcase
    end
    wire signed [43:0] prod = u * c;
    wire signed [45:0] sum  = (st[1:0] == 2'd0 ? 46'sd0 : acc) + $signed({{2{prod[43]}}, prod});

    // round and saturate the accumulator to Q6.18
    wire signed [45:0] rnd = acc + 46'sd131072;
    wire signed [27:0] q   = rnd[45:18];
    wire signed [23:0] ys  = (q > 28'sd8388607) ? 24'sd8388607 : (q < -28'sd8388608) ? -24'sd8388608 : q[23:0];

    // output: Q6.18 -> Q5.11, rounded and saturated
    wire signed [24:0] yr  = $signed({yc0[23], yc0}) + 25'sd64;
    wire signed [17:0] yo  = yr[24:7];
    wire signed [15:0] ysat = (yo > 18'sd32767) ? 16'sd32767 : (yo < -18'sd32768) ? -16'sd32768 : yo[15:0];

    wire unused_bits = &{1'b0, rnd[17:0], yr[6:0]};

    always @(posedge clk) begin
        if (reset) begin
            x0 <= 24'sd0; x1 <= 24'sd0;
            ya0 <= 24'sd0; ya1 <= 24'sd0; ya2 <= 24'sd0;
            yb0 <= 24'sd0; yb1 <= 24'sd0; yb2 <= 24'sd0;
            yc0 <= 24'sd0; yc1 <= 24'sd0; yc2 <= 24'sd0;
            acc <= 46'sd0; st <= 4'd0; busy <= 1'b0; y <= 16'sd0;
        end else if (ce_48k) begin
            x0   <= {x[15], x, 7'd0};           // Q5.11 -> Q6.18
            st   <= 4'd0;
            busy <= 1'b1;
        end else if (busy) begin
            st <= st + 4'd1;
            if (st == 4'd12) begin
                busy <= 1'b0;
                x1 <= x0;
                ya2 <= ya1; ya1 <= ya0;
                yb2 <= yb1; yb1 <= yb0;
                yc2 <= yc1; yc1 <= yc0;
                y <= ysat;
            end else if (st[1:0] == 2'd3) begin
                case (st[3:2])
                    2'd0:    ya0 <= ys;
                    2'd1:    yb0 <= ys;
                    default: yc0 <= ys;
                endcase
            end else begin
                acc <= sum;
            end
        end
    end
endmodule
`default_nettype wire
