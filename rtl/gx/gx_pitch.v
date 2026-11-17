// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_pitch.v -- the pitch (melody) counter (Galaxian manual p.22 zones 10-11; MAME galaxian_a.cpp:395-410): the CPU
// writes a pitch byte into 9J (74273); 9K/8K (74161) count on 2H (1.536 MHz) and reload it when they reach 0xFF; each
// time the count reaches 0xFF the second half of 74393 6T advances.  Its QA, QC, QD drive the mixer.
//
// pitch_we: lat <= d (lat is not cleared by reset).  At ce_pr while h[1:0] = 2'b01 (2H rising): the counter steps --
// cnt <= (cnt == 8'hFF) ? lat : cnt + 1 -- and t393 advances by one when the new cnt is 0xFF and the old one was not.
// So qa toggles every (256 - lat) steps (1.536 MHz / (256 - lat) / 2), and lat = 0xFF holds cnt at 0xFF: no edges,
// the tone stops.  qa = t393[0], qc = t393[2], qd = t393[3].  reset (synchronous, system reset): cnt = 0, t393 = 0.
`default_nettype none
module gx_pitch (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    input  wire [1:0] h,
    input  wire       pitch_we,
    input  wire [7:0] d,
    output wire       qa,
    output wire       qc,
    output wire       qd
);
    // Registers
    reg [7:0] lat = 8'd0; // power-up value 0, not affected by reset
    reg [7:0] cnt;
    reg [3:0] t393;

    // Combinational outputs
    assign qa = t393[0];
    assign qc = t393[2];
    assign qd = t393[3];

    // Sequential logic
    always @(posedge clk) begin
        // Pitch write
        if (pitch_we)
            lat <= d;

        // Reset handling
        if (reset) begin
            cnt  <= 8'd0;
            t393 <= 4'd0;
        end
        // Step logic
        else if (ce_pr && h == 2'b01) begin
            reg [7:0] nxt;
            nxt = (cnt == 8'hFF) ? lat : cnt + 1'b1;
            cnt <= nxt;
            if (nxt == 8'hFF && cnt != 8'hFF)
                t393 <= t393 + 1'b1;
        end
        // else hold
    end
endmodule
`default_nettype wire

