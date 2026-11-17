// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_dl_ctrl.v -- the download decode: game byte, DIP word, ROM write strobes.
// START FILE: the port list only; every output is tied to 0 until the module is written.
`default_nettype none
module gx_dl_ctrl (
    input  wire        clk,
    input  wire        por,
    input  wire        ioctl_download,
    input  wire [7:0]  ioctl_index,
    input  wire        ioctl_wr,
    input  wire [26:0] ioctl_addr,
    input  wire [7:0]  ioctl_dout,
    output wire [15:0] dn_addr,
    output wire [7:0]  dn_data,
    output wire        dn_wr,
    output wire [7:0]  mod,
    output wire [1:0]  mod_src,
    output wire [23:0] dsw,
    output wire        dsw_seen,
    output wire        kb_speech_sw
);
    // Derived combinational signals
    wire rom_dl = ioctl_download & (ioctl_index == 8'd0);
    wire mod_dl = ioctl_download & (ioctl_index == 8'd1);
    wire dip_dl = ioctl_download & (ioctl_index == 8'd254);
    assign dn_addr  = ioctl_addr[15:0];
    assign dn_data  = ioctl_dout;
    assign dn_wr    = rom_dl & ioctl_wr & (ioctl_addr[26:16] == 11'd0);
    wire rom_start = rom_dl & ~rom_q;
    wire rom_end   = ~rom_dl & rom_q;

    // Internal state registers
    reg [7:0]  mod_reg      = 8'd0;   // holds current game byte
    reg [1:0]  mod_src_reg  = 2'd0;
    reg [7:0]  mod_pend     = 8'd0;   // holds last index-1 byte value
    reg        pend_set     = 1'b0;    // indicates mod_pend is valid
    reg [7:0]  sw0          = 8'd0;
    reg [7:0]  sw1          = 8'd0;
    reg [7:0]  sw2          = 8'd0;
    reg        dsw_seen_reg = 1'b0;
    reg        sw3_b0_reg   = 1'b0;    // DIP byte 3 bit 0
    reg        sp_seen_reg  = 1'b0;
    reg        rom_q        = 1'b0;

    // Default DIP word lookup
    function [23:0] def_dsw;
        input [7:0] m;
        case (m)
            8'h00: def_dsw = 24'h041F9F;  8'h01: def_dsw = 24'h01DF1F;  8'h02: def_dsw = 24'h007F7F;
            8'h03: def_dsw = 24'h021F1F;  8'h04: def_dsw = 24'h045F1F;  8'h05: def_dsw = 24'h073FFF;
            8'h06: def_dsw = 24'h00FFFF;  8'h07: def_dsw = 24'h045F9F;  8'h08: def_dsw = 24'h041FFF;
            8'h09: def_dsw = 24'h00DF1F;  8'h0A: def_dsw = 24'h00DFFF;  8'h0B: def_dsw = 24'h001F1F;
            8'h0C: def_dsw = 24'h011F9F;  8'h0D: def_dsw = 24'h07DFFF;  8'h0E: def_dsw = 24'h0A3FDF;
            8'h0F: def_dsw = 24'h001F1F;  8'h10: def_dsw = 24'h041FFF;  8'h11: def_dsw = 24'h041FFF;
            default: def_dsw = 24'h041F9F;
        endcase
    endfunction

    // Combinational outputs
    assign dsw = dsw_seen_reg ? {sw2, sw1, sw0} : def_dsw(mod_reg);
    assign dsw_seen = dsw_seen_reg;
    assign kb_speech_sw = sp_seen_reg ? sw3_b0_reg : 1'b1;
    assign mod = mod_reg;
    assign mod_src = mod_src_reg;

    // Sequential logic
    always @(posedge clk) begin
        if (por) begin
            // Power-on reset
            mod_reg     <= 8'd0;
            mod_pend    <= 8'd0;
            pend_set    <= 1'b0;
            mod_src_reg <= 2'd0;
            sw0         <= 8'd0;
            sw1         <= 8'd0;
            sw2         <= 8'd0;
            dsw_seen_reg <= 1'b0;
            sw3_b0_reg   <= 1'b0;
            sp_seen_reg  <= 1'b0;
            rom_q        <= 1'b0;
        end else begin
            // Statement 1
            rom_q <= rom_dl;
            // Statement 2
            if (mod_dl & ioctl_wr) begin
                mod_reg   <= ioctl_dout;
                mod_pend  <= ioctl_dout;
                pend_set  <= 1'b1;
                mod_src_reg <= 2'd1;
            end
            // Statement 3
            if (rom_start) begin
                mod_reg    <= pend_set ? mod_pend : 8'd0;
                mod_src_reg <= pend_set ? 2'd1 : 2'd0;
                dsw_seen_reg <= 1'b0;
                sp_seen_reg  <= 1'b0;
            end
            // Statement 4
            if (rom_dl & ioctl_wr & (ioctl_addr == 27'h000A000)) begin
                mod_reg   <= ioctl_dout;
                mod_src_reg <= 2'd2;
            end
            // Statement 5
            if (rom_end) begin
                pend_set <= 1'b0;
            end
            // Statement 6
            if (dip_dl & ioctl_wr & (ioctl_addr <= 27'd2)) begin
                case (ioctl_addr[1:0])
                    2'd0: sw0 <= ioctl_dout;
                    2'd1: sw1 <= ioctl_dout;
                    2'd2: sw2 <= ioctl_dout;
                    default: sw0 <= sw0;
                endcase
                dsw_seen_reg <= 1'b1;
            end
            // Statement 7
            if (dip_dl & ioctl_wr & (ioctl_addr == 27'd3)) begin
                sw3_b0_reg <= ioctl_dout[0];
                sp_seen_reg <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire
