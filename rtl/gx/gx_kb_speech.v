// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_kb_speech.v -- King & Balloon speech board (KB p15, "Sound Synthesizer PCB", drawing 02-70103).
//
// Board: IC9 Z80 clocked at 2.5 MHz (5 MHz crystal oscillator IC1, halved by IC2 74LS74).  IC3 74LS138, enabled by
// /A13 with /MREQ and /RD, selects IC4/IC5/IC6 2716 from A11/A12 (0000/0800/1000; the fourth output is unused, so
// 1800-1FFF is open on the board).  IC7/IC8 2114 (1 KB) are selected by A13 with /MREQ (IC12 74LS32); A10-A12 and
// A14/A15 are not decoded, so the RAM mirrors through 2000-3FFF (and 6000-7FFF, A000-BFFF, E000-FFFF).  No I/O
// address decode: any IORQ read enables IC13 74LS367 (IN0..IN3 on J2 pins 4-7 onto D0..D3, D4..D7 pulled high);
// any IORQ write clocks IC14 74LS273 (cleared by the board's POR) from /IORQ | /WR.  INT, NMI, WAIT and BUSRQ are
// pulled up (R6), so the CPU runs without interrupts or wait states.  IC14 drives IC10/IC11 4050 buffers into the
// resistor ladder, IC15 TL081 buffers it, IC16 TL082 filters it (gx_kb_filter), R33 47K is the output.
// MAME galaxian.cpp: kingball_sound_map / kingball_sound_portmap :2959-2972, soundlatch = sound bits | F0
// :1448-1458, Z80 at 5000000/2 :7961.
//
// Inputs from the main board 9N 74LS259: trig[0] = Q0 (main CPU B000), trig[1] = Q2 (B002) (KB p14).  IN2/IN3 (J2
// pins 6/7) go to ground through jumpers C and B, so an IORQ read returns {1111, 0, 0, Q2, Q0}; the speech program
// compares that value with F0..F3 exactly, so they must read 0.  F1, F2 or F3 plays one of three 4-bit sample
// tables, F0 is idle.
//
// DAC: the ladder is taken as linear on the full byte, V = 5 V * code / 256 (full scale 5 V: the 4050 supply is not
// drawn, +5 V assumed).  The ladder's series resistor between the D4 and D3 nodes, R19, is 30K, not 15K, and jumper A
// grounds its lower end: with A fitted, D7..D4 form an exact 4-bit R-2R ladder and D3..D0 have no effect; with A open
// the levels are not linear.  The program writes only the high nibble (low nibble always 0), so for every value it
// writes, linear-on-the-byte gives the levels of the 4-bit ladder with A fitted.  In Q5.11 volts that is code * 40.
//
// Download: image addresses 7000-8FFF load ROM 0000-1FFF (index = addr - 7000); 8800-8FFF is kbe2.ic7, the same
// data as IC5, so 1800-1FFF mirrors 0800-0FFF as MAME loads it.
//
// speech: the filtered output, signed Q5.11 volts (1 LSB = 1/2048 V, range -16 .. +16 V), updated 13 clk after
// each ce_48k.  It swings about -4.1 .. +9.13 V on the speech data (the filter's resonance), so Q4.12 would clip.
`default_nettype none
module gx_kb_speech (
    input  wire               clk,
    input  wire               reset,      // system reset (the board's POR), not the main-board watchdog
    input  wire               ce_2m5,     // gx_ce_frac: 2.5 MHz CPU clock enable
    input  wire               ce_48k,
    input  wire [15:0]        dn_addr,
    input  wire [7:0]         dn_data,
    input  wire               dn_wr,
    input  wire [1:0]         trig,       // {9N Q2, 9N Q0}
    output wire signed [15:0] speech
);
    wire [15:0] a;
    wire [7:0]  cpu_do;
    wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
    reg  [7:0]  cpu_di;

    T80se u_cpu (
        .RESET_n(~reset), .CLK_n(clk), .CLKEN(ce_2m5),
        .WAIT_n(1'b1), .INT_n(1'b1), .NMI_n(1'b1), .BUSRQ_n(1'b1),
        .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
        .RFSH_n(rfsh_n), .HALT_n(halt_n), .BUSAK_n(busak_n),
        .A(a), .DI(cpu_di), .DO(cpu_do)
    );

    wire mreq = ~mreq_n;
    wire iorq = ~iorq_n;
    wire rd   = ~rd_n;
    wire wr   = ~wr_n;

    // ROM 8K: port A = download, port B = CPU
    wire [15:0] rom_wa = dn_addr - 16'h7000;
    wire        rom_we = dn_wr & (dn_addr[15:12] == 4'h7 || dn_addr[15:12] == 4'h8);
    wire [7:0]  rom_q;
    wire [7:0]  rom_qa_unused;
    gx_dpram #(.AW(13), .DW(8)) u_rom (
        .clk(clk), .we_a(rom_we), .addr_a(rom_wa[12:0]), .d_a(dn_data), .q_a(rom_qa_unused),
        .addr_b(a[12:0]), .q_b(rom_q)
    );

    // RAM 1K at A13 = 1: port A = CPU
    wire        ram_we = mreq & wr & a[13];
    wire [7:0]  ram_q;
    wire [7:0]  ram_qb_unused;
    gx_dpram #(.AW(10), .DW(8)) u_ram (
        .clk(clk), .we_a(ram_we), .addr_a(a[9:0]), .d_a(cpu_do), .q_a(ram_q),
        .addr_b(10'd0), .q_b(ram_qb_unused)
    );

    // data bus into the CPU (undriven bus reads FF)
    always @* begin
        if (mreq & rd & ~a[13])
            cpu_di = rom_q;
        else if (mreq & rd & a[13])
            cpu_di = ram_q;
        else if (iorq & rd)
            cpu_di = {4'hF, 2'b00, trig};
        else
            cpu_di = 8'hFF;
    end

    // IC14 74LS273 DAC latch: any IORQ write; DO is stable for the whole write, so loading while /IORQ and /WR are
    // both low leaves the value the 273 takes on the rising edge of /IORQ | /WR.
    reg [7:0] dac;
    always @(posedge clk) begin
        if (reset)
            dac <= 8'd0;
        else if (iorq & wr)
            dac <= cpu_do;
    end

    // ladder: V = 5 * dac / 256 = dac * 40 in Q5.11
    wire signed [15:0] v_dac = $signed({3'b000, dac, 5'd0}) + $signed({5'b00000, dac, 3'd0});

    gx_kb_filter u_filt (
        .clk(clk), .reset(reset), .ce_48k(ce_48k), .x(v_dac), .y(speech)
    );

    wire unused_ok = &{1'b0, m1_n, rfsh_n, halt_n, busak_n, a[15:14], rom_wa[15:13],
                       rom_qa_unused, ram_qb_unused};
endmodule
`default_nettype wire
