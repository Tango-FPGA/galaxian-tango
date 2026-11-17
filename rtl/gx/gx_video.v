// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_video.v -- the Galaxian video board logic (Galaxian manual p.22 zones 05-16): timing (gx_hv), strobes
// (gx_ld_pulses), addressing (gx_vid_addr, gx_gfx_bank), shifters, the sprite line buffer (gx_linebuf_ctl + its RAM),
// priority (gx_pix_combine), shells and missiles (gx_missile), stars and NOISE (gx_stars) and the colour stage
// (gx_colour + the CLUT), with the video RAM, object RAM, graphics ROM and colour PROM as block RAMs.
// The leaves are wired as on the board.
//
// RAMs (gx_dpram: registered reads, so every video read address is combinational from h and the latches, and its
// data is valid in d1 of the pixel):
//   VRAM 1K   port A = CPU (cpu_a[9:0], vram_we), port B = gx_vid_addr.vram_va
//   OBJ  256  port A = CPU (cpu_a[7:0], obj_we),  port B = gx_vid_addr.objram_va (the HPOSI bus)
//   GFX  16K  image 0x4000-0x7FFF (index = addr - 0x4000).  Port A writes the download while reset is held, and
//             otherwise reads plane 1 ("1H", VID bit 1) at {porter ? 01 : 00, addr}; port B reads plane 0 ("1K",
//             VID bit 0) at {porter ? 10 : 01, addr} (Portman's planes sit one 4K block higher in its image).
//   CLUT 64   port A = download: image 0x6000-0x601F -> 0x00-0x1F, 0x7000-0x701F -> 0x20-0x3F; port B reads
//             {porter, clut_a}.
//   LB   256x5  port A = gx_linebuf_ctl's write (d2), port B = its read at lb_addr.
// The game logic is game-independent here except for gfx_mode, porter, stars_disp and bullet_az (gx_flags), and
// rot_ccw (gx_flags, the per-game 180-degree turn).
// hflip / vflip are the board's 9N Q6 / Q7 as the video sees them (gx_top applies the per-game rotation).
//
// rot_ccw: the picture is turned with the board's own flip (hflip / vflip already include rot_ccw), and the
// corrections below make the turned picture an exact 180-degree turn of the board picture for the game's 9N flip bits
// (rtl/gx/gx_top.v).  With rot_ccw = 0 every leaf input below is the board's own signal.
//   Sprite X: the line buffer is read at cnt (flip: ~cnt), cnt = 0 at h = 8, and the pixel read at count n shows at
//     screen x = n + 1, so under the flip sprites land 2 px off the mirror.  For rot_ccw the display count starts at
//     2: the first /LD of the display loads 2 (cntr_ld with hposi = 2) instead of clearing the counter.  The 16-pixel
//     clip and the wrap stay at the same line-buffer addresses, so they turn with the sprites.  The two edge columns
//     are swapped by hand (see the line buffer below).
//   Object Y: objects 0-2 (sprites and shells, h 0x180..0x1AF) are matched before V advances (v_inc at h = 0x1AF), so
//     against the line before the one they show on; objects 3-7 and the missile against their own line.  Under the
//     flip the stale line is the wrong neighbour by 2.  For rot_ccw, gx_vid_addr and gx_ld_pulses see V + 2 during
//     h 0x180..0x1AF (the 2M adder), and a VBLANK (the 2M clear, the 3D preset) that lets them load for v 15..237.
//   Shell / missile X: HFLIP does not move them; mirrored here (see below).
//
// Video out: r/g/b are gx_colour's output register (it changes in d0 and holds output pixel P(h) for one pixel);
// hblank_o / vblank_o describe the same pixel: pixel h's own ~c256hnx and vblank, copied at ce_pr (before 6P
// updates on that edge) and registered on the clock on which gx_colour's register updates.  ce_pix = ce_pf (d1),
// when all of them are stable.  Visible: 256 x 224 (h 8..255 and 0x180..0x187, v 16..239).
`default_nettype none
module gx_video (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_12m,
    input  wire        ce_pr,
    input  wire        ce_pf,
    // per-game flags (gx_flags)
    input  wire [2:0]  gfx_mode,
    input  wire        porter,
    input  wire        stars_disp,
    input  wire        bullet_az,
    input  wire        rot_ccw,         // the per-game 180-degree turn (corrections above)
    // board latches
    input  wire        hflip,
    input  wire        vflip,
    input  wire        stars_on,
    input  wire [2:0]  bank9m,
    // CPU side of the video and object RAMs
    input  wire [9:0]  cpu_a,
    input  wire [7:0]  cpu_do,
    input  wire        vram_we,
    input  wire        obj_we,
    output wire [7:0]  vram_cq,
    output wire [7:0]  obj_cq,
    // download (index 0 image)
    input  wire [15:0] dn_addr,
    input  wire [7:0]  dn_data,
    input  wire        dn_wr,
    // timing to the CPU side
    output wire [8:0]  h,
    output wire [7:0]  v,
    output wire        hsync,
    output wire        vsync,
    output wire        vblank,
    output wire        hblank_ff,
    output wire        v_inc,
    output wire        vblank_rise,
    output wire        noise,
    // picture
    output wire [7:0]  r,
    output wire [7:0]  g,
    output wire [7:0]  b,
    output wire        ce_pix,
    output reg         hblank_o,
    output reg         vblank_o
);
    // ---- timing and strobes
    wire cblank_n;
    gx_hv u_hv (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .h(h), .v(v), .vsync(vsync), .hsync(hsync), .vblank(vblank),
        .hblank_ff(hblank_ff), .cblank_n(cblank_n), .v_inc(v_inc), .vblank_rise(vblank_rise)
    );

    // rot_ccw, objects 0-2 (h 0x180..0x1AF): they load for line v + 1, whose turn is line 254 - v; the board matches
    // that line's objects 0-2 against 253 - v = ~(v + 2), so the turned picture needs V + 2 here (VFLIP inverts it).
    // They load only where the board does for a visible line: 17..239 (on line 16 they are still in VBLANK), so
    // v 15..237.  (The board's load on line 239 for the hidden line 240 leaves a shell 0-2 armed through VBLANK, to
    // show on line 16 of the next frame; that carry has no rot_ccw counterpart.)
    wire       pre_vinc = rot_ccw & h[8] & (h[6:4] < 3'd3);
    wire [7:0] v_obj    = pre_vinc ? v + 8'd2 : v;
    wire       vb_obj   = pre_vinc ? (v < 8'd15 || v > 8'd237) : vblank;

    wire vpl, coll, objd, mstb, ld, ld_stb, cntr_clr, cntr_ld, sld, mld, h1d, msld_n, c256hnx;
    gx_ld_pulses u_ld (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .ce_pf(ce_pf), .h(h), .vblank(vb_obj), .msld_n(msld_n),
        .c256hnx(c256hnx), .vpl(vpl), .coll(coll), .objd(objd), .mstb(mstb), .ld(ld), .ld_stb(ld_stb),
        .cntr_clr(cntr_clr), .cntr_ld(cntr_ld), .sld(sld), .mld(mld), .h1d(h1d)
    );

    // ---- addressing
    wire [7:0] hposi, vram_q, objram_va, gfx_code;
    wire [9:0] vram_va;
    wire [2:0] gfx_row, cd;
    wire       srld, col5, hflip2x, hflip1x, cblnx, hf8, vf1;
    gx_vid_addr u_va (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .h(h), .v(v_obj), .hflip(hflip), .vflip(vflip), .vblank(vb_obj),
        .cblank_n(cblank_n), .vpl(vpl), .objd(objd), .coll(coll), .ld(ld), .ld_stb(ld_stb), .hposi(hposi),
        .vram_q(vram_q), .objram_va(objram_va), .vram_va(vram_va), .msld_n(msld_n), .gfx_code(gfx_code),
        .gfx_row(gfx_row), .srld(srld), .col5(col5), .hflip2x(hflip2x), .hflip1x(hflip1x), .cblnx(cblnx),
        .c256hnx(c256hnx), .cd(cd), .hf8(hf8), .vf1(vf1)
    );

    wire [11:0] gaddr;
    gx_gfx_bank u_gb (
        .gfx_mode(gfx_mode), .code(gfx_code), .row(gfx_row), .h8(h[8]), .bank9m(bank9m), .col5(col5), .addr(gaddr)
    );

    // ---- RAMs
    gx_dpram #(.AW(10), .DW(8)) u_vram (
        .clk(clk), .we_a(vram_we), .addr_a(cpu_a), .d_a(cpu_do), .q_a(vram_cq), .addr_b(vram_va), .q_b(vram_q)
    );
    gx_dpram #(.AW(8), .DW(8)) u_obj (
        .clk(clk), .we_a(obj_we), .addr_a(cpu_a[7:0]), .d_a(cpu_do), .q_a(obj_cq), .addr_b(objram_va), .q_b(hposi)
    );

    wire [15:0] dn_gfx = dn_addr - 16'h4000;
    wire        gfx_dn = reset & dn_wr & (dn_addr[15:14] == 2'b01);
    wire [13:0] gfx_a  = reset ? dn_gfx[13:0] : {1'b0, porter, gaddr};
    wire [13:0] gfx_b  = {porter, ~porter, gaddr};
    wire [7:0]  gq_hi, gq_lo;
    gx_dpram #(.AW(14), .DW(8)) u_gfx (
        .clk(clk), .we_a(gfx_dn), .addr_a(gfx_a), .d_a(dn_data), .q_a(gq_hi), .addr_b(gfx_b), .q_b(gq_lo)
    );

    wire [4:0] clut_a;
    wire [7:0] clut_q, clut_qa_unused;
    wire       clut_dn = dn_wr & (dn_addr[15:12] == 4'h6 || dn_addr[15:12] == 4'h7) & (dn_addr[11:5] == 7'd0);
    gx_dpram #(.AW(6), .DW(8)) u_clut (
        .clk(clk), .we_a(clut_dn), .addr_a({dn_addr[12], dn_addr[4:0]}), .d_a(dn_data), .q_a(clut_qa_unused),
        .addr_b({porter, clut_a}), .q_b(clut_q)
    );

    // ---- shifters, line buffer, priority
    wire [1:0] raw;
    gx_shifter u_sh (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .srld(srld), .flip(hflip2x), .d_hi(gq_hi), .d_lo(gq_lo), .raw(raw)
    );

    wire [1:0] cmb_vid, rv;
    wire [2:0] cmb_col, rc;
    wire [7:0] lb_addr;
    wire       lb_we;
    wire [4:0] lb_d, lb_q, lb_qa;
    // rot_ccw: the display count starts at 2 (cntr_clr becomes a load of 2; cntr_ld and cntr_clr never coincide)
    wire       lb_clr = cntr_clr & ~rot_ccw;
    wire       lb_ld  = cntr_ld | (cntr_clr & rot_ccw);
    wire [7:0] lb_x   = cntr_clr ? 8'd2 : hposi;
    // rot_ccw, the edge columns: x = 0 (h = 8) shows the 1U read of h = 7, the read-modify-write of the last sprite
    // pixel (cnt is cleared only after it), and the read of h = 0x187 shows at x = 256, off screen.  So for rot_ccw
    // x = 255 (h = 0x187) shows the h = 7 read kept from the start of the line (what the board shows at x = 0), and
    // x = 0 the address the count of 2 would read at h = 7 (count 1: 254 under the flip, else 1): port A reads it in
    // the last clock of h = 7 (ce_pr, after the write-back of d2) and it is kept in d0 of h = 8.  6M takes the combine
    // at ce_pf of h = 8 / 0x187; the write-back at h = 7 and the display clear see 1U unchanged.
    reg        ce_pr_d;   // d0 (registered with the output blanks below)
    wire       h7     = (h == 9'd7);
    wire [7:0] lb_aa  = (rot_ccw & h7 & ce_pr) ? (hflip ? 8'd254 : 8'd1) : lb_addr;
    reg  [4:0] lb_h7, lb_c1;
    always @(posedge clk)
        if (reset) begin
            lb_h7 <= 5'd0; lb_c1 <= 5'd0;
        end else begin
            if (ce_pf & h7)              lb_h7 <= lb_q;
            if (ce_pr_d & (h == 9'd8))   lb_c1 <= lb_qa;
        end
    wire [4:0] lb_pc  = (rot_ccw & (h == 9'd8))    ? lb_c1 :
                        (rot_ccw & (h == 9'h187))  ? lb_h7 : {rc, rv};
    gx_linebuf_ctl u_lb (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .ce_pf(ce_pf), .cntr_clr(lb_clr), .cntr_ld(lb_ld),
        .c256hnx(c256hnx), .hflip1x(hflip1x), .hposi(lb_x), .lb_q(lb_q), .cmb_vid(cmb_vid), .cmb_col(cmb_col),
        .lb_addr(lb_addr), .lb_we(lb_we), .lb_d(lb_d), .rv(rv), .rc(rc)
    );
    gx_dpram #(.AW(8), .DW(5)) u_lbram (
        .clk(clk), .we_a(lb_we), .addr_a(lb_aa), .d_a(lb_d), .q_a(lb_qa), .addr_b(lb_addr), .q_b(lb_q)
    );
    gx_pix_combine u_pc (.raw(raw), .cd(cd), .rv(lb_pc[1:0]), .rc(lb_pc[4:2]), .vid(cmb_vid), .col(cmb_col));

    // ---- shells / missiles, stars, colour
    // The board's HFLIP does not move the shells and missiles (their counters load the object-RAM X whatever the
    // flip; a game in cocktail mode writes mirrored X itself; MAME galaxian_v.cpp:648-650).  The per-game rotation
    // turns the picture with HFLIP/VFLIP behind the program's back, so the X is mirrored here for it: a bullet at
    // screen x = 251 - hpos .. 254 - hpos must show at its mirror hpos + 1 .. hpos + 4, i.e. load 250 - hpos.  Y
    // follows VFLIP on the board already (the 2M adder uses the flipped V).
    // hpos 251..254 show on the board at x = 0 .. 254 - hpos (cut by the left edge), mirrored at hpos + 1 .. 255,
    // which needs a load of -1..-4: the 8-bit counter wraps there and its 5P arm clears.  Those load 254 - hpos (0..3)
    // and their output is delayed 4 pixels (bdel_s / bdel_m, per counter, set at its load).  hpos 255 shows nothing
    // on the board (the counter stops at FF before x = 0) and loads FF, which shows nothing either.  No rot_ccw game
    // uses bullet_az, whose 2-pixel window this mirror does not cover.
    wire       bedge = rot_ccw & (hposi >= 8'd251) & (hposi != 8'd255);
    wire [7:0] bpos  = ~rot_ccw ? hposi : (hposi >= 8'd251) ? 8'd254 - hposi : 8'd250 - hposi;
    wire shell_c, missile_c;
    gx_missile u_ms (
        .clk(clk), .reset(reset), .ce_pf(ce_pf), .cblnx(cblnx), .sld(sld), .mld(mld), .hposi(bpos),
        .bullet_az(bullet_az), .shell(shell_c), .missile(missile_c)
    );
    // the counter outputs change on ce_pf; sh_d[3] / ms_d[3] hold them as they were 4 pixels earlier
    reg       bdel_s, bdel_m;
    reg [3:0] sh_d, ms_d;
    always @(posedge clk)
        if (reset) begin
            bdel_s <= 1'b0; bdel_m <= 1'b0; sh_d <= 4'd0; ms_d <= 4'd0;
        end else if (ce_pf) begin
            if (sld) bdel_s <= bedge;
            if (mld) bdel_m <= bedge;
            sh_d <= {sh_d[2:0], shell_c};
            ms_d <= {ms_d[2:0], missile_c};
        end
    wire shell   = bdel_s ? sh_d[3] : shell_c;
    wire missile = bdel_m ? ms_d[3] : missile_c;

    wire       star_en, stars_off_n, cblx;
    wire [1:0] star_r, star_g, star_b;
    gx_stars u_st (
        .clk(clk), .reset(reset), .ce_12m(ce_12m), .v_inc(v_inc), .v(v[1:0]), .stars_on(stars_on), .hflip(hflip),
        .vsync(vsync), .c256hnx(c256hnx), .hf8(hf8), .vf1(vf1), .stars_off_n(stars_off_n), .stars_disp(stars_disp),
        .star_en(star_en), .star_r(star_r), .star_g(star_g), .star_b(star_b), .noise(noise)
    );

    gx_colour u_col (
        .clk(clk), .reset(reset), .ce_pr(ce_pr), .ce_pf(ce_pf), .vid(cmb_vid), .col(cmb_col), .cblnx(cblnx),
        .clut_a(clut_a), .clut_q(clut_q), .star_en(star_en), .star_r(star_r), .star_g(star_g), .star_b(star_b),
        .shell(shell), .missile(missile), .bullet_az(bullet_az), .stars_off_n(stars_off_n), .cblx(cblx),
        .r(r), .g(g), .b(b)
    );

    // ---- blanks for the output pixel
    reg hb_c, vb_c;
    always @(posedge clk) begin
        if (reset) begin
            hb_c <= 1'b1; vb_c <= 1'b1; ce_pr_d <= 1'b0; hblank_o <= 1'b1; vblank_o <= 1'b1;
        end else begin
            ce_pr_d <= ce_pr;
            if (ce_pr) begin hb_c <= ~c256hnx; vb_c <= vblank; end
            if (ce_pr_d) begin hblank_o <= hb_c; vblank_o <= vb_c; end
        end
    end
    assign ce_pix = ce_pf;

    wire unused_ok = &{1'b0, mstb, h1d, cblx, clut_qa_unused, dn_gfx[15:14]};
endmodule
`default_nettype wire
