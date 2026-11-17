// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_gfx_bank.v -- the per-game graphics ROM address: the 12-bit address into one 4K plane (both planes use the same
// address).  Combinational.
//   gfx_mode 0 GAL    (Galaxian, M p.22 zone 09; 2K ROMs, A11 = 0):     {1'b0, code, row}
//   gfx_mode 1 MOONCR (mooncrgx; MCG p5: 9M Q0-Q2 gated with A9/A10; MAME galaxian_v.cpp:1355-1366):
//            bank9m[2] & code[7:6] == 2'b10 ? {1'b1, bank9m[0], bank9m[1], code[5:0], row} : {1'b0, code, row}
//            (bank9m[0] on A10 and bank9m[1] on A9: the image holds MAME's 12.chr/11.chr unshuffled)
//   gfx_mode 2 DEVIL  (devilfsg; tiles upper 2K, sprites lower 2K):       {~h8, code, row}
//   gfx_mode 3 PISCES (pisces, uniwars, Portman; A11 = 9M Q2; MAME :1323-1332): {bank9m[2], code, row}
//   gfx_mode 4 MQSR   (moonqsr; A11 = colour latch bit 5; MAME :1369-1378):    {col5, code, row}
//   gfx_mode 5..7: as GAL.
// code is the 8x8 cell index (tile code, or 4 x sprite code + quadrant), row the line within the cell.
`default_nettype none
module gx_gfx_bank (
    input  wire [2:0]  gfx_mode,
    input  wire [7:0]  code,
    input  wire [2:0]  row,
    input  wire        h8,
    input  wire [2:0]  bank9m,
    input  wire        col5,
    output reg  [11:0] addr
);

    // Combinational logic to compute the ROM address based on game mode and inputs.
    always @* begin
        case (gfx_mode)
            3'd1: begin
                if (bank9m[2] && (code[7:6] == 2'b10)) begin
                    // Banked MOONCR: A11=1, A10=bank9m[0], A9=bank9m[1]
                    addr = {1'b1, bank9m[0], bank9m[1], code[5:0], row};
                end else begin
                    // Default MOONCR: A11=0
                    addr = {1'b0, code, row};
                end
            end
            3'd2: begin
                // DEVIL: A11 = ~h8
                addr = {~h8, code, row};
            end
            3'd3: begin
                // PISCES: A11 = bank9m[2]
                addr = {bank9m[2], code, row};
            end
            3'd4: begin
                // MQSR: A11 = col5
                addr = {col5, code, row};
            end
            default: begin
                // GAL (0,5,6,7): A11 = 0
                addr = {1'b0, code, row};
            end
        endcase
    end

endmodule
`default_nettype wire
