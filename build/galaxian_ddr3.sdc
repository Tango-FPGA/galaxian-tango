// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// galaxian_ddr3.sdc -- the core clock of build/build_galaxian.sh (TANGO_VIDEO_DDR3: no SDRAM clock; build_core.sh
// adds the DDR3's own clocks to the clock-group line below).  clk_sys is the PLL's CLKOUT0 (rtl/galaxian_clocks.v,
// rtl/pll_galaxian_mod.v): 725 MHz / 29.5 = 24.576271 MHz, period 40.690 ns.  It is named at the PLL primitive's
// output pin because the wrapper's net alias does not survive synthesis.  TA1123 (STA's own PLL frequency differs:
// it ignores the ODIV0 fraction) is expected.
// Adapted from scramble-tango build/scramble_ddr3.sdc (the same authors; the same 24.576 MHz clock).
create_clock -name gx_clk -period 40.690 [get_pins {u_sys/u_core/u_clocks/u_pll/PLL_inst/CLKOUT0}]
set_clock_groups -asynchronous -group [get_clocks {gx_clk}] -group [get_clocks {clk}] -group [get_clocks {clk27}] -group [get_clocks {clk_ser clk_pix}] -group [get_clocks {clk48}] -group [get_clocks {spi_sck}] -group [get_clocks {clk_audio}]
// The board SDC's report_timing lists the 300 worst paths of all clocks, which the faster framework clocks fill;
// this lists the core clock's own worst paths.
report_timing -setup -to [get_clocks {gx_clk}] -max_paths 10 -max_common_paths 1
