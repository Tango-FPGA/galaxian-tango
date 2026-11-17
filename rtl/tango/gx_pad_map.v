// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_pad_map.v -- the two Tango pads to gx_top's pad inputs.
// START FILE: the port list only; every output is tied to 0 until the module is written.
`default_nettype none
module gx_pad_map (
    input  wire        clk,
    input  wire [31:0] joystick_0,
    input  wire [31:0] joystick_1,
    output reg         p1_up,
    output reg         p1_down,
    output reg         p1_left,
    output reg         p1_right,
    output reg         p1_fire,
    output reg         p2_up,
    output reg         p2_down,
    output reg         p2_left,
    output reg         p2_right,
    output reg         p2_fire,
    output reg         start1,
    output reg         start2,
    output reg         coin,
    output reg         test
);
    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] j = joystick_0 | joystick_1;
    /* verilator lint_on UNUSEDSIGNAL */
    always @ (posedge clk) begin
        // Map bits 0-8 to outputs.
        p1_right <= j[0];
        p2_right <= j[0];
        p1_left  <= j[1];
        p2_left  <= j[1];
        p1_down  <= j[2];
        p2_down  <= j[2];
        p1_up    <= j[3];
        p2_up    <= j[3];
        p1_fire  <= j[4];
        p2_fire  <= j[4];
        start1   <= j[5];
        start2   <= j[6];
        coin     <= j[7];
        test     <= j[8];
    end
    // Unused bits 10-31 are ignored; bits 9 is unused too.
endmodule
`default_nettype wire
