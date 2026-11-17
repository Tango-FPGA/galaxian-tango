# galaxian-tango -- the Galaxian family for the Tango FPGA system

**Version 2026-11-17** (date code `20261117`)

galaxian-tango runs the **Namco Galaxian arcade hardware and its relatives** on the Tango FPGA system for the
**Sipeed Tang Console 138K**: Galaxian, Moon Cresta, King and Balloon (with its speech board), UniWar S, Pisces, Black
Hole, Orbitron, War of the Bugs and the other games of MiSTer's
[Arcade-Galaxian_MiSTer](https://github.com/MiSTer-devel/Arcade-Galaxian_MiSTer) core, with their clones and
bootlegs, all on one core. The game logic is the Tango authors' own Verilog, written from the original boards'
schematics and manuals; the CPU is the T80. Each game is launched from an **`.mra`** file the way MiSTer launches
arcade cores, and its ROMs come from **your own MAME ROM zip** at run time: no ROM data is in the bitstream, and the
only ROM data in this repository is the program of the two homebrew games, which their `.mra` files carry inline as
MiSTer publishes them.

Like every Tango core it is built on the framework [sys-tango](https://github.com/Tango-FPGA/sys-tango), which this
repository includes as a git submodule at `sys/`. The BL616 firmware that reads the `.mra`, loads the core and draws
its menu is [firmware-tango](https://github.com/Tango-FPGA/firmware-tango); the launcher is
[menu-tango](https://github.com/Tango-FPGA/menu-tango).

## Contents

- [On the board](#on-the-board)
- [The games](#the-games)
- [Playing](#playing)
- [Building from source](#building-from-source)
- [Layout](#layout)
- [Licence](#licence)

## On the board

You need a Tang Console 138K with [firmware-tango](https://github.com/Tango-FPGA/firmware-tango) in its BL616 -- a
version with `.mra` index 1 and 3 support (older versions cannot select the game or load the hi-score table) -- and
[menu-tango](https://github.com/Tango-FPGA/menu-tango)'s launcher on a FAT32 SD card (firmware-tango's README, "The SD
card"), and your own ROM sets in MAME's format.

The core is in this repository's **`releases/`** folder, one file per release named `Arcade-galaxian_<YYYYMMDD>.bin`
(this version: `releases/Arcade-galaxian_20261117.bin`). Take the latest (the newest date) and copy it to the
card's `/_Arcade/cores/` under the same name.

| On the card | What |
|---|---|
| `/_Arcade/<game>.mra` | the `.mra` files of this repository's `mra/` folder, one per game |
| `/_Arcade/_alternatives/_<family>/<clone>.mra` | the `.mra` files of `mra/_alternatives/` (clones and bootlegs), in the same folders, as on MiSTer |
| `/_Arcade/cores/Arcade-galaxian_<YYYYMMDD>.bin` | the core: the newest **`releases/Arcade-galaxian_<YYYYMMDD>.bin`** from this repository (the card build, `build/build_galaxian.sh`), or your own build (below); the firmware resolves the `.mra`'s `<rbf>galaxian</rbf>` to `Arcade-galaxian_<date>.bin` (or `galaxian_<date>.bin`), the greatest name winning |
| `/games/mame/<set>.zip` | your MAME ROM zips (`/_Arcade/mame/` works too), named as each `.mra`'s `zip=` attribute says (e.g. `galaxian.zip`, `mooncrst.zip`, `kingball.zip`, `uniwars.zip`) |

**Use the `.mra` files from this repository, not MiSTer's.** They are made from MiSTer's, with the game byte and the
direction the core needs, the DIP switches of the original boards and the buttons this core has. The firmware checks
each image's md5 before it sends anything: a different ROM set is refused, not half-loaded.

## The games

`mra/` holds 19 games: Azurian Attack, Black Hole, Catacomb, Clean Sweep, Devil Fish, Galaxian (Namco, Set 1), King
and Balloon (US) and (Japan), Lucky Today, Moon Cresta [bl], Moon Quasar, Mr. Do's Nightmare, Omega [bl], Orbitron,
Pisces, Portman, UniWar S, Victory and War of the Bugs. Clean Sweep and Mr. Do's Nightmare are homebrew games with no
MAME set: their `.mra` files carry the program inline, as MiSTer's do, so they need no zip. `mra/_alternatives/` holds 34 clones and bootlegs in four families: `_Galaxian` (Midway, Taito, Irem,
Swarm, Zero Time, Moon Alien, Star Fighter and the hacks and bootlegs), `_Pisces`, `_Uniwars` (Gingateikoku no
Gyakushu, Space Battle, Galaxy Empire and others) and `_War of the Bugs`.

All of them are portrait games. Most turn the monitor clockwise; Devil Fish, Lucky Today, Moon Cresta, Omega,
Orbitron and Victory turned it counter-clockwise in their cabinets, and the core turns these the same way: for them
the Video page's Rotation CW and CCW are swapped, so one saved Rotation setting stands every game upright.

## Playing

Launch a game from the launcher's Arcade list. The menu (Start + Select on a pad) has the core's pages:

- **Video**: Aspect ratio, Scale, Scanlines and the framework's video processing, and **Rotation** (Normal, CW,
  CCW). Choose CW or CCW to stand the game upright on a landscape screen, or Normal for a screen turned on its side.
- **Audio Boost**: +15 dB (the default), 4x, 2x or No. "No" is the board's own level; the boost raises it with a
  soft knee instead of clipping.
- **DIP Switches**: each game's switches from its `.mra` (Lives, Bonus, Coinage, Cabinet and the game's own), set and
  saved per game. Cabinet Cocktail flips the picture for player 2's turn, as the board does.
- **Reset**, **Reset and close OSD**.

The core's buttons are **Fire, Start 1P, Start 2P, Coin, Service**; a button a game does not read is shown as "-" in
its `.mra`. The `.mra` files set no default layout: define the buttons for your pad in the menu (System, Define
buttons) and save. The ship or player moves with the pad's d-pad. Both pads drive the one control panel, and either
pad's Coin drops a coin.

**Hi-scores:** the games whose `.mra` declares a hi-score table keep it between launches: the firmware saves the table
as a `.nvm` file when you leave the game for the launcher and loads it again at the next launch.

## Building from source

You need, on Linux (x86-64):

- **Gowin EDA** (the IDE with `gw_sh`), V1.9.11.03, with a licence for the GW5AST-138 and its DDR3 Memory Interface
  IP. The framework's `build_core.sh` runs it headless from `$GOWIN_HOME/IDE` (default `~/gowin`) and takes Gowin's
  `PLL_INIT` and the DDR3 IP from that installation (sys-tango README, "Building").
- **GHDL 4.1** with its `--synth` Verilog output (4.1.0 tested): the T80 CPU becomes two Verilog netlists,
  `build/out/ghdl/T80se.v` and `T80se_t2w.v` (`build/galaxian_ghdl.sh`, with `tools/ghdl_fix_verilog.py` and
  `tools/ghdl_suffix_modules.py`); **Verilator** (5.020 tested) is needed too: the script checks each netlist with
  `--lint-only` and stops on an error.
- **Python 3**, and **systemd** user scopes for `tango_capped.sh`, which runs each job in a memory-capped cgroup.
  A 138K build needs a few GB of memory; run one build at a time.

Get the sources with the framework:

    git clone https://github.com/Tango-FPGA/galaxian-tango.git
    cd galaxian-tango
    git submodule update --init          # sys/ = sys-tango, at the commit this release was built with

Build:

    build/build_galaxian.sh        # the card build: scaler + DDR3 frame buffers, video and audio processing, rotation

It makes the T80 netlists, runs the framework's `sys/board/console138k/build_core.sh` (the Gowin project in
`build/out/<name>/`), then the STA gate (`sys/build_tools/sta_gate.py`: no setup or hold violation, every clock at
or above its constraint, logic and block RAM at most 98%; never use a build whose gate failed), and archives the
result in `bitstreams/` as `<name>_<YYYYMMDD-HHMM>_g<commit>_ddr3_rotate.{fs,bin,txt}` (`..._STA-FAIL` when the gate
failed; the `.txt` holds the gate's report, the resource use and the netlists' sha256). Copy the `.bin` to the card as
`/_Arcade/cores/Arcade-galaxian_<date>.bin`. `DBGOV=1 build/build_galaxian.sh` makes a development build with an
on-screen debug overlay (`rtl/tango/gx_dbg_ov.v`, written by `tools/gen_gx_dbg_ov.py`); release builds leave it out.

`TANGO_BUILD_DATE=<YYMMDD>` sets the build date the menu shows (`V,v<YYMMDD>`; the default is today); this release's
`releases/Arcade-galaxian_20261117.bin` was built with `TANGO_BUILD_DATE=261117`, and the same command with that
date rebuilds it bit for bit (Gowin V1.9.11.03, GHDL 4.1.0). The build's timing depends on placement, which changes
with the build date: if its STA gate fails, build again with another `TANGO_BUILD_DATE`.

## Layout

| Path | What |
|---|---|
| `releases/` | the core bitstreams, `Arcade-galaxian_<YYYYMMDD>.bin`, one per release (copy the latest to the card's `/_Arcade/cores/`) |
| `rtl/gx/` | the game logic, the Tango authors' own Verilog (`gx_top.v` and its modules: timing, video, stars, missiles, inputs, sound, King and Balloon's speech board) |
| `rtl/tango_galaxian.v` | the core (module `tango_core`): the framework's interface around `gx_top`, the ROM / DIP / hi-score downloads, the pads, rotation, audio and the Audio Boost |
| `rtl/galaxian_clocks.v`, `rtl/pll_galaxian_mod.v` | the core's clock: 50 MHz to 24.576 MHz (+11 ppm) |
| `rtl/tango/` | the wrapper's own modules: the download decode, the hi-score reset sequencer, the pad map, the Audio Boost `tg16_aboost.v`, the dev build's debug overlay `gx_dbg_ov.v` |
| `rtl/galaxian/` | the T80 CPU from Arcade-Galaxian_MiSTer, unchanged, and MiSTer's hi-score module `hiscore.v` with three changes (`rtl/galaxian/README.md`: the commit and each file's sha256) |
| `mra/` | the `.mra` files: one per game, clones and bootlegs in `mra/_alternatives/` |
| `build/` | the Gowin build, the GHDL netlist script and its file list, the core's timing constraints |
| `tools/` | the netlist post-processors (`ghdl_fix_verilog.py`, `ghdl_suffix_modules.py`), the generators of the sound, mixer, filter and colour constants in `rtl/gx/` (`gx_snd_coefs.py`, `gx_snd_consts.py`, `gx_mix_coefs.py`, `gx_kb_filter.py`, `gx_colour_levels.py`) and of the debug overlay (`gen_gx_dbg_ov.py`) |
| `sys/` | the framework, [sys-tango](https://github.com/Tango-FPGA/sys-tango) (git submodule) |

## Licence

The Tango authors' files are **GPL-3.0-or-later** (`LICENSE`), `Copyright (c) 2026 the Tango authors`, as their
`SPDX-License-Identifier` headers say. The files from Arcade-Galaxian_MiSTer keep their own authors and terms, which
`NOTICE` sets out in full:

- **T80** (`rtl/galaxian/T80/`), Copyright (c) 2001-2002 Daniel Wallner, under a BSD-style licence whose text
  `NOTICE` reproduces.
- **`rtl/galaxian/hiscore.v`**, MiSTer's hi-score module (Copyright (c) 2021 Alan Steremberg and Jim Gregory),
  GPL-3.0-or-later, with the Tango authors' changes.
- The `.mra` files are made from MiSTer's. They contain no ROM data, except the two homebrew games' files
  (`mra/Clean Sweep.mra`, `mra/Mr. Do Nightmare.mra`), which carry their program inline as published in MiSTer's
  Arcade-Galaxian release; `NOTICE` says what is known about that data.

**The bitstream (`releases/Arcade-galaxian_<YYYYMMDD>.bin`)** combines all of these with sys-tango (MIT, with
GPL-2.0-or-later files derived from MiSTer; its `NOTICE`). It is distributed under the terms of **GPL-3.0-or-later**
(`LICENSE`), together with the T80 notice; its source is this repository at the release's commit, with sys-tango at
`sys/` (the commit the submodule points at). No ROM data is in the bitstream. `PLL_INIT` and
the DDR3 Memory Interface IP, which the build takes from the Gowin installation, keep Gowin's terms.

Galaxian is a trademark of Bandai Namco Entertainment; the other game names belong to their owners. This project is
not affiliated with or endorsed by any of them.
