// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_top.v -- the Galaxian-family game logic: main CPU, its memory and I/O, the video board (gx_video), the sound
// board (gx_pitch, gx_snd_bg / hit / fire, gx_snd_mix) and King & Balloon's speech board (gx_kb_speech).
//
//
// Clocks: one clock, clk (24.576 MHz), with enables from gx_ce (ce_12m, ce_pr = 6MHZ rising, ce_pf = /6MHZ rising,
// ce_1m5), ce_48k (a 9-bit counter: 24.576 MHz / 512) and gx_ce_frac (ce_2m5, the speech CPU).  The main Z80 is
// clocked by 1H rising: ce_cpu = ce_pr & ~h[0] (gx_ce.ce_3m is not used: it is not tied to the H counter's phase);
// ce_wait = ce_pr & h[0] is 1H falling, where gx_wait_nmi samples the WAIT request.
//
// Main CPU: T80se built with T2Write = 1 (module T80se_t2w, build/galaxian_ghdl.sh), so writes assert WR_n / MREQ_n
// in T2 and wait like reads.  RESET_n = ~game_reset_q (system reset or the 6T watchdog, registered); BUSRQ_n = 1.
// game_reset_q / reset_q: one-flop registered copies of game_reset and reset.  The T80 netlists' RESET_n is an
// asynchronous reset, and the wrapper's reset is combinational (a download-index decode that can glitch), so every
// asynchronous reset (both T80s) and the 9N / 9L / 9M clears take the registered copy; the synchronous resets of the
// other leaves and gx_video's download write gate take reset itself.
// Address decode gx_addr_dec (per-game map flags from gx_flags); every write strobe is qualified by gx_wait_nmi's
// WEN (only the video-RAM write is ever held back).  The 9N / 9L / 9M 74LS259 latches take A2..A0 and D0 and are
// cleared by game_reset_q; the 9J pitch latch takes the data byte.
//   9N (lat_we): Q0 NMI ON (Moon map: Portman, Moon Quasar) / K&B speech trigger 0, Q1 NMI ON (Galaxian, K&B),
//                Q2 K&B speech trigger 1, Q3 K&B speech-DIP mux, Q4 STARS ON, Q6 HFLIP, Q7 VFLIP
//   9L (snd_we): Q0-Q2 FS1-3, Q3 HIT, Q5 FIRE, Q6 VOL1, Q7 VOL2
//   9M (drv_we): Q0-Q2 lamps / coin lockout or the gfx bank bits, Q4-Q7 the background DAC
// Data in: ROM (through gx_rom_map: per-game image remap, Moon Quasar opcode decrypt), RAM, video RAM, object RAM,
// IN0 / IN1 / IN2 (gx_inputs); anything else, the watchdog read and interrupt acknowledge included, reads FF (MAME
// unmap_value_high; the board's bus pull-ups, docs Q8).
// Memories: CPU ROM gx_dpram 32K (port A = download of image 0x0000-0x7FFF, port B = CPU); CPU RAM gx_dpram2 4K
// (port A = CPU at gx_addr_dec.ram_a; port B = the hi-score engine at {0, hs_addr}); the video memories are in
// gx_video.  The download decode does not depend on the game byte, so mod may arrive at any time before reset ends.
//
// Rotation: rot_ccw (output) is the game's flag: its cabinet turns the monitor counter-clockwise.  It is gx_flags'
// per-game-byte value unless rot_mra[1] is set, then rot_mra[0] (a .mra whose set turns the other way than its game
// byte's family; the wrapper decodes it from the index-1 option byte).  While the framework
// turns the picture (fw_rotate = 1: Rotation CW or CCW, and the wrapper asks sys-tango to swap them for a rot_ccw game)
// the board raster here is exactly the board's.  With fw_rotate = 0 (Rotation Normal: a physically turned monitor, no
// frame-buffer turn) a rot_ccw game is turned 180 degrees here with the board's own cocktail flip: turn = rot_ccw &
// ~fw_rotate, the video sees HFLIP ^ turn and VFLIP ^ turn, and gx_video corrects the flip's departures from an exact
// 180-degree turn (sprite X, the Y of objects 0-2, the shell/missile X, which HFLIP does not move); the game's own
// flip bits stay the board's.  fw_rotate must change only between frames (the wrapper takes it in the vertical
// blanking or while reset is held).
//
// Sound: gx_pitch (9J/9K/8K/6T) -> QA, QC, QD; gx_snd_bg (9M DAC, FS1-3); gx_snd_hit (HIT, NOISE); gx_snd_fire (FIRE,
// NOISE); K&B speech; all into gx_snd_mix (board: Galaxian, Moon Cresta Gremlin, K&B or Nichibutsu MC-1, from
// mix_moon / kb / mix_mc1).  mix_mc1 also sets the MC-1 values in gx_snd_bg (C17-C19 0.1 uF) and gx_snd_hit (FLASH:
// the gated C21 as v_flash, no band-pass), and gx_snd_mix then takes v_flash behind R35 in place of v_hit.  audio: signed 16-bit Q3.13 volts at 48 kHz (gx_snd_mix header), AC-coupled by the
// board's output coupling (K&B: half the node voltage); the wrapper adds its DC blocker and the Audio Boost.
// Video: r / g / b, ce_pix, hblank, vblank from gx_video (all four describe the same output pixel); hsync / vsync from
// gx_hv (active high).
//
// cpu_hold (hi-score engine, OSD pause) holds the CPU in WAIT and stops the watchdog.
// wd_reset: the 6T watchdog's half of the game reset (game_reset & ~reset = wd[3] while reset is low), for the
// hi-score engine, which re-arms its restore on every game reset as a machine reset does.
`default_nettype none
module gx_top (
    input  wire        clk,
    input  wire        reset,          // system reset, held during the download
    input  wire [7:0]  mod,            // game byte (.mra index 1)
    input  wire [15:0] dn_addr,        // index-0 image download
    input  wire [7:0]  dn_data,
    input  wire        dn_wr,
    input  wire        p1_up,
    input  wire        p1_down,
    input  wire        p1_left,
    input  wire        p1_right,
    input  wire        p1_fire,
    input  wire        p2_up,
    input  wire        p2_down,
    input  wire        p2_left,
    input  wire        p2_right,
    input  wire        p2_fire,
    input  wire        start1,
    input  wire        start2,
    input  wire        coin,
    input  wire        test,
    input  wire [23:0] dsw,            // {sw2 (DIP port IN2), sw1 (IN1 mask), sw0 (IN0 mask)}
    input  wire        kb_speech_sw,
    input  wire        cpu_hold,
    input  wire        fw_rotate,      // the framework turns the picture: no rot_ccw turn here (header, Rotation)
    input  wire [1:0]  rot_mra,        // {valid, ccw}: the .mra's own direction in place of the game byte's (00: none)
    input  wire [10:0] hs_addr,
    input  wire [7:0]  hs_d,
    input  wire        hs_we,
    output wire [7:0]  hs_q,
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b,
    output wire        ce_pix,
    output wire        hblank,
    output wire        vblank,
    output wire        hsync,
    output wire        vsync,
    output wire signed [15:0] audio,
    output wire        rot_ccw,
    output wire        wd_reset        // the watchdog's game reset (6T Q3), not the system reset
);
    // ---- per-game flags
    wire       map_moon, nmi_q0, irq_int, rom_4fff, ram_2k, ram_vic, mq_dec, stars_disp, mix_moon, bullet_az, kb;
    wire       mix_mc1;
    wire       pisces, porter;
    wire [1:0] rom_mode;
    wire [2:0] gfx_mode;
    wire [3:0] layout;
    wire       rot_ccw_mod;                          // gx_flags: the game byte's direction
    gx_flags u_flags (
        .mod(mod), .map_moon(map_moon), .nmi_q0(nmi_q0), .irq_int(irq_int), .rom_mode(rom_mode), .rom_4fff(rom_4fff),
        .ram_2k(ram_2k), .ram_vic(ram_vic), .mq_dec(mq_dec), .gfx_mode(gfx_mode), .stars_disp(stars_disp),
        .mix_moon(mix_moon), .mix_mc1(mix_mc1), .bullet_az(bullet_az), .kb(kb), .layout(layout), .pisces(pisces),
        .porter(porter), .rot_ccw(rot_ccw_mod)
    );
    assign rot_ccw = rot_mra[1] ? rot_mra[0] : rot_ccw_mod;

    // ---- clock enables
    wire ce_12m, ce_pr, ce_3m_unused, ce_1m5;
    gx_ce u_ce (.clk(clk), .reset(reset), .ce_12m(ce_12m), .ce_6m(ce_pr), .ce_3m(ce_3m_unused), .ce_1m5(ce_1m5));
    wire ce_pf = ce_12m & ~ce_pr;

    reg [8:0] c48;
    always @(posedge clk)
        if (reset) c48 <= 9'd0;
        else       c48 <= c48 + 9'd1;
    wire ce_48k = &c48;

    wire ce_2m5;
    gx_ce_frac u_ce_sp (.clk(clk), .reset(reset), .ce(ce_2m5));

    wire [8:0] h;
    wire       ce_cpu  = ce_pr & ~h[0];
    wire       ce_wait = ce_pr &  h[0];

    // ---- main CPU
    wire [15:0] a;
    wire [7:0]  cpu_do;
    reg  [7:0]  cpu_di;
    wire        m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n, busak_n;
    wire        wait_n, nmi_n, int_n, game_reset, wen;
    reg         game_reset_q, reset_q;
    always @(posedge clk) begin
        game_reset_q <= game_reset;
        reset_q      <= reset;
    end
    T80se_t2w u_cpu (
        .RESET_n(~game_reset_q), .CLK_n(clk), .CLKEN(ce_cpu), .WAIT_n(wait_n), .INT_n(int_n), .NMI_n(nmi_n),
        .BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(rfsh_n),
        .HALT_n(halt_n), .BUSAK_n(busak_n), .A(a), .DI(cpu_di), .DO(cpu_do)
    );

    wire        rom_rd, ram_rd, ram_wr, vram_req, vram_rd, vram_wr, obj_rd, obj_wr, in0_oe, in1_oe, dip_oe, wdr;
    wire        drv_we, snd_we, lat_we, pitch_we;
    wire [11:0] ram_a;
    gx_addr_dec u_dec (
        .a(a), .mreq_n(mreq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(rfsh_n), .map_moon(map_moon), .rom_4fff(rom_4fff),
        .ram_2k(ram_2k), .ram_vic(ram_vic), .rom_rd(rom_rd), .ram_rd(ram_rd), .ram_wr(ram_wr), .ram_a(ram_a),
        .vram_req(vram_req), .vram_rd(vram_rd), .vram_wr(vram_wr), .obj_rd(obj_rd), .obj_wr(obj_wr), .in0_oe(in0_oe),
        .in1_oe(in1_oe), .dip_oe(dip_oe), .wdr(wdr), .drv_we(drv_we), .snd_we(snd_we), .lat_we(lat_we),
        .pitch_we(pitch_we)
    );

    // ---- latches 9N, 9L, 9M
    wire [7:0] q9n, q9l, q9m;
    gx_latch_259 u_9n (.clk(clk), .clr(game_reset_q), .we(lat_we & wen), .a(a[2:0]), .d(cpu_do[0]), .q(q9n));
    gx_latch_259 u_9l (.clk(clk), .clr(game_reset_q), .we(snd_we & wen), .a(a[2:0]), .d(cpu_do[0]), .q(q9l));
    gx_latch_259 u_9m (.clk(clk), .clr(game_reset_q), .we(drv_we & wen), .a(a[2:0]), .d(cpu_do[0]), .q(q9m));

    // ---- video
    wire       turn = rot_ccw & ~fw_rotate;     // the 180-degree turn (header, Rotation)
    wire [7:0] v;
    wire       vsync_i, vblank_i, hblank_ff, v_inc, vblank_rise, noise;
    wire [7:0] vram_cq, obj_cq;
    gx_video u_video (
        .clk(clk), .reset(reset), .ce_12m(ce_12m), .ce_pr(ce_pr), .ce_pf(ce_pf),
        .gfx_mode(gfx_mode), .porter(porter), .stars_disp(stars_disp), .bullet_az(bullet_az),
        .rot_ccw(turn),
        .hflip(q9n[6] ^ turn), .vflip(q9n[7] ^ turn), .stars_on(q9n[4]), .bank9m(q9m[2:0]),
        .cpu_a(a[9:0]), .cpu_do(cpu_do), .vram_we(vram_wr & wen), .obj_we(obj_wr & wen), .vram_cq(vram_cq),
        .obj_cq(obj_cq), .dn_addr(dn_addr), .dn_data(dn_data), .dn_wr(dn_wr),
        .h(h), .v(v), .hsync(hsync), .vsync(vsync_i), .vblank(vblank_i), .hblank_ff(hblank_ff), .v_inc(v_inc),
        .vblank_rise(vblank_rise), .noise(noise), .r(r), .g(g), .b(b), .ce_pix(ce_pix), .hblank_o(hblank),
        .vblank_o(vblank)
    );
    assign vsync = vsync_i;

    // ---- WAIT, WEN, NMI / INT, watchdog
    gx_wait_nmi u_wn (
        .clk(clk), .reset(reset), .ce_wait(ce_wait), .vram_req(vram_req), .hblank_ff(hblank_ff), .vblank(vblank_i),
        .vblank_rise(vblank_rise), .nmi_on(nmi_q0 ? q9n[0] : q9n[1]), .irq_int(irq_int), .wdr(wdr),
        .cpu_hold(cpu_hold), .wd_off(1'b0), .wait_n(wait_n), .wen(wen), .nmi_n(nmi_n), .int_n(int_n),
        .game_reset(game_reset)
    );
    assign wd_reset = game_reset & ~reset;

    // ---- CPU ROM (32K): port A = download, port B = CPU
    wire [14:0] rom_a;
    wire [7:0]  rom_q, rom_d, rom_qa_unused;
    gx_dpram #(.AW(15), .DW(8)) u_rom (
        .clk(clk), .we_a(dn_wr & ~dn_addr[15]), .addr_a(dn_addr[14:0]), .d_a(dn_data), .q_a(rom_qa_unused),
        .addr_b(rom_a), .q_b(rom_q)
    );
    gx_rom_map u_rmap (
        .a(a), .m1_n(m1_n), .rom_mode(rom_mode), .mq_dec(mq_dec), .rom_q(rom_q), .rom_a(rom_a), .rom_d(rom_d)
    );

    // ---- CPU RAM (4K): port A = CPU, port B = hi-score
    wire [7:0] ram_q;
    gx_dpram2 #(.AW(12), .DW(8)) u_ram (
        .clk(clk), .we_a(ram_wr & wen), .addr_a(ram_a), .d_a(cpu_do), .q_a(ram_q),
        .we_b(hs_we), .addr_b({1'b0, hs_addr}), .d_b(hs_d), .q_b(hs_q)
    );

    // ---- inputs
    // gx_inputs' noise is the level the CPU reads on K&B's IN1 bit 5: NOISE (2D) passes the 74368 inverting input
    // buffer (9F pin 6 -> 7, KB p14) like the switch inputs, so the CPU reads NOT NOISE.  The sound leaves take NOISE.
    wire [7:0] in0, in1, in2;
    gx_inputs u_in (
        .layout(layout), .pisces(pisces), .p1_up(p1_up), .p1_down(p1_down), .p1_left(p1_left), .p1_right(p1_right),
        .p1_fire(p1_fire), .p2_up(p2_up), .p2_down(p2_down), .p2_left(p2_left), .p2_right(p2_right),
        .p2_fire(p2_fire), .start1(start1), .start2(start2), .coin(coin), .test(test), .dsw(dsw), .kb(kb),
        .kb_mux(q9n[3]), .kb_speech_sw(kb_speech_sw), .noise(~noise), .in0(in0), .in1(in1), .in2(in2)
    );

    // ---- CPU data in (one-hot selects; unmapped reads FF)
    always @* begin
        if (rom_rd)      cpu_di = rom_d;
        else if (ram_rd) cpu_di = ram_q;
        else if (vram_rd) cpu_di = vram_cq;
        else if (obj_rd) cpu_di = obj_cq;
        else if (in0_oe) cpu_di = in0;
        else if (in1_oe) cpu_di = in1;
        else if (dip_oe) cpu_di = in2;
        else             cpu_di = 8'hFF;
    end

    // ---- sound
    wire qa, qc, qd;
    gx_pitch u_pitch (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .h(h[1:0]), .pitch_we(pitch_we & wen), .d(cpu_do),
        .qa(qa), .qc(qc), .qd(qd)
    );
    wire [15:0] bg, v_fire;
    wire signed [15:0] v_hit, v_flash, speech;
    gx_snd_bg u_bg (
        .clk(clk), .reset(reset), .ce_1m5(ce_1m5), .ce_48k(ce_48k), .dac(q9m[7:4]), .fs(q9l[2:0]), .mc1(mix_mc1),
        .bg(bg)
    );
    gx_snd_hit u_hit (
        .clk(clk), .reset(reset), .ce_48k(ce_48k), .hit(q9l[3]), .noise(noise), .mc1(mix_mc1), .v_hit(v_hit),
        .v_flash(v_flash)
    );
    gx_snd_fire u_fire (
        .clk(clk), .reset(reset), .ce_1m5(ce_1m5), .ce_48k(ce_48k), .fire(q9l[5]), .noise(noise), .v_fire(v_fire)
    );
    gx_kb_speech u_speech (
        .clk(clk), .reset(reset_q), .ce_2m5(ce_2m5), .ce_48k(ce_48k), .dn_addr(dn_addr), .dn_data(dn_data),
        .dn_wr(dn_wr), .trig({q9n[2], q9n[0]}), .speech(speech)
    );
    gx_snd_mix u_mix (
        .clk(clk), .reset(reset), .ce_1m5(ce_1m5), .ce_48k(ce_48k), .mix_moon(mix_moon), .kb(kb), .mc1(mix_mc1),
        .vol1(q9l[6]), .vol2(q9l[7]), .qa(qa), .qc(qc), .qd(qd), .bg(bg), .v_hit(v_hit), .v_flash(v_flash),
        .v_fire(v_fire), .speech(speech), .audio(audio)
    );

    wire unused_ok = &{1'b0, ce_3m_unused, iorq_n, halt_n, busak_n, rom_qa_unused, v, v_inc, h[8:2], q9l[4], q9n[5],
                       q9m[3]};
endmodule
`default_nettype wire
