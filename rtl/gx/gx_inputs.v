// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_inputs.v -- the IN0 / IN1 / IN2 switch ports (Galaxian manual p.22 zone 01: 74368 9E / 9F / 9C) for every
// family layout.  Combinational.  All pad inputs are active high.
//
// Bit order (bit 7 .. bit 0) per layout follows MiSTer Arcade-Galaxian.sv:409-435 (GPL-2.0-or-later), which follows
// MAME's INPUT_PORTS; IN0 / IN1 are ANDed with the DIP bytes sw0 = dsw[7:0] / sw1 = dsw[15:8]; in2 = sw2 = dsw[23:16].
//   0 GAL  in0 = sw0 & {test, 1, 1, fire1, right1, left1, pisces & coin, ~pisces & coin}
//          in1 = sw1 & {1, 1, 1, fire2, right2, left2, start2, start1}
//   1 AZ   in0 = sw0 & {0, fire2, fire1, coin, left1, right1, up1, down1}
//          in1 = sw1 & {1, 1, left2, right2, up2, down2, start2, start1}
//   2 ORB  in0 = sw0 & {up1, down1, down2, fire1, right1, left1, 0, coin}
//          in1 = sw1 & {up2, 1, 1, fire1, right1, left1, start2, start1}
//   3 DEV  in0 = sw0 & {up1, up2, down1, fire1, right1, left1, 0, coin}
//          in1 = sw1 & {1, 1, down2, fire2, right2, left2, start2, start1}
//   4 MRDO in0 = sw0 & {test, 1, 1, fire1, right1, left1, 0, coin}
//          in1 = sw1 & {1, 1, 1, fire1, down1, up1, start2, start1}
//   5 VIC  in0 = sw0 & {up1, up2, down1, fire1, right1, left1, down2, coin}
//          in1 = sw1 & {1, 1, 1, fire2, right2, left2, start2, start1}
//   6 WOB  in0 = sw0 & {up1, down1, 1, fire1, right1, left1, up2, coin}
//          in1 = sw1 & {1, 1, down1, fire2, right2, left2, start2, start1}
//   7 POR  in0 = {down1, down2, 0, up1, right1, left1, 0, coin}              (no DIP mask)
//          in1 = {sw1[7:6], fire2, up2, right2, left2, start2, fire1 | start1}
//   other layout codes read as GAL.
// King & Balloon (kb): IN0 bit 6 is edge pin K, switched by 9N Q3 (kb_mux) between the GAL bit (test DIP) and the
// speech DIP (KB p14; MAME galaxian.cpp:1426-1430 muxbit_r); IN1 bit 5 is the NOISE line (:1433-1438 noise_r,
// :5098).
`default_nettype none
module gx_inputs (
    input  wire [3:0]  layout,
    input  wire        pisces,
    input  wire        p1_up,
    input  wire        p1_down,
    input  wire        p1_left,
    input  wire        p1_right,
    input  wire        p1_fire,
    input  wire        p2_up,
    input  wire        p2_down,
    input  wire        p2_left,
    input  wire        p2_right,
    input  wire        p2_fire,
    input  wire        start1,
    input  wire        start2,
    input  wire        coin,
    input  wire        test,
    input  wire [23:0] dsw,
    input  wire        kb,
    input  wire        kb_mux,
    input  wire        kb_speech_sw,
    input  wire        noise,
    output reg  [7:0]  in0,
    output reg  [7:0]  in1,
    output wire [7:0]  in2
);
    // combinational logic
    assign in2 = dsw[23:16];

    // internal wires for GAL logic
    wire [7:0] gal0_vec = dsw[7:0] & {test, 1'b1, 1'b1, p1_fire, p1_right, p1_left, pisces & coin, ~pisces & coin};
    wire [7:0] gal1_vec = dsw[15:8] & {1'b1, 1'b1, 1'b1, p2_fire, p2_right, p2_left, start2, start1};

    always @* begin
        reg [7:0] in0_tmp;
        reg [7:0] in1_tmp;

        case (layout)
            4'd0: begin
                in0_tmp = gal0_vec;
                in1_tmp = gal1_vec;
            end
            4'd1: begin
                in0_tmp = dsw[7:0] & {1'b0, p2_fire, p1_fire, coin, p1_left, p1_right, p1_up, p1_down};
                in1_tmp = dsw[15:8] & {1'b1, 1'b1, p2_left, p2_right, p2_up, p2_down, start2, start1};
            end
            4'd2: begin
                in0_tmp = dsw[7:0] & {p1_up, p1_down, p2_down, p1_fire, p1_right, p1_left, 1'b0, coin};
                in1_tmp = dsw[15:8] & {p2_up, 1'b1, 1'b1, p1_fire, p1_right, p1_left, start2, start1};
            end
            4'd3: begin
                in0_tmp = dsw[7:0] & {p1_up, p2_up, p1_down, p1_fire, p1_right, p1_left, 1'b0, coin};
                in1_tmp = dsw[15:8] & {1'b1, 1'b1, p2_down, p2_fire, p2_right, p2_left, start2, start1};
            end
            4'd4: begin
                in0_tmp = dsw[7:0] & {test, 1'b1, 1'b1, p1_fire, p1_right, p1_left, 1'b0, coin};
                in1_tmp = dsw[15:8] & {1'b1, 1'b1, 1'b1, p1_fire, p1_down, p1_up, start2, start1};
            end
            4'd5: begin
                in0_tmp = dsw[7:0] & {p1_up, p2_up, p1_down, p1_fire, p1_right, p1_left, p2_down, coin};
                in1_tmp = dsw[15:8] & {1'b1, 1'b1, 1'b1, p2_fire, p2_right, p2_left, start2, start1};
            end
            4'd6: begin
                in0_tmp = dsw[7:0] & {p1_up, p1_down, 1'b1, p1_fire, p1_right, p1_left, p2_up, coin};
                in1_tmp = dsw[15:8] & {1'b1, 1'b1, p1_down, p2_fire, p2_right, p2_left, start2, start1};
            end
            4'd7: begin
                in0_tmp = {p1_down, p2_down, 1'b0, p1_up, p1_right, p1_left, 1'b0, coin};
                in1_tmp = {dsw[15], dsw[14], p2_fire, p2_up, p2_right, p2_left, start2, (p1_fire | start1)};
            end
            default: begin
                in0_tmp = gal0_vec;
                in1_tmp = gal1_vec;
            end
        endcase

        if (kb) begin
            in0_tmp[6] = kb_mux ? kb_speech_sw : dsw[6];
            in1_tmp[5] = noise;
        end

        in0 = in0_tmp;
        in1 = in1_tmp;
    end
endmodule
`default_nettype wire
