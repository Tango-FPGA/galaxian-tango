#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
"""gen_gx_dbg_ov.py -- writes rtl/tango/gx_dbg_ov.v, the GX_DBG_OV on-screen debug text of dev builds (DBGOV=1).

A few lines of large hex text drawn by the core into its own pixel stream (before the framework's scaler), so they are
readable on a capture of the 720p output: an 8 x 8 cell per character in the core's native pixels (256 x 224). The
picture goes through the framework's Rotation like the game, so the text turns with it; Rotation Normal shows it
upright. No $readmemh: the font and the text are logic (case statements), which survives Gowin synthesis.
Adapted from tg16-tango tools/gen_tg16_dbg_ov.py (the same authors): the glyphs and the pipeline are unchanged; the
bus, the rows and the build-identity macro are this core's.

usage: python3 tools/gen_gx_dbg_ov.py rtl/tango/gx_dbg_ov.v
Edit ROWS / FIELDS / WORDS / COLOURS below and re-run; never edit the generated file.
"""
import sys

# ---- the 5 x 7 glyphs ('#' = on), drawn for this file
GLYPHS = {
'0': ".###. #...# #..## #.#.# ##..# #...# .###.",
'1': "..#.. .##.. ..#.. ..#.. ..#.. ..#.. .###.",
'2': ".###. #...# ....# ...#. ..#.. .#... #####",
'3': "##### ...#. ..#.. ...#. ....# #...# .###.",
'4': "...#. ..##. .#.#. #..#. ##### ...#. ...#.",
'5': "##### #.... ####. ....# ....# #...# .###.",
'6': "..##. .#... #.... ####. #...# #...# .###.",
'7': "##### ....# ...#. ..#.. .#... .#... .#...",
'8': ".###. #...# #...# .###. #...# #...# .###.",
'9': ".###. #...# #...# .#### ....# ...#. .##..",
'A': ".###. #...# #...# ##### #...# #...# #...#",
'B': "####. #...# #...# ####. #...# #...# ####.",
'C': ".###. #...# #.... #.... #.... #...# .###.",
'D': "###.. #..#. #...# #...# #...# #..#. ###..",
'E': "##### #.... #.... ####. #.... #.... #####",
'F': "##### #.... #.... ####. #.... #.... #....",
'G': ".###. #...# #.... #.### #...# #...# .####",
'H': "#...# #...# #...# ##### #...# #...# #...#",
'I': ".###. ..#.. ..#.. ..#.. ..#.. ..#.. .###.",
'J': "..### ...#. ...#. ...#. ...#. #..#. .##..",
'K': "#...# #..#. #.#.. ##... #.#.. #..#. #...#",
'L': "#.... #.... #.... #.... #.... #.... #####",
'M': "#...# ##.## #.#.# #.#.# #...# #...# #...#",
'N': "#...# #...# ##..# #.#.# #..## #...# #...#",
'O': ".###. #...# #...# #...# #...# #...# .###.",
'P': "####. #...# #...# ####. #.... #.... #....",
'Q': ".###. #...# #...# #...# #.#.# #..#. .##.#",
'R': "####. #...# #...# ####. #.#.. #..#. #...#",
'S': ".#### #.... #.... .###. ....# ....# ####.",
'T': "##### ..#.. ..#.. ..#.. ..#.. ..#.. ..#..",
'U': "#...# #...# #...# #...# #...# #...# .###.",
'V': "#...# #...# #...# #...# #...# .#.#. ..#..",
'W': "#...# #...# #...# #.#.# #.#.# #.#.# .#.#.",
'X': "#...# #...# .#.#. ..#.. .#.#. #...# #...#",
'Y': "#...# #...# .#.#. ..#.. ..#.. ..#.. ..#..",
'Z': "##### ....# ...#. ..#.. .#... #.... #####",
' ': "..... ..... ..... ..... ..... ..... .....",
':': "..... .##.. .##.. ..... .##.. .##.. .....",
'-': "..... ..... ..... ##### ..... ..... .....",
'/': "..... ....# ...#. ..#.. .#... #.... .....",
'=': "..... ..... ##### ..... ##### ..... .....",
'.': "..... ..... ..... ..... ..... .##.. .##..",
'_': "..... ..... ..... ..... ..... ..... #####",
}
ORDER = list('0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ') + [' ', ':', '-', '/', '=', '.', '_']
CODE = {c: i for i, c in enumerate(ORDER)}          # hex nibble n -> code n: '0'-'9', 'A'-'F' are codes 0-15

# ---- the debug bus (dbg[BUS-1:0], LSB first): name -> (lsb, bits). rtl/tango_galaxian.v (SECTION 10) assembles it.
FIELDS = {
    'crc':  (0, 32),    # CRC-32 (zlib/IEEE) of every byte of the last index-0 download (= crc32 of the assembled image)
    'cnt':  (32, 24),   # the byte count of the last index-0 download
    'mod':  (56, 8),    # the game byte (gx_dl_ctrl mod)
    'src':  (64, 2),    # where it came from (gx_dl_ctrl mod_src): 0 default, 1 index 1, 2 the image byte at 0xA000
    'seq':  (66, 2),    # gx_hs_seq seq_state: 0 WAIT_ROM, 1 SETTLE, 2 RUN
    'dsw':  (68, 24),   # the DIP word to gx_top, {sw2, sw1, sw0}
    'dsws': (92, 1),    # gx_dl_ctrl dsw_seen: 1 = from index 254, 0 = the game's default word
    'hcfg': (93, 1),    # hiscore.v configured (an index-3 table arrived)
    'hp':   (94, 1),    # hiscore.v pause_cpu (= gx_top cpu_hold)
    'dump': (95, 1),    # an index-4 download (the NVRAM dump) ended since the last index-0 start
    'rot':  (96, 1),    # gx_top rot_ccw: the game is turned 180 degrees in the core
    'late': (97, 1),    # since the last index-0 start, a launch download came after gx_hs_seq had released the game
                        # (index 3 or 4, or 254 with the OSD closed, starting in RUN): a firmware gap longer than
                        # QUIET, which 'gap' cannot show (it keeps only gaps that end in SETTLE)
    'lidx': (104, 8),   # ioctl_index[7:0] of the last download started
    'ndl':  (112, 16),  # downloads started since power-on
    'fr':   (128, 16),  # frames (gx_vsync rises) since power-on
    'gap':  (144, 32),  # the longest time, in clk_sys clocks, from the end of a download to the start of the next one
                        # while gx_hs_seq is in SETTLE (the launch burst): the firmware gap that QUIET must exceed;
                        # valid only with late = 0
}
BUS = 176
# ---- the text: one string per row, <= 30 characters; {name:N} = the field's low N hex digits, MSB first;
# {name} for a name in WORDS = a word per value; {bid} = the build identity, BID_N characters of the compile-time string
# `GX_BUILD_ID (build/build_galaxian.sh writes it, upper case: "<TAG> G<7-hex git SHA>", -D if the tree was dirty;
# without it -- a sim -- the row reads "NO BUILD ID").
BID_N = 25
ROWS = [
    "GX {bid}",
    "MOD {mod:2} {src} ROT {rot:1}",
    "DSW {dsw:6} {dsws}",
    "SEQ {seq} HS CFG {hcfg:1} PAUSE {hp:1}",
    "DUMP {dump:1} IDX {lidx:2} DL {ndl:4}",
    "CRC0 {crc:8} N {cnt:6}",
    "GAP {gap:8} L {late:1} FR {fr:4}",
]
WORDS = {
    'src':  ['DFLT', 'IDX1', 'IMG ', '----'],
    'dsws': ['DEF ', '254 '],
    'seq':  ['WAIT', 'SETL', 'RUN ', '----'],
}
# ---- the colour of each row (Verilog expressions over the captured bus s2; 24-bit RGB)
WHITE, GREEN, RED, YELLOW, GREY = "24'hFFFFFF", "24'h30E030", "24'hFF3030", "24'hE8E030", "24'hA0A0A0"
def f(name):
    lsb, bits = FIELDS[name]
    return f"s2[{lsb + bits - 1}:{lsb}]"
COLOURS = [
    WHITE,
    WHITE,
    f"({f('dsws')} == 1'b1) ? {GREEN} : {GREY}",
    f"({f('seq')} == 2'd2) ? {GREEN} : ({f('seq')} == 2'd3) ? {RED} : {YELLOW}",
    WHITE,
    WHITE,
    f"({f('late')} == 1'b1) ? {RED} : {WHITE}",
]
NCOL = 30

def row_cells(tmpl):
    """-> list of ('c', code) | ('n', lsb_of_nibble) | ('w', field, index, char-per-value list)"""
    out, i = [], 0
    while i < len(tmpl):
        if tmpl[i] == '{':
            j = tmpl.index('}', i)
            spec = tmpl[i + 1:j].split(':')
            name = spec[0]
            if name == 'bid':
                for k in range(BID_N):
                    out.append(('b', k))
            elif name in WORDS:
                n = len(WORDS[name][0])
                for k in range(n):
                    out.append(('w', name, k))
            else:
                lsb, bits = FIELDS[name]
                n = int(spec[1])
                assert 4 * n <= bits + 3, (name, n)
                for k in range(n):              # most significant shown nibble first
                    out.append(('n', lsb + 4 * (n - 1 - k), min(4, bits - 4 * (n - 1 - k))))
            i = j + 1
        else:
            out.append(('c', CODE[tmpl[i]]))
            i += 1
    assert len(out) <= NCOL, (tmpl, len(out))
    return out

def gen(path):
    for c in ORDER:
        rows = GLYPHS[c].split()
        assert len(rows) == 7 and all(len(r) == 5 for r in rows), c
    L = []
    w = L.append
    w("// SPDX-License-Identifier: GPL-3.0-or-later")
    w("// gx_dbg_ov.v -- GENERATED by tools/gen_gx_dbg_ov.py (edit that, re-run it; never edit this file).")
    w("// GX_DBG_OV (dev builds only): large hex text drawn into the core's own pixel stream (CLK_VIDEO = clk_sys), so it")
    w("// reaches HDMI through the framework's scaler like the picture. 8 x 8 native-pixel cells.")
    w("// Text rows 2..%d (y 16..%d), columns 1..30 (x 8..247), on a black panel y 8..%d, x 0..255." %
      (len(ROWS) + 1, 8 * (len(ROWS) + 2) - 1, 8 * (len(ROWS) + 3) - 1))
    w(f"// The bus dbg[{BUS - 1}:0] comes from clk_sys registers (tango_galaxian.v ov_dbg_q) that change at most once a frame")
    w("// or are counters: one more clk register here. Nothing here feeds back into the game.")
    w("// Pixel position: px = the pixel the NEXT CE_PIXEL samples (counts CE_PIXEL with DE), py = the active line")
    w("// (counts DE runs, cleared by VS). The three stages below finish 3 clk after px moves, and the next CE_PIXEL is")
    w("// 4 clk later (gx_ce: ce_pix = clk_sys / 4), so ov_on/ov_rgb belong to that pixel.")
    w("// Bus map (lsb, bits):")
    for k, (lsb, bits) in FIELDS.items():
        w(f"//   {k:5s} [{lsb + bits - 1}:{lsb}]")
    w("// Rows:")
    for r in ROWS:
        w(f"//   \"{r}\"")
    w("`default_nettype none")
    w("module gx_dbg_ov (")
    w("    input  wire         clk,        // clk_sys = CLK_VIDEO")
    w("    input  wire         ce_pix,     // CE_PIXEL")
    w("    input  wire         de,         // VGA_DE")
    w("    input  wire         vs,         // VGA_VS")
    w(f"    input  wire [{BUS - 1}:0] dbg,")
    w("    output reg          ov_on = 1'b0,")
    w("    output reg  [23:0]  ov_rgb = 24'd0")
    w(");")
    w(f"    // ---- the build identity (row 0): `GX_BUILD_ID, a {BID_N}-character string literal written by build/build_galaxian.sh")
    w("    // (left-aligned, space-padded; the sim leaves it undefined: NO BUILD ID), folded to constant character codes.")
    w("`ifndef GX_BUILD_ID")
    w(f"`define GX_BUILD_ID \"{'NO BUILD ID':<{BID_N}}\"")
    w("`endif")
    w(f"    localparam [{8 * BID_N - 1}:0] BID = `GX_BUILD_ID;")
    # ASCII -> character code as a plain constant expression per character (no constant function: the most portable
    # form for GowinSynthesis / Verilator / iverilog); lower case is shown as upper case, anything unknown as '-'
    def a2c_expr(b):
        e = f"6'd{CODE['-']}"
        for ch in ['_', '.', '=', '/', '-', ':', ' ']:
            e = f"({b} == 8'h{ord(ch):02X}) ? 6'd{CODE[ch]} : {e}"
        e = f"({b} == 8'h00) ? 6'd{CODE[' ']} : {e}"
        e = f"({b} >= 8'h61 && {b} <= 8'h7A) ? {b} - 8'h57 : {e}"     # 'a'-'z' -> 10-35
        e = f"({b} >= 8'h41 && {b} <= 8'h5A) ? {b} - 8'h37 : {e}"     # 'A'-'Z' -> 10-35
        e = f"({b} >= 8'h30 && {b} <= 8'h39) ? {b} - 8'h30 : {e}"     # '0'-'9' -> 0-9
        return e
    for k in range(BID_N):
        w(f"    localparam [7:0] BCH{k} = BID[{8 * (BID_N - 1 - k) + 7}:{8 * (BID_N - 1 - k)}];")
        w(f"    localparam [5:0] BID{k} = {a2c_expr(f'BCH{k}')};")
    w(f"    reg [{BUS - 1}:0] s2 = {BUS}'d0;")
    w("    always @(posedge clk) s2 <= dbg;")
    w("    reg  [9:0] px = 10'd0;")
    w("    reg  [8:0] py = 9'd0;")
    w("    reg        de_l = 1'b0, vs_l = 1'b0;")
    w("    always @(posedge clk) if (ce_pix) begin")
    w("        de_l <= de; vs_l <= vs;")
    w("        if (vs && !vs_l) begin px <= 10'd0; py <= 9'd0; end")
    w("        else if (de) px <= px + 10'd1;")
    w("        else if (de_l) begin px <= 10'd0; py <= py + 9'd1; end")
    w("    end")
    w("    // ---- stage 1: cell and glyph coordinates")
    w("    reg        box1 = 1'b0, txt1 = 1'b0;")
    w("    reg  [2:0] gx1 = 3'd0, gy1 = 3'd0;")
    w("    reg  [3:0] tr1 = 4'd0;")
    w("    reg  [4:0] tc1 = 5'd0;")
    w("    wire [6:0] col = px[9:3];")
    w("    wire [5:0] row = py[8:3];")
    w("    always @(posedge clk) begin")
    w(f"        box1 <= (py >= 9'd8) && (py < 9'd{8 * (len(ROWS) + 3)}) && (px < 10'd256);")
    w(f"        txt1 <= (row >= 6'd2) && (row <= 6'd{len(ROWS) + 1}) && (col >= 7'd1) && (col <= 7'd{NCOL});")
    w("        tr1  <= row[3:0] - 4'd2;")
    w("        tc1  <= col[4:0] - 5'd1;")
    w("        gx1  <= px[2:0];")
    w("        gy1  <= py[2:0];")
    w("    end")
    w("    // ---- stage 2: the character code and the row colour")
    w("    reg        box2 = 1'b0, txt2 = 1'b0;")
    w("    reg  [2:0] gx2 = 3'd0, gy2 = 3'd0;")
    w("    reg  [5:0] code2 = 6'd36;")
    w("    reg [23:0] col2 = 24'd0;")
    w("    always @(posedge clk) begin")
    w("        box2 <= box1; txt2 <= txt1; gx2 <= gx1; gy2 <= gy1;")
    w("        code2 <= 6'd%d;" % CODE[' '])
    w("        case (tr1)")
    for ri, r in enumerate(ROWS):
        cells = row_cells(r)
        w(f"        4'd{ri}: case (tc1)")
        for ci, cell in enumerate(cells):
            if cell[0] == 'c':
                if cell[1] == CODE[' ']:
                    continue
                w(f"            5'd{ci}: code2 <= 6'd{cell[1]};")
            elif cell[0] == 'b':
                w(f"            5'd{ci}: code2 <= BID{cell[1]};")
            elif cell[0] == 'n':
                lsb, nb = cell[1], cell[2]
                if nb == 4:
                    w(f"            5'd{ci}: code2 <= {{2'b00, s2[{lsb + 3}:{lsb}]}};")
                else:
                    w(f"            5'd{ci}: code2 <= {{{6 - nb}'d0, s2[{lsb + nb - 1}:{lsb}]}};")
            else:
                name, k = cell[1], cell[2]
                lsb, bits = FIELDS[name]
                words = WORDS[name]
                sel = f"s2[{lsb + bits - 1}:{lsb}]"
                opts = [CODE[words[v][k]] for v in range(len(words))]
                expr = f"6'd{opts[-1]}"
                for v in range(len(words) - 2, -1, -1):
                    expr = f"({sel} == {bits}'d{v}) ? 6'd{opts[v]} : {expr}"
                w(f"            5'd{ci}: code2 <= {expr};")
        w("            default: ;")
        w("            endcase")
    w("        default: ;")
    w("        endcase")
    w("        case (tr1)")
    for ri, c in enumerate(COLOURS):
        w(f"        4'd{ri}: col2 <= {c};")
    w(f"        default: col2 <= {WHITE};")
    w("        endcase")
    w("    end")
    w("    // ---- stage 3: the glyph row (logic) and the pixel (black panel, coloured text)")
    w("    reg  [7:0] bits2;")
    w("    always @(*) begin")
    w("        case ({code2, gy2})")
    for c in ORDER:
        rows = GLYPHS[c].split()
        for gy, r in enumerate(rows):
            v = 0
            for x, ch in enumerate(r):          # glyph column x (0..4) -> bit 6 - x (cell column 1 + x)
                if ch == '#':
                    v |= 1 << (6 - x)
            if v:
                w(f"        {{6'd{CODE[c]}, 3'd{gy}}}: bits2 = 8'h{v:02X};   // {c!r} {r}")
    w("        default: bits2 = 8'h00;")
    w("        endcase")
    w("    end")
    w("    always @(posedge clk) begin")
    w("        ov_on  <= box2;")
    w("        ov_rgb <= (txt2 && bits2[3'd7 - gx2]) ? col2 : 24'h000000;")
    w("    end")
    w("endmodule")
    w("`default_nettype wire")
    open(path, 'w').write('\n'.join(L) + '\n')

if __name__ == '__main__':
    gen(sys.argv[1])
    print('wrote', sys.argv[1])
