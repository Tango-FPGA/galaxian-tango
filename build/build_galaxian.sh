#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (c) 2026 the Tango authors
# build_galaxian.sh -- build the Galaxian-family core for the Tang Console 138K on the Tango framework, STA-gate it
# and archive it.  The card build: ascal scaler with its frames in DDR3, the framework's video options and
# processing, screen rotation (every game is portrait; the counter-clockwise games ask for the other turn,
# TANGO_VIDEO_ROTATE_CCW) and the upload direction (hiscore.v's NVRAM save).
#   build/build_galaxian.sh                 release build (no debug overlay)
#   DBGOV=1 build/build_galaxian.sh         dev build: adds the debug overlay (GX_DBG_OV, rtl/tango/gx_dbg_ov.v)
#   GX_NOGHDL=1 ...                         reuse build/out/ghdl/ (a previous run's T80 netlists) instead of re-running GHDL
#   GX_SUFFIX=<tag> ...                     a separate build name, output directory and archive name (side-by-side builds)
#   TAG=<text> ...                          dev builds: the build identity's first word (overlay row 0), default NOTAG
# Steps: build/galaxian_ghdl.sh makes the T80 netlists (build/out/ghdl/T80se.v, T80se_t2w.v); sys/board/console138k/
# build_core.sh builds the board top, the framework and the files below with build/galaxian_ddr3.sdc;
# sys/build_tools/sta_gate.py gates timing (every clock: no setup/hold violation, Fmax >= constraint, fill <= 98%).
# Archive: <repo>/bitstreams/ (git-ignored) <name>_<YYYYMMDD-HHMM>_g<git>[-dirty]_ddr3_rotate[_dbgov].{fs,bin,txt};
# a failing gate is archived as ..._STA-FAIL and printed as do-not-flash.  Never flashes anything.
# Gowin needs several GB of memory; build_core.sh runs it under sys/build_tools/tango_capped.sh (a memory cap).
# The build refuses to start until the wrapper's leaf sections exist (rtl/tango/gx_dl_ctrl.v, gx_hs_seq.v,
# gx_pad_map.v and the gx_top instance in rtl/tango_galaxian.v): without them the bitstream would hold no game.
# Adapted from scramble-tango build/build_scramble.sh and arcade-template-tango's ascal build (the same authors).
set -eu
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
. "$ROOT/build/galaxian_files.sh"
NAME=tango_galaxian_138
WRAP="$ROOT/rtl/tango_galaxian.v"
MISSING=""
for m in gx_dl_ctrl gx_hs_seq gx_pad_map; do [ -f "$ROOT/rtl/tango/$m.v" ] || MISSING="$MISSING rtl/tango/$m.v"; done
grep -qE '^[[:space:]]*gx_top[[:space:]]+u_game' "$WRAP" || MISSING="$MISSING (rtl/tango_galaxian.v SECTION 7: gx_top u_game)"
[ -z "$MISSING" ] || { echo "build_galaxian.sh: the wrapper is not assembled yet, missing:$MISSING"; exit 2; }
GHO="$ROOT/build/out/ghdl"
if [ "${GX_NOGHDL:-0}" = 1 ] && [ -f "$GHO/T80se.v" ] && [ -f "$GHO/T80se_t2w.v" ]; then echo "GX_NOGHDL=1: using $GHO as is"
else "$ROOT/build/galaxian_ghdl.sh" "$GHO"; fi
[ -n "${GX_SUFFIX:-}" ] && NAME=${NAME}_${GX_SUFFIX}
SHA=$(git rev-parse --short HEAD 2>/dev/null || echo nogit)
DTAG=""; [ -n "$(git status --porcelain --untracked-files=all -- rtl build/*.sh build/*.sdc tools sys 2>/dev/null)" ] && DTAG="-dirty"   # untracked sources count
# rtl/tango/*.v except the overlay, which only a dev build compiles
TANGO_V=""
for f in "$ROOT"/rtl/tango/*.v; do [ "$(basename "$f")" = gx_dbg_ov.v ] || TANGO_V="$TANGO_V $f"; done
FILES="$WRAP $ROOT/rtl/galaxian_clocks.v $ROOT/rtl/pll_galaxian_mod.v$TANGO_V $GX_VERILOG $ROOT/rtl/galaxian/hiscore.v"
for u in $GX_UNITS; do FILES="$FILES $GHO/$u.v"; done
VTAG=""
if [ "${DBGOV:-0}" = 1 ]; then
    # the dev build's identity on overlay row 0: "<TAG> G<sha>[-D]", 25 characters, upper case, overlay glyphs only
    BID=$(printf '%s G%s%s' "${TAG:-NOTAG}" "$SHA" "$([ -n "$DTAG" ] && echo -D)" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9 :/=._\n-' '-')
    BID=$(printf '%-25.25s' "$BID")
    NAME=${NAME}_dbgov; VTAG="_dbgov"; mkdir -p "$ROOT/build/out"
    DEF="$ROOT/build/out/gx_dbg_def.v"
    printf '`define GX_DBG_OV\n`define GX_BUILD_ID "%s"\n' "$BID" > "$DEF"
    python3 "$ROOT/tools/gen_gx_dbg_ov.py" "$ROOT/build/out/gx_dbg_ov_check.v" > /dev/null
    cmp -s "$ROOT/build/out/gx_dbg_ov_check.v" "$ROOT/rtl/tango/gx_dbg_ov.v" ||
        { echo "build_galaxian.sh: rtl/tango/gx_dbg_ov.v is not what tools/gen_gx_dbg_ov.py writes: re-run the generator"; exit 2; }
    FILES="$DEF $FILES $ROOT/rtl/tango/gx_dbg_ov.v"
fi
OPTS="TANGO_VIDEO_ASCAL=1 TANGO_VIDEO_DDR3=1 TANGO_VIDEO_OPTS=1 TANGO_VIDEO_PROC=1 TANGO_VIDEO_ASCAL_MAXW=256 TANGO_IOCTL_UPLOAD=1 TANGO_VIDEO_ROTATE=1 TANGO_VIDEO_ROTATE_CCW=1"
CSDC="$ROOT/build/galaxian_ddr3.sdc"
START=$(mktemp); trap 'rm -f "$START"' EXIT
set +e
# shellcheck disable=SC2086  # OPTS and FILES are word lists
env $OPTS TANGO_NO_ARCHIVE=1 TANGO_OUT=build/out \
    "$ROOT/sys/board/console138k/build_core.sh" "$NAME" "$CSDC" $FILES
BC=$?
set -e
IMPL="$ROOT/build/out/$NAME/impl/pnr"
FS="$IMPL/$NAME.fs"
[ $BC -eq 0 ] && [ -f "$FS" ] && [ "$FS" -nt "$START" ] || { echo "NO FRESH BITSTREAM (build_core.sh exit $BC)"; exit 1; }
# STRICT gate (no --relax): a DDR3 build has no clk_sdram clock
set +e; GATE=$(python3 "$ROOT/sys/build_tools/sta_gate.py" "$IMPL"); SG=$?; set -e
echo "$GATE"
FSHA=$(git -C sys rev-parse --short=12 HEAD); FDIRTY=$(git -C sys status --porcelain --untracked-files=no | wc -l)
ARCH="$ROOT/bitstreams"; mkdir -p "$ARCH"
STAMP="$ARCH/${NAME%_dbgov}_$(date +%Y%m%d-%H%M)_g${SHA}${DTAG}_ddr3_rotate${VTAG}"; [ $SG -ne 0 ] && STAMP="${STAMP}_STA-FAIL"
cp "$FS" "$STAMP.fs" && cmp "$FS" "$STAMP.fs" && chmod 444 "$STAMP.fs"
python3 "$ROOT/sys/build_tools/fs2bin.py" "$STAMP.fs" "$STAMP.bin" && chmod 444 "$STAMP.bin"
{ echo "galaxian-tango $SHA$DTAG (scaler+rotate: $OPTS)$([ -n "$VTAG" ] && echo ", GX_DBG_OV (dev build)")"
  echo "framework: sys/ = sys-tango $FSHA (uncommitted files in sys/: $FDIRTY)"
  echo "upstream MiSTer-devel/Arcade-Galaxian_MiSTer e6b4dc5 (NOTICE)"
  for u in $GX_UNITS; do
      echo "netlist: sha256 $(sha256sum "$GHO/$u.v" | cut -c1-64) build/out/ghdl/$u.v$([ "${GX_NOGHDL:-0}" = 1 ] && echo ' (GX_NOGHDL=1: reused, not rebuilt)')"
  done
  echo "BUILD_DATE v${TANGO_BUILD_DATE:-$(date +%y%m%d)} (in the CONF_STR: a different date is a different netlist and placement)"
  [ -n "$VTAG" ] && echo "build identity (overlay row 0): \"GX $BID\""
  (cd "$ARCH" && sha256sum "$(basename "$STAMP").fs" "$(basename "$STAMP").bin" | sed 's/^/sha256: /')
  echo; echo "$GATE"
  grep -E "^\s*(Logic|CLS|Register|BSRAM|DSP|PLL)\s*\|" "$IMPL/$NAME.rpt.txt" || true; } > "$STAMP.txt"
chmod 444 "$STAMP.txt"
ls -l "$STAMP".*
[ $SG -ne 0 ] && { echo "WARNING: STA GATE FAIL -- do NOT flash"; exit 1; }
exit 0
