// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_dpram2.v -- true dual-port RAM on one clock: both ports read/write, both outputs registered.  The main CPU's
// work RAM uses it: port A is the CPU, port B the hi-score engine (rtl/galaxian/hiscore.v).
//
// Each port is write-through: on a write its output takes the written data, otherwise the addressed word.  One
// read/write mux per port, for the reason given in gx_dpram.v.  Writes of both ports to one address on the same edge
// are not defined (the hi-score engine writes only while it holds the CPU in WAIT).
// Same behaviour as scramble-tango's rtl/tango/dpram2.vhd (the same authors), in Verilog.
`default_nettype none
module gx_dpram2 #(
    parameter integer AW = 8,
    parameter integer DW = 8
) (
    input  wire          clk,
    input  wire          we_a,
    input  wire [AW-1:0] addr_a,
    input  wire [DW-1:0] d_a,
    output reg  [DW-1:0] q_a,
    input  wire          we_b,
    input  wire [AW-1:0] addr_b,
    input  wire [DW-1:0] d_b,
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

    always @(posedge clk) begin
        if (we_b) begin
            mem[addr_b] <= d_b;
            q_b <= d_b;
        end else begin
            q_b <= mem[addr_b];
        end
    end
endmodule
`default_nettype wire
