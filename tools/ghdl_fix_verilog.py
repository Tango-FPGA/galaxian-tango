#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
"""ghdl_fix_verilog.py -- make GHDL 4.1 `--synth --out=verilog` output readable by Verilator and GowinSynthesis.

Copied from galaga-tango tools/ghdl_fix_verilog.py (the same authors; MIT there).

Adapted from genesis-tango's tools/ghdl_fix_verilog.py (itself genesis-tango's own; see its NOTICE), which
fixes GHDL 4.1 printer defects 1-4 below.  galaga-tango's build/galaga_ghdl.sh hit a fifth defect (5), not
seen on genesis's VDP/T80s/SVP units, so it is added here.

GHDL 4.1 printer defects seen so far (build/genesis_ghdl.sh and build/galaga_ghdl.sh both compile the result):
  1. a port named after a Verilog keyword is printed as `name_\\output ` (an escaped identifier that
     does not start with a backslash) -> rename to name_output_e;
  2. a signal that is driven by an instance output is declared twice (`wire x;` ... `wire x;`) and
     tied to itself (`assign x = x; // (signal)`) -> drop the second declaration and the self-assign;
  3. VHDL nets joined through inout ports (the A2601's shared data bus: CPU, RIOT, TIA, cartridge mux,
     each driving 'Z' when not selected) are printed as one-way `assign a = b;` aliases, so a driver on one
     name never reaches the readers of the other (the CPU read the cartridge as 00) -> every class of
     wires joined by plain `assign a = b;` becomes ONE net (the port's name if a port is in it), and the
     multiple tri-state drivers of that net are left for Verilator to resolve.  Classes with a reg or with
     two ports are left alone.
  4. GHDL escapes only Verilog-2005 keywords, but GowinSynthesis reads every file of the build as SystemVerilog
     (build_core.tcl -verilog_std sysv2017): an identifier that is a SystemVerilog-only keyword (T80's port DO,
     printed "do" inside the flattened T80s) -> do_e.  Comments, strings and escaped identifiers are left alone;
     a rename onto a name already in the file is refused.
  5. (galaga-tango) an output port that nothing in the VHDL ever drives (mb88.vhd's sc_out_n/so_n/to_n -- the
     MB88xx's serial I/O, unused by Galaga's 51XX/54XX wiring; gen_video.vhd's csync, which galaga.vhd's own
     instance leaves unconnected) is printed BOTH as the port declaration (`output sc_out_n,` ...) AND as a
     same-named `localparam sc_out_n = 1'bZ;` inside the body -- a duplicate declaration (Verilator: "Duplicate
     declaration of signal"; same failure mode would hit GowinSynthesis).  The `localparam ... = 1'bZ;` line is
     dropped whenever its name is already an output port of the enclosing module, leaving the port genuinely
     undriven (a lint warning, not an error: nothing in galaga.vhd reads it either).
     (galaxian-tango) the same duplicate arises for an output that is a CONSTANT, not Z: T80se netlisted alone in
     Mode 0 has T80_MCode's outputs ldhlsp and addspdd tied to 0 (`localparam n7555_o = 1'b0;` + `assign ldhlsp =
     n7555_o;`), and merge_aliases (defect 3) gives the alias class the port's name, so the result is
     `localparam ldhlsp = 1'b0;` beside `output ldhlsp`.  A non-Z `localparam` named after an output port becomes
     `assign NAME = VALUE;` (the port keeps its constant driver); a Z one is dropped as above.
  6. (galaga-tango: the cause of the 54XX explosion channel's flat, saturated audio) a VHDL
     signed INTEGER division is printed as a plain Verilog `assign x = a / b; // sdiv` with NEITHER operand
     cast `$signed(...)` -- unlike the comparison operators GHDL emits elsewhere in the SAME module for the
     SAME signals (e.g. `$signed(uout) > $signed(32'd255)`, sound_lpf.vhd's own clamp), which GHDL correctly
     casts. Plain Verilog `/` on uncast `wire` operands is UNSIGNED, so whenever the dividend's two's-
     complement bit pattern represents a negative VHDL integer (confirmed live in sim: sound_lpf.vhd's
     `u3 <= u3 + du3/scale;` with du3=-370, scale=8192 produced u3=524287, i.e. (2^32-370)/8192 truncated --
     the UNSIGNED quotient -- instead of the correct signed result, 0) the division result is wildly wrong.
     Confirmed exhaustively, not just for this one site: EVERY "// sdiv"-tagged line in build/out/galaga.v
     (8 of 8, all of sound_lpf.vhd's own du3/du4/dt_over_c{3,4} terms) has zero `$signed` casts, while every
     comparison GHDL emits in the same file for the same class of signal IS cast -- a systematic GHDL 4.1
     Verilog-printer omission (division, unlike +/-/*, is not two's-complement-bit-pattern-agnostic, so this
     is the one arithmetic operator class the printer needed to cast and didn't). This single mis-division
     corrupted sound_lpf.vhd's own u3 integrator state to a huge, un-recoverable magnitude within ~5ms of
     reset release (every run observed, not input-dependent), permanently saturating all three of the 54XX
     explosion channel's discrete-filter outputs at +-255 (uout=u4-u3 swamped by the corrupted operand) for
     the rest of any run -- NOT a settling-time/latency characteristic as the prior pass's NOTICE entry
     named it, and NOT specific to the 54XX command's timing at all (reproduced with zero 54XX command
     activity, driven purely by the self-test's own idle/constant input). Every `// sdiv` line is rewritten
     to cast both operands `$signed(...)`, exactly mirroring GHDL's own already-correct comparison-operator
     casts for the identical signals two lines away -- this does not touch any vendored VHDL source file;
     it only makes the GENERATED Verilog match the VHDL's own already-correct signed-division semantics.
Usage: ghdl_fix_verilog.py in.v out.v
"""
import re, sys
src = open(sys.argv[1]).read().replace('\\output ', 'output_e')
# 1b. the same defect for any keyword-named signal inside a flattened instance: T80s's u0 (T80) port REG is printed
#     `u0_\reg ` -> u0_reg_e (a standalone `\reg `, vdp's signal REG, is a legal escaped identifier: left alone)
src = re.sub(r'(?<=[A-Za-z0-9_$])\\([A-Za-z_][A-Za-z0-9_$]*) ', r'\1_e', src)
out, seen = [], set()
decl = re.compile(r'^\s*wire\s*(\[[^\]]*\])?\s*([A-Za-z_][A-Za-z0-9_$]*)\s*;')
selfa = re.compile(r'^\s*assign\s+([A-Za-z_][A-Za-z0-9_$]*)\s*=\s*\1\s*;')
dropped = 0
for line in src.split('\n'):
    if line.startswith('module '):
        seen = set()
    m = decl.match(line)
    if m:
        if m.group(2) in seen:
            dropped += 1
            continue
        seen.add(m.group(2))
    if selfa.match(line):
        dropped += 1
        continue
    out.append(line)

def merge_aliases(text):
    mods = re.split(r'(?m)^(?=module )', text)
    res, merged = [], 0
    alias = re.compile(r'^\s*assign\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*;.*$', re.M)
    for m in mods:
        if not m.startswith('module '):
            res.append(m); continue
        hdr_end = m.index(');') + 2
        hdr, body = m[:hdr_end], m[hdr_end:]
        ports = set(re.findall(r'(?:input|output|inout)\s+(?:\[[^\]]*\]\s*)?(\w+)', hdr))
        regs = set(re.findall(r'^\s*reg\s+(?:\[[^\]]*\]\s*)?(\w+)', body, re.M))
        parent = {}
        def find(x):
            while parent.get(x, x) != x: x = parent[x]
            return x
        pairs = alias.findall(body)
        for a, b in pairs:
            ra, rb = find(a), find(b)
            if ra != rb: parent[ra] = rb
        classes = {}
        for a, b in pairs:
            for x in (a, b): classes.setdefault(find(x), set()).add(x)
        ren = {}
        for c in classes.values():
            if len(c) < 2 or c & regs: continue
            pc = c & ports
            if len(pc) > 1: continue
            rep = next(iter(pc)) if pc else min(c, key=lambda x: (bool(re.match(r'n\d+_', x)), len(x), x))  # keep the VHDL name
            for x in c:
                if x != rep: ren[x] = rep
        if not ren:
            res.append(m); continue
        merged += len(ren)
        lines = []
        for line in body.split('\n'):
            am = alias.match(line)
            if am and ren.get(am.group(1), am.group(1)) == ren.get(am.group(2), am.group(2)):
                continue                                  # the alias itself
            dm = decl.match(line)
            if dm and dm.group(2) in ren:
                continue                                  # a merged wire's declaration
            lines.append(line)
        body = '\n'.join(lines)
        # rename nets only: never a named port connection's pin name (".pin(net)")
        body = re.sub(r'(?<![.\w$])(' + '|'.join(map(re.escape, sorted(ren, key=len, reverse=True))) + r')(?![\w$])',
                      lambda mm: ren[mm.group(1)], body)
        res.append(hdr + body)
    print(f'ghdl_fix_verilog: {merged} alias nets merged', file=sys.stderr)
    return ''.join(res)

def drop_undriven_output_localparams(text):
    """Defect 5: a `localparam NAME = VALUE;` where NAME is already an output port of the module: dropped when VALUE
    is all Z (the port is undriven), else turned into `assign NAME = VALUE;`."""
    mods = re.split(r'(?m)^(?=module )', text)
    res, dropped, assigned = [], [], []
    lp = re.compile(r"^(\s*)localparam\s+([A-Za-z_]\w*)\s*=\s*([^;]+?)\s*;\s*$")
    for m in mods:
        if not m.startswith('module '):
            res.append(m); continue
        hdr_end = m.index(');') + 2
        hdr, body = m[:hdr_end], m[hdr_end:]
        outs = set(re.findall(r'output\s+(?:\[[^\]]*\]\s*)?(\w+)', hdr))
        lines = []
        for line in body.split('\n'):
            lm = lp.match(line)
            if lm and lm.group(2) in outs:
                if re.fullmatch(r"\d*'[bB][zZ]+", lm.group(3)):
                    dropped.append(lm.group(2)); continue
                assigned.append(lm.group(2))
                line = f"{lm.group(1)}assign {lm.group(2)} = {lm.group(3)};"
            lines.append(line)
        res.append(hdr + '\n'.join(lines))
    if dropped:
        print(f"ghdl_fix_verilog: {len(dropped)} undriven-output localparam(s) dropped {sorted(set(dropped))}",
              file=sys.stderr)
    if assigned:
        print(f"ghdl_fix_verilog: {len(assigned)} constant-output localparam(s) made assigns {sorted(set(assigned))}",
              file=sys.stderr)
    return ''.join(res)

# IEEE 1800-2017 Annex B keywords that are not IEEE 1364-2005 Annex B keywords
V2005 = set("""always and assign automatic begin buf bufif0 bufif1 case casex casez cell cmos config deassign default
 defparam design disable edge else end endcase endconfig endfunction endgenerate endmodule endprimitive endspecify
 endtable endtask event for force forever fork function generate genvar highz0 highz1 if ifnone incdir include
 initial inout input instance integer join large liblist library localparam macromodule medium module nand negedge
 nmos nor noshowcancelled not notif0 notif1 or output parameter pmos posedge primitive pull0 pull1 pulldown pullup
 pulsestyle_ondetect pulsestyle_onevent rcmos real realtime reg release repeat rnmos rpmos rtran rtranif0 rtranif1
 scalared showcancelled signed small specify specparam strong0 strong1 supply0 supply1 table task time tran tranif0
 tranif1 tri tri0 tri1 triand trior trireg unsigned use uwire vectored wait wand weak0 weak1 while wire wor xnor
 xor""".split())
SV2017 = V2005 | set("""accept_on alias always_comb always_ff always_latch assert assume before bind bins binsof bit
 break byte chandle checker class clocking const constraint context continue cover covergroup coverpoint cross dist
 do endchecker endclass endclocking endgroup endinterface endpackage endprogram endproperty endsequence enum
 eventually expect export extends extern final first_match foreach forkjoin global iff ignore_bins illegal_bins
 implements implies import inside int interconnect interface intersect join_any join_none let local logic longint
 matches modport nettype new nexttime null package packed priority program property protected pure rand randc
 randcase randsequence ref reject_on restrict return s_always s_eventually s_nexttime s_until s_until_with sequence
 shortint shortreal soft solve static string strong struct super sync_accept_on sync_reject_on tagged this
 throughout timeprecision timeunit type typedef union unique unique0 until until_with untyped var virtual void
 wait_order weak wildcard with within""".split())
SV_ONLY = SV2017 - V2005

def rename_sv_keywords(text):
    keep = re.compile(r'/\*.*?\*/|//[^\n]*|"(?:[^"\\\n]|\\.)*"|\\\S+', re.S)   # comments, strings, \escaped ids
    kw = re.compile(r"(?<![\w$'\\])(" + '|'.join(sorted(SV_ONLY, key=len, reverse=True)) + r")(?![\w$])")
    pieces, pos = [], 0
    for m in keep.finditer(text):
        pieces += [(False, text[pos:m.start()]), (True, m.group(0))]; pos = m.end()
    pieces.append((False, text[pos:]))
    found, ids = set(), set()
    for k, s in pieces:
        if not k:
            found |= set(kw.findall(s)); ids |= set(re.findall(r'[A-Za-z_][\w$]*', s))
    clash = sorted(f + '_e' for f in found if f + '_e' in ids)
    if clash:
        sys.exit(f'ghdl_fix_verilog: cannot rename SystemVerilog keywords, already used: {clash}')
    print(f'ghdl_fix_verilog: {len(found)} SystemVerilog keyword identifier(s) renamed to *_e {sorted(found)}',
          file=sys.stderr)
    return ''.join(s if k else kw.sub(r'\1_e', s) for k, s in pieces)

def fix_signed_division(text):
    """Defect 6: `assign x = a / b; // sdiv` -> `assign x = $signed(a) / $signed(b); // sdiv` --
    GHDL tags the comment but, unlike its own comparison-operator casts, never casts the operands,
    so plain Verilog `/` (unsigned on uncast wires) gives a wrong result whenever a two's-complement-
    negative VHDL integer is divided.  Operands seen so far are always a single identifier or a sized
    binary literal (`32'b...`), never a sub-expression -- the pattern is intentionally that narrow so
    it only ever touches a line shaped exactly like GHDL's own printer output, not a line this script
    itself rewrote some other way."""
    sdiv = re.compile(r"^(\s*assign\s+\w+\s*=\s*)([\w$]+(?:'[bdho][01xz_]+)?)\s*/\s*([\w$]+(?:'[bdho][01xz_]+)?)(;\s*//\s*sdiv\s*)$", re.M)
    n = 0
    def repl(m):
        nonlocal n
        n += 1
        return f'{m.group(1)}$signed({m.group(2)}) / $signed({m.group(3)}){m.group(4)}'
    text2 = sdiv.sub(repl, text)
    want = text.count('// sdiv')
    if n != want:
        sys.exit(f'ghdl_fix_verilog: fix_signed_division matched {n} of {want} "// sdiv" lines -- '
                  f'a line has an unexpected shape, fix the pattern before trusting this output')
    print(f'ghdl_fix_verilog: {n} signed-division operand(s) cast $signed (GHDL defect 6)', file=sys.stderr)
    return text2

open(sys.argv[2], 'w').write(
    fix_signed_division(rename_sv_keywords(drop_undriven_output_localparams(merge_aliases('\n'.join(out))))))
print(f'ghdl_fix_verilog: {dropped} lines dropped', file=sys.stderr)
