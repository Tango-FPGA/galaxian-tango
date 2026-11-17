# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# galaxian_files.sh -- the core's source lists (sourced by build/galaxian_ghdl.sh).
# $ROOT = the repo.
#
# GX_VHDL: the only VHDL, the vendored T80 (rtl/galaxian/, byte-identical to upstream; rtl/galaxian/README.md), in
# compile order; GX_UNITS: the netlists made by GHDL, one Verilog module each.  A unit's VHDL entity and generics are
# GX_UNIT_<unit> ("<entity> <ghdl -g options>"), or the unit's own name with the default generics when that is unset:
#   T80se      King and Balloon's speech CPU (default generics)
#   T80se_t2w  the main CPU: T80se with T2Write = 1 (WR_n and MREQ_n from T2, so writes see the board's WAIT,
#              rtl/gx/gx_wait_nmi.v); its sub-modules get the suffix _t2w so both netlists compile together
# GX_VERILOG: the Tango authors' Verilog game logic (rtl/gx/) and the clocks.
G=$ROOT/rtl/galaxian
GX_VHDL="$G/T80/T80_Pack.vhd $G/T80/T80_ALU.vhd $G/T80/T80_MCode.vhd $G/T80/T80_Reg.vhd $G/T80/T80.vhd $G/T80/T80se.vhd"
GX_UNITS="T80se T80se_t2w"
GX_UNIT_T80se_t2w="T80se -gT2Write=1"
GX_VERILOG="$(ls "$ROOT"/rtl/gx/*.v | tr '\n' ' ')"
