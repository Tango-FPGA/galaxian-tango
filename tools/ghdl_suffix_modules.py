#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
"""ghdl_suffix_modules.py -- give every module of one GHDL netlist a new name, so that two netlists of the same VHDL
entity built with different generics can be compiled together.

GHDL names a unit's sub-modules after the entity and the generics it passes down (T80se's T80 instance is
t80_0_1_0_1_... whatever T80se's own T2Write is), so the netlists of `T80se` and of `T80se -gT2Write=1` both define
t80_reg, t80_alu_..., t80_mcode_... and t80_... .  This script renames, in one netlist, every `module NAME` and every
instantiation of NAME: the top module (the last one GHDL prints) becomes TOP, every other module NAME_SUFFIX.

    ghdl_suffix_modules.py IN.v OUT.v TOP SUFFIX

Only whole identifiers that are module names are changed, and only where they open a module declaration or an
instantiation (`NAME instance (` / `NAME #(`).  Comments are left alone.  A new name that already occurs in the file
is refused.
"""
import re
import sys


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    src, dst, top, suffix = sys.argv[1:]
    text = open(src).read()
    mods = re.findall(r"^module\s+([A-Za-z_][A-Za-z0-9_$]*)", text, flags=re.M)
    if not mods:
        sys.exit(f"ghdl_suffix_modules: no module in {src}")
    new = {m: m + "_" + suffix for m in mods}
    new[mods[-1]] = top
    for m, n in new.items():
        if re.search(r"\b" + re.escape(n) + r"\b", text):
            sys.exit(f"ghdl_suffix_modules: new name {n} already occurs in {src}")
    names = "|".join(re.escape(m) for m in sorted(mods, key=len, reverse=True))
    n_decl = n_inst = 0

    def decl(mo):
        nonlocal n_decl
        n_decl += 1
        return mo.group(1) + new[mo.group(2)]

    def inst(mo):
        nonlocal n_inst
        n_inst += 1
        return mo.group(1) + new[mo.group(2)] + mo.group(3)

    text = re.sub(r"^(module\s+)(" + names + r")\b", decl, text, flags=re.M)
    text = re.sub(r"^(\s+)(" + names + r")(\s+(?:#\s*\(|[A-Za-z_\\][^\s(]*\s*\())", inst, text, flags=re.M)
    if n_decl != len(mods):
        sys.exit(f"ghdl_suffix_modules: renamed {n_decl} declarations, expected {len(mods)}")
    open(dst, "w").write(text)
    print(f"ghdl_suffix_modules: {src}: {n_decl} modules, {n_inst} instantiations renamed; top {mods[-1]} -> {top}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
