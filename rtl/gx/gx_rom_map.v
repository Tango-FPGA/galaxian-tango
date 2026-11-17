// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_rom_map.v -- per-game CPU ROM address (image index) and the Moon Quasar opcode decrypt.
// Combinational.
//
// The index-0 image holds each set's ROM files in .mra part order; the remaps below put each CPU address on the
// image byte that MAME's ROM_LOAD / ROM_CONTINUE layout loads at that address (MAME galaxian.cpp).  They are image
// layouts, not board circuits.  b = a[13:11] is the 2K block.
//   rom_mode 1, Devil Fish (devilfshgb, :11166-11175): each 4K part dfishN holds CPU 0x2000+n, then 0x0000+n, so CPU
//     block b is image block {b[1], b[0], ~b[2]}:  rom_a = {a[14], a[12], a[11], ~a[13], a[10:0]}.
//   rom_mode 2, Orbitron (:10457-10475): below 0x2000 each 2K part stores its four 0x200 chunks in reverse order:
//     rom_a = a[13] ? a[14:0] : {a[14:11], ~a[10], ~a[9], a[8:0]}.
//   rom_mode 3, Portman (porter, :13330-13341): each 4K part portN (N = 1..4) holds CPU 0x0000+n, then 0x2000+n:
//     rom_a = a[14] ? a[14:0] : {a[14], a[12], a[11], a[13], a[10:0]}.
//   rom_mode 0: rom_a = a[14:0].
// Moon Quasar (mq_dec), opcode fetches only (m1_n low): MAME decode_mooncrst (:8488-8501), the opcode space of
// moonqsr (:7738-7742, :1843-1846, init_moonqsr :8967-8974):
//   x = rom_q;  if (x[1]) x ^= 0x40;  if (x[5]) x ^= 0x04;
//   if (~a[0]) x = {x[7], x[2], x[5], x[4], x[3], x[6], x[1], x[0]}   (bits 6 and 2 swap)
// Operand and data reads (m1_n high) pass rom_q unchanged.  The caller uses rom_d only for ROM reads.
`default_nettype none
module gx_rom_map (
    input  wire [15:0] a,
    input  wire        m1_n,
    input  wire [1:0]  rom_mode,
    input  wire        mq_dec,
    input  wire [7:0]  rom_q,
    output reg  [14:0] rom_a,
    output wire [7:0]  rom_d
);
    // Dummy to use unused bit a[15] and avoid lint warning
    wire _a15 = a[15];

    // Compute rom_a based on rom_mode
    always @* begin
        case (rom_mode)
            2'b00: rom_a = a[14:0];
            2'b01: rom_a = {a[14], a[12], a[11], ~a[13], a[10:0]};
            2'b10: rom_a = a[13] ? a[14:0] : {a[14:11], ~a[10], ~a[9], a[8:0]};
            2'b11: rom_a = a[14] ? a[14:0] : {a[14], a[12], a[11], a[13], a[10:0]};
            default: rom_a = a[14:0];
        endcase
        rom_a = rom_a ^ {15{_a15 & 1'b0}};
    end

    // Decrypt opcode for Moon Quasar
    wire [7:0] x1 = rom_q ^ (rom_q[1] ? 8'h40 : 8'h00);
    wire [7:0] x2 = x1 ^ (x1[5] ? 8'h04 : 8'h00);
    wire [7:0] xs = a[0] ? x2 : {x2[7], x2[2], x2[5], x2[4], x2[3], x2[6], x2[1], x2[0]};
    assign rom_d = (mq_dec && ~m1_n) ? xs : rom_q;

endmodule
`default_nettype wire
