// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_dpram.v -- dual-port RAM on one clock: port A read/write, port B read only, both outputs registered.
//
// Port A is write-through: on a write (we_a) q_a takes the written data, otherwise the addressed word.  One
// read/write mux per port feeding its output register, the form GowinSynthesis maps to a block RAM in write-through
// mode (the GW5A BSRAM has no read-before-write mode, UG300 section 3.1; it has no LUT RAM either, so every instance
// is a BSRAM).  A port-B read of the address port A writes on the same edge is not defined.  The outputs have no
// initial value: GowinSynthesis does not keep one on a block-RAM output.
// Same behaviour as scramble-tango's rtl/tango/dpram.vhd (the same authors), in Verilog.
`default_nettype none
module gx_dpram #(
    parameter integer AW = 8,
    parameter integer DW = 8
) (
    input  wire          clk,
    input  wire          we_a,
    input  wire [AW-1:0] addr_a,
    input  wire [DW-1:0] d_a,
    output reg  [DW-1:0] q_a,
    input  wire [AW-1:0] addr_b,
    output reg  [DW-1:0] q_b
);
    reg [DW-1:0] mem [0:(1<<AW)-1];

    always @(posedge clk) begin
        if (we_a) begin
            mem[addr_a] <= d_a;
            q_a <= d_a;
        end else begin
            q_a <= mem[addr_a];
        end
    end

    always @(posedge clk)
        q_b <= mem[addr_b];
endmodule
`default_nettype wire
