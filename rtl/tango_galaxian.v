// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// tango_galaxian.v -- the Tango core wrapper (module tango_core) around gx_top, the Galaxian-family game logic.
// Parts are reused from scramble-tango and galaga-tango; the wrapper's own leaf modules are gx_dl_ctrl, gx_hs_seq and
// gx_pad_map (rtl/tango/).
//
// Every wire that crosses sections is declared once, at the top; each "// SECTION n" block drives only the wires its
// comment lists under "Drives".  A block that holds only its comment leaves those outputs undriven.
//
// Build options (build/build_galaxian.sh): TANGO_VIDEO_ASCAL TANGO_VIDEO_DDR3 TANGO_VIDEO_OPTS TANGO_VIDEO_PROC
// TANGO_VIDEO_ASCAL_MAXW=256 TANGO_IOCTL_UPLOAD TANGO_VIDEO_ROTATE TANGO_VIDEO_ROTATE_CCW; dev builds add GX_DBG_OV
// (DBGOV=1), release builds never do.
//
// Status bits: [0] Reset, [2:1] Audio Boost, [3] Debug overlay (GX_DBG_OV builds only); [127:118] the framework's, of
// which section 8 reads Rotation [119:118] (whether the framework turns the picture).
`default_nettype none
module tango_core (
    `include "tango_core_ports.vh"
);
    // ---- wires that cross sections ------------------------------------------------------------------------------
    wire        clk_sys;            // S1 -> all
    wire        pll_locked;         // S1
    wire        por;                // S1 -> S3, S4: ~pll_locked through two clk_sys flops
    wire        sys_reset;          // S1 -> S4: RESET through two clk_sys flops, OR status[0]

    wire [15:0] dn_addr;            // S3 -> S7
    wire [7:0]  dn_data;            // S3 -> S7
    wire        dn_wr;              // S3 -> S7
    wire [7:0]  mod;                // S3 -> S7, S10
    wire [1:0]  mod_src;            // S3 -> S10
    wire [23:0] dsw;                // S3 -> S7, S10
    wire        dsw_seen;           // S3 -> S10
    wire        kb_speech_sw;       // S3 -> S7 (King and Balloon speech switch: DIP byte 3 bit 0, default On)

    wire        game_reset;         // S4 -> S5 (hiscore.v reset), S7 (gx_top reset): the same reset for both
    wire [1:0]  seq_state;          // S4 -> S10

    wire [10:0] hs_addr;            // S5 -> S7
    wire [7:0]  hs_d;               // S5 -> S7
    wire        hs_we;              // S5 -> S7
    wire [7:0]  hs_q;               // S7 -> S5
    wire        hs_pause;           // S5: hiscore.v pause_cpu (looped back to its own paused input)
    wire        hs_configured;      // S5 -> S10
    wire        cpu_hold;           // S5 -> S7: = hs_pause

    wire        p1_up, p1_down, p1_left, p1_right, p1_fire;     // S6 -> S7
    wire        p2_up, p2_down, p2_left, p2_right, p2_fire;     // S6 -> S7
    wire        start1, start2, coin, test;                     // S6 -> S7

    wire [7:0]  gx_r, gx_g, gx_b;   // S7 -> S8
    wire        gx_ce_pix;          // S7 -> S8, S10
    wire        gx_hblank;          // S7 -> S8, S10
    wire        gx_vblank;          // S7 -> S8, S10
    wire        gx_hsync;           // S7 -> S8
    wire        gx_vsync;           // S7 -> S8, S10
    wire signed [15:0] gx_audio;    // S7 -> S9
    wire        rot_ccw;            // S7 -> S8, S10
    wire        fw_rotate;          // S8 -> S7
    wire [1:0]  rot_mra;            // S8 -> S7: {valid, ccw}, the .mra's index-1 option byte

    wire        ov_on;              // S10 -> S8: 0 in builds without GX_DBG_OV
    wire [23:0] ov_rgb;             // S10 -> S8

    // SECTION 1: clocks and resets
    //
    // Drives: CLK_SYS, clk_sys, pll_locked, por, sys_reset.  Reads: CLK_50M, RESET, status[0].
    galaxian_clocks u_clocks (.clk50(CLK_50M), .clk_sys(clk_sys), .locked(pll_locked));
    assign CLK_SYS = clk_sys;
    // RESET (the pixel PLL not locked) is asynchronous to clk_sys, and so is pll_locked (PLL_INIT's O_LOCK): each goes
    // through two clk_sys flops.  Both chains start at 1, so the core is in reset from configuration until each has
    // been seen released for two clocks.  status[0] (the OSD's Reset) is a clk_sys register (sys/tango_io.v).
    reg  [1:0] rst_s = 2'b11;
    reg  [1:0] por_s = 2'b11;
    always @(posedge clk_sys) begin
        rst_s <= {rst_s[0], RESET};
        por_s <= {por_s[0], ~pll_locked};
    end
    assign por       = por_s[1];
    assign sys_reset = rst_s[1] | status[0];

    // SECTION 2: menu
    //
    // Drives: conf_char, status_menumask.  Reads: conf_addr.
    // J1: pad bits 4-8 (gx_pad_map).  Bits 10 and 11 stay unnamed: the firmware opens the in-core menu on them
    // (Start + Select).
    localparam CONF_STR = {
        "Galaxian;;",
        "-;",
        `TANGO_VIDEO_CONF,
        "O[2:1],Audio Boost,+15 dB,4x,2x,No;",
`ifdef GX_DBG_OV
        "O[3],Debug overlay,On,Off;",
`endif
        "-;",
        "T[0],Reset;",
        "R[0],Reset and close OSD;",
        "-;",
        "DIP;",
        "-;",
        "J1,Fire,Start 1P,Start 2P,Coin,Service;",
        "V,",`BUILD_DATE
    };
    tango_conf_rom #(.CONF_STR(CONF_STR)) u_conf (.clk(CLK_PIX), .addr(conf_addr), .q(conf_char));
    assign status_menumask = 16'd0;

    // SECTION 3: downloads
    // The download decode (rtl/tango/gx_dl_ctrl.v).
    // Drives: dn_addr, dn_data, dn_wr, mod, mod_src, dsw, dsw_seen, kb_speech_sw, ioctl_wait.
    // Reads: clk_sys, por, ioctl_download, ioctl_index[7:0], ioctl_wr, ioctl_addr, ioctl_dout.
    gx_dl_ctrl u_dl (.clk(clk_sys), .por(por), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index[7:0]),
        .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout), .dn_addr(dn_addr),
        .dn_data(dn_data), .dn_wr(dn_wr), .mod(mod), .mod_src(mod_src), .dsw(dsw), .dsw_seen(dsw_seen),
        .kb_speech_sw(kb_speech_sw));
    assign ioctl_wait = 1'b0;   // (every byte is taken in one clk_sys clock)

    // SECTION 4: reset sequencer
    // The reset sequencer (rtl/tango/gx_hs_seq.v).
    // Drives: game_reset, seq_state.  Reads: clk_sys, por, sys_reset, ioctl_download, ioctl_index[7:0].
    gx_hs_seq u_seq (.clk(clk_sys), .por(por), .sys_reset(sys_reset), .ioctl_download(ioctl_download), .ioctl_index(ioctl_index[7:0]), .reset_out(game_reset), .seq_state(seq_state));

    // SECTION 5: hi-score
    //
    // Drives: hs_addr, hs_d, hs_we, hs_pause, hs_configured, cpu_hold, ioctl_din, ioctl_upload_req (= 0),
    //         ioctl_upload_index (= 0).
    // Reads: clk_sys, game_reset, ioctl_upload, ioctl_download, ioctl_wr, ioctl_addr[24:0], ioctl_index[7:0],
    //        ioctl_dout, OSD_STATUS, hs_q.
    // hiscore.v (vendored, with the T1-T3 changes in its header): the .mra's hi-score table arrives at index 3, the
    // saved dump at index 4 and is written into the game RAM after a reset falling edge (game_reset, the same reset as
    // gx_top's); an upload of index 4 reads back the table an OSD-open extraction captured.  Its own pause request is
    // the only CPU hold (gx_top cpu_hold), and it is looped back as the "paused" acknowledge.  The RAM index is
    // {0, hs_addr}: 11 bits.  The .mra tables use 2-byte lengths.
    // The firmware saves on its own schedule: no save request from the core (ioctl_upload_req = 0, autosave = 0).
`ifndef TANGO_IOCTL_UPLOAD
    GX_needs_TANGO_IOCTL_UPLOAD u_error ();      // hiscore.v's dump upload needs the upload ports: build option
`endif
    hiscore #(
        .HS_ADDRESSWIDTH(11),
        .CFG_LENGTHWIDTH(2)
    ) u_hiscore (
        .clk(clk_sys),
        .paused(hs_pause),
        .reset(game_reset),
        .autosave(1'b0),
        .ioctl_upload(ioctl_upload),
        .ioctl_upload_req(),
        .ioctl_download(ioctl_download),
        .ioctl_wr(ioctl_wr),
        .ioctl_addr(ioctl_addr[24:0]),
        .ioctl_index(ioctl_index[7:0]),
        .OSD_STATUS(OSD_STATUS),
        .data_from_hps(ioctl_dout),
        .data_from_ram(hs_q),
        .ram_address(hs_addr),
        .data_to_hps(ioctl_din),
        .data_to_ram(hs_d),
        .ram_write(hs_we),
        .ram_intent_read(),
        .ram_intent_write(),
        .pause_cpu(hs_pause),
        .configured(hs_configured)
    );
    assign cpu_hold           = hs_pause;
    assign ioctl_upload_req   = 1'b0;
    assign ioctl_upload_index = 8'd0;

    // SECTION 6: pads
    // The pad map (rtl/tango/gx_pad_map.v).
    // Drives: p1_up, p1_down, p1_left, p1_right, p1_fire, p2_up, p2_down, p2_left, p2_right, p2_fire, start1, start2,
    //         coin, test.  Reads: clk_sys, joystick_0, joystick_1.
    // gx_pad_map u_pads (.clk(clk_sys), .joystick_0(joystick_0), .joystick_1(joystick_1), and each output port to
    //     the wire of the same name).
    gx_pad_map u_pads (
        .clk(clk_sys), .joystick_0(joystick_0), .joystick_1(joystick_1),
        .p1_up(p1_up), .p1_down(p1_down), .p1_left(p1_left), .p1_right(p1_right), .p1_fire(p1_fire),
        .p2_up(p2_up), .p2_down(p2_down), .p2_left(p2_left), .p2_right(p2_right), .p2_fire(p2_fire),
        .start1(start1), .start2(start2), .coin(coin), .test(test)
    );

    // SECTION 7: the game
    // gx_top ports: rtl/gx/gx_top.v.
    // Drives: gx_r, gx_g, gx_b, gx_ce_pix, gx_hblank, gx_vblank, gx_hsync, gx_vsync, gx_audio, rot_ccw, hs_q.
    // Reads: clk_sys, game_reset, mod, dn_addr, dn_data, dn_wr, the 14 pad wires, dsw, kb_speech_sw, cpu_hold, fw_rotate,
    //        rot_mra, hs_addr, hs_d, hs_we.
    gx_top u_game (
        .clk(clk_sys), .reset(game_reset), .mod(mod),
        .dn_addr(dn_addr), .dn_data(dn_data), .dn_wr(dn_wr),
        .p1_up(p1_up), .p1_down(p1_down), .p1_left(p1_left), .p1_right(p1_right), .p1_fire(p1_fire),
        .p2_up(p2_up), .p2_down(p2_down), .p2_left(p2_left), .p2_right(p2_right), .p2_fire(p2_fire),
        .start1(start1), .start2(start2), .coin(coin), .test(test),
        .dsw(dsw), .kb_speech_sw(kb_speech_sw), .cpu_hold(cpu_hold), .fw_rotate(fw_rotate), .rot_mra(rot_mra),
        .hs_addr(hs_addr), .hs_d(hs_d), .hs_we(hs_we), .hs_q(hs_q),
        .r(gx_r), .g(gx_g), .b(gx_b),
        .ce_pix(gx_ce_pix), .hblank(gx_hblank), .vblank(gx_vblank), .hsync(gx_hsync), .vsync(gx_vsync),
        .audio(gx_audio), .rot_ccw(rot_ccw)
    );
    // kb_speech_sw is gx_dl_ctrl's output: King and Balloon's speech switch (IN0 bit 6 through the 9N Q3 mux), DIP
    // byte 3 bit 0 of index 254, On (1) until a 254 download has written byte 3.

    // SECTION 8: video outputs
    //
    // Drives: CLK_VIDEO, CE_PIXEL, VGA_R/G/B, VGA_HS, VGA_VS, VGA_DE, VGA_SL, VIDEO_SCALE, VIDEO_CROP_SIZE,
    //         VIDEO_CROP_OFF, HDMI_FREEZE, VIDEO_ARX, VIDEO_ARY, VIDEO_ROTATE_CCW, fw_rotate, rot_mra.
    // Reads: the gx_* video wires, ov_on, ov_rgb, rot_ccw, clk_sys, por, game_reset, status[119:118], mod_src,
    //        ioctl_download, ioctl_index[7:0], ioctl_wr, ioctl_addr, ioctl_dout.
    // gx_top's 8-bit RGB (its colour DAC levels) with positive syncs.  CE_PIXEL is gx_top's 6.144 MHz pixel enable,
    // which pulses through the blanking (the framework's CE_PIXEL rule) and stops while the game is in reset (gx_ce
    // holds its divider).  Native picture 256 x 224, aspect 8:7 unrotated; rotation is the framework's
    // (TANGO_VIDEO_ROTATE), and every game is portrait, so the core has no VIDEO_NO_ROTATE.
    assign CLK_VIDEO = clk_sys;
    assign CE_PIXEL  = gx_ce_pix;
    assign VGA_R     = ov_on ? ov_rgb[23:16] : gx_r;
    assign VGA_G     = ov_on ? ov_rgb[15:8]  : gx_g;
    assign VGA_B     = ov_on ? ov_rgb[7:0]   : gx_b;
    assign VGA_HS    = gx_hsync;
    assign VGA_VS    = gx_vsync;
    assign VGA_DE    = ~(gx_hblank | gx_vblank);
    assign VGA_SL          = 2'd0;               // TANGO_VIDEO_OPTS owns Scanlines
    assign VIDEO_SCALE     = 3'd0;               // TANGO_VIDEO_OPTS owns Scale
    assign VIDEO_CROP_SIZE = 12'd0;
    assign VIDEO_CROP_OFF  = 5'd0;
    assign HDMI_FREEZE     = 1'b0;
    assign VIDEO_ARX       = 13'd8;              // a ratio (bit 12 clear): 8:7, the unrotated native shape
    assign VIDEO_ARY       = 13'd7;
    // Rotation (rtl/gx/gx_top.v): the games whose cabinets turn the monitor counter-clockwise (rot_ccw,
    // gx_top's flag: the game byte's, or the .mra's option byte below) ask the framework to swap its CW and CCW (VIDEO_ROTATE_CCW, a clk_sys flop:
    // it crosses into the video clock in sys-tango), so one Rotation setting shows every game upright, turned after
    // the board as a whole frame.  fw_rotate = the framework turns the picture: Rotation CW (01) or CCW (10), the
    // rotation client's own decode (00 Normal and 11 show the raster unturned).  Only then is gx_top's own 180-degree
    // turn of a rot_ccw game off; with Normal (a physically turned monitor) gx_top turns it.  fw_rotate is taken while
    // the game is in reset and at the start of each vertical blanking, so that turn never changes inside a frame.
    // status is a clk_sys register (sys/tango_io.v).
`ifndef TANGO_VIDEO_ROTATE_CCW
    GX_needs_TANGO_VIDEO_ROTATE_CCW u_error_rot ();  // VIDEO_ROTATE_CCW: build option (and TANGO_VIDEO_ROTATE)
`endif
    reg         rot_ccw_q = 1'b0;
    reg         fw_rot_q  = 1'b0;
    reg         vbl_q     = 1'b0;
    always @(posedge clk_sys) begin
        rot_ccw_q <= rot_ccw;
        vbl_q     <= gx_vblank;
        if (game_reset || (gx_vblank && !vbl_q))
            fw_rot_q <= ^status[119:118];   // check_confstr: status[119:118] the framework's Rotation (TANGO_VO_B_ROTATE)
    end
    assign VIDEO_ROTATE_CCW = rot_ccw_q;
    assign fw_rotate        = fw_rot_q;
    // The .mra's direction (rtl/gx/gx_flags.v): a two-byte index 1 is {option byte, game byte}.  The option
    // byte is 1000000c (bit 7 set: never a game byte; c = the set's cabinet turns the monitor counter-clockwise); the
    // game byte comes last, so gx_dl_ctrl's mod ends on it (every index-1 byte writes mod, gx_dl_ctrl).  Each
    // index-1 byte at address 0 replaces the option: a one-byte index 1 clears it.  It applies while mod is from
    // index 1 (mod_src 1), so a launch without index 1, or a game byte from the image, drops it at the index-0 start.
    reg  [1:0]  opt_rot = 2'b00;
    always @(posedge clk_sys)
        if (por)
            opt_rot <= 2'b00;
        else if (ioctl_download && ioctl_index[7:0] == 8'd1 && ioctl_wr && ioctl_addr == 27'd0)
            opt_rot <= {ioctl_dout[7], ioctl_dout[0]};
    assign rot_mra = {opt_rot[1] & (mod_src == 2'd1), opt_rot[0]};

    // SECTION 9: audio
    //
    // Drives: AUDIO_L, AUDIO_R, AUDIO_MIX (= 0, under TANGO_CORE_AUDIO_MIX).  Reads: clk_sys, CLK_PIX, gx_audio,
    //         status[2:1].
    // gx_audio: signed 16-bit, Q3.13 volts, a new sample at 48 kHz.  Its DC is removed at 48 kHz (MiSTer's
    // DC_blocker, sys/iir_filter.v: y = x - x' + y' - y'/512), it is doubled to MiSTer's level and saturated, goes
    // through the Audio Boost option (rtl/tango/tg16_aboost.v: +15 dB, 4x, 2x, No; default +15 dB) and is crossed
    // to CLK_PIX, the same sample on both channels.
    // 48 kHz sample enable: 24.576 MHz / 512
    reg  [8:0]  aud_div = 9'd0;
    reg         aud_ce = 1'b0;
    always @(posedge clk_sys) begin
        aud_div <= aud_div + 9'd1;
        aud_ce  <= (aud_div == 9'd0);
    end
    // DC blocker on x = gx_audio sign-extended: y = x - x' + y' - y' >>> 9, with y kept to 16 fraction bits so the
    // decay reaches 0.  y is x minus a low-passed copy of x, so |y| <= 2^16 (18 integer bits + 16 fraction bits).
    wire signed [17:0] dc_x = {{2{gx_audio[15]}}, gx_audio};
    reg  signed [17:0] dc_xp = 18'sd0;
    reg  signed [33:0] dc_acc = 34'sd0;
    wire signed [17:0] dc_y = dc_acc[33:16];
    always @(posedge clk_sys)
        if (aud_ce) begin
            dc_xp  <= dc_x;
            dc_acc <= dc_acc + $signed({(dc_x - dc_xp), 16'd0}) - (dc_acc >>> 9);   // all signed: >>> sign-extends
        end
    // doubled to MiSTer's level, saturated to +-32743: tg16_aboost's 4x and 2x curves turn the sign over for
    // |x| >= 32744 and >= 32764
    wire signed [18:0] dc_2 = {dc_y, 1'b0};
    wire        [15:0] aud_lvl = (dc_2 >  19'sd32743) ? 16'd32743 :
                                 (dc_2 < -19'sd32743) ? 16'h8019 : dc_2[15:0];     // 8019 = -32743
    wire [15:0] aud_boost;
    tg16_aboost u_boost (.clk(clk_sys), .sel(status[2:1]), .x(aud_lvl), .y(aud_boost));

    reg  [31:0] aud_sys = 32'd0;
    always @(posedge clk_sys) aud_sys <= {aud_boost, aud_boost};
    wire [31:0] aud_pix;
    tango_cdc_word #(.W(32)) u_aud (.clk_a(clk_sys), .din(aud_sys), .clk_b(CLK_PIX), .dout(aud_pix));
    assign AUDIO_L = aud_pix[31:16];
    assign AUDIO_R = aud_pix[15:0];
`ifdef TANGO_CORE_AUDIO_MIX
    assign AUDIO_MIX = 2'd0;
`endif

    // SECTION 10: debug overlay
    //
    // Drives: ov_on, ov_rgb.  Reads: the debug bus (below), gx_ce_pix, gx_hblank, gx_vblank, gx_vsync, status[3].
    // GX_DBG_OV (dev builds, build/build_galaxian.sh DBGOV=1; never in a release build): large hex text over the
    // picture (rtl/tango/gx_dbg_ov.v, generated by tools/gen_gx_dbg_ov.py, which lists the bus map and the rows).
    // Every value is a clk_sys register of this core; the overlay feeds nothing back into the game.
`ifdef GX_DBG_OV
    // CRC-32 (zlib/IEEE) and byte count of every byte of the last index-0 download, reset at its start
    function [31:0] crc32_byte(input [31:0] c, input [7:0] d);
        integer i;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, d};
            for (i = 0; i < 8; i = i + 1) x = x[0] ? ((x >> 1) ^ 32'hEDB88320) : (x >> 1);
            crc32_byte = x;
        end
    endfunction
    wire        dbg_dl_rom = ioctl_download & (ioctl_index[7:0] == 8'd0);
    reg         dbg_dl_q = 1'b0;
    wire        dbg_dl_start = ioctl_download & ~dbg_dl_q;
    wire        dbg_dl_end   = ~ioctl_download & dbg_dl_q;
    reg  [7:0]  dbg_idx_q = 8'd0;                // the index of the download that is open (or last was)
    reg  [31:0] dbg_crc = 32'hFFFFFFFF;
    reg  [23:0] dbg_cnt = 24'd0;
    reg         dbg_dump = 1'b0;                 // an index-4 download ended since the last index-0 start
    // A launch download that started after gx_hs_seq released the game (index 3 or 4, or 254 with the OSD closed,
    // starting in RUN), since the last index-0 start: the firmware's gap outran QUIET.  dbg_gap_max never sees that
    // gap (it ends in RUN), so its value is valid only while this is 0.
    reg         dbg_late = 1'b0;
    reg  [15:0] dbg_ndl = 16'd0;
    // The firmware gap gx_hs_seq's QUIET must exceed: clk_sys clocks from the end of a download to the start of the
    // next one, counted while gx_hs_seq is in SETTLE (seq_state 1), the longest kept since power-on.  The quiet
    // time after the last download of a burst is never kept (no download ends it).
    reg  [31:0] dbg_gap = 32'd0;
    reg  [31:0] dbg_gap_max = 32'd0;
    always @(posedge clk_sys) begin
        dbg_dl_q <= ioctl_download;
        if (dbg_dl_start) begin
            dbg_idx_q <= ioctl_index[7:0];
            dbg_ndl   <= dbg_ndl + 16'd1;
        end
        if (dbg_dl_start && ioctl_index[7:0] == 8'd0) begin
            dbg_crc <= 32'hFFFFFFFF; dbg_cnt <= 24'd0; dbg_dump <= 1'b0; dbg_late <= 1'b0;
        end else if (dbg_dl_rom && ioctl_wr) begin
            dbg_crc <= crc32_byte(dbg_crc, ioctl_dout); dbg_cnt <= dbg_cnt + 24'd1;
        end
        if (dbg_dl_end && dbg_idx_q == 8'd4) dbg_dump <= 1'b1;
        if (dbg_dl_start && seq_state == 2'd2 &&
            (ioctl_index[7:0] == 8'd3 || ioctl_index[7:0] == 8'd4 || (ioctl_index[7:0] == 8'd254 && !OSD_STATUS)))
            dbg_late <= 1'b1;
        if (ioctl_download) begin
            if (dbg_dl_start && seq_state == 2'd1 && dbg_gap != 32'd0 && dbg_gap > dbg_gap_max) dbg_gap_max <= dbg_gap;
            dbg_gap <= 32'd0;
        end else if (seq_state == 2'd1 && dbg_gap != 32'hFFFFFFFF)
            dbg_gap <= dbg_gap + 32'd1;
    end
    reg         dbg_vs_q = 1'b0;
    reg  [15:0] dbg_fr = 16'd0;
    always @(posedge clk_sys) begin
        dbg_vs_q <= gx_vsync;
        if (gx_vsync && !dbg_vs_q) dbg_fr <= dbg_fr + 16'd1;
    end
    // the bus (tools/gen_gx_dbg_ov.py FIELDS), through one register: every bit leaves a flop with no logic behind it
    wire [175:0] ov_dbg = {dbg_gap_max, dbg_fr, dbg_ndl, dbg_idx_q, 6'd0, dbg_late, rot_ccw, dbg_dump, hs_pause, hs_configured,
                           dsw_seen, dsw, seq_state, mod_src, mod, dbg_cnt, ~dbg_crc};
    reg  [175:0] ov_dbg_q = 176'd0;
    always @(posedge clk_sys) ov_dbg_q <= ov_dbg;
    wire        ov_on_raw;
    gx_dbg_ov u_ov (.clk(clk_sys), .ce_pix(gx_ce_pix), .de(~(gx_hblank | gx_vblank)), .vs(gx_vsync), .dbg(ov_dbg_q),
                    .ov_on(ov_on_raw), .ov_rgb(ov_rgb));
    // OSD "Debug overlay" (status[3]: 0 On, 1 Off) gates only the overlay's pixels; the bus keeps running
    reg         ov_hide = 1'b0;
    always @(posedge clk_sys) ov_hide <= status[3];   // check_confstr: status[3] the Debug overlay entry (GX_DBG_OV builds)
    assign ov_on = ov_on_raw & ~ov_hide;
`else
    assign ov_on  = 1'b0;
    assign ov_rgb = 24'd0;
`endif

endmodule
`default_nettype wire
