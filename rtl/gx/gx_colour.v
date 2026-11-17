// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_colour.v -- the colour output stage (Galaxian manual p.22 zones 13-16): the 6M 74273 colour latch (CK /6MHZ,
// cleared through 6N while blanked), the 6L 82LS123 colour PROM address (the 32 x 8 CLUT RAM is outside), and the
// resistor DAC: PROM R74-R81 (red/green 1K/470/220, blue 470/220), stars R68-R73 (150/100), bullets 9D 74LS368 +
// R58-R60 100 ohm (enabled by 6H 7408 while a shell or missile is on), each line into R61-R63 470 ohm to ground.
// Levels: tools/gx_colour_levels.py; MAME palette galaxian_v.cpp:238-358.
//
// 6M, at ce_pf: if cblnx, {c6, v6, t6, b6} <= {col, vid, vid == 2'b00, 1'b1}; else all 0 (the first blanked pixel is
//   black and the latch stays 0 outside the window).
// clut_a (c) = {c6, v6};  stars_off_n (c) = t6 (6M 1Q: the latched pixel is transparent);  cblx (c) = b6.
// prom_en = ~t6: a transparent pixel tri-states the PROM (stars and bullets show on a floating background); a blanked
//   pixel (6M = 0) enables PROM entry 0.
// Bullets: any = shell | missile.  When any, R and G are driven to cblx, B is driven to shell (missile: blue low), or
//   to 0 with bullet_az (both yellow).  When ~any the 9D outputs float.
// Output register, in the clk after ce_pr (d0 of the next pixel; clut_q, star_* and the bullets are then pixel h's):
//   per gun, level = the 470 ohm node voltage of every driving source (high = 1, low = 0, floating = absent), scaled
//   so the largest reachable node (a shell over a '11' red/green star) is 255.  Red = clut_q[2:0], green = [5:3],
//   blue = [7:6].  A PROM or star bit at 0 sinks through its resistor, so a bullet over a pixel is not an OR.
//   The PROM and a star never drive together (star_en includes stars_off_n = t6).
// reset (synchronous): 6M, the output register and the d0 strobe cleared.
`default_nettype none
module gx_colour (
    input  wire       clk,
    input  wire       reset,
    input  wire       ce_pr,
    input  wire       ce_pf,
    input  wire [1:0] vid,
    input  wire [2:0] col,
    input  wire       cblnx,
    output wire [4:0] clut_a,
    input  wire [7:0] clut_q,
    input  wire       star_en,
    input  wire [1:0] star_r,
    input  wire [1:0] star_g,
    input  wire [1:0] star_b,
    input  wire       shell,
    input  wire       missile,
    input  wire       bullet_az,
    output wire       stars_off_n,
    output wire       cblx,
    output reg  [7:0] r,
    output reg  [7:0] g,
    output reg  [7:0] b
);
    // Internal registers with power-up values
    reg [2:0] c6   = 3'd0;
    reg [1:0] v6   = 2'd0;
    reg       t6   = 1'b0;
    reg       b6   = 1'b0;
    reg       d0   = 1'b0;
    // Derived combinational signals
    wire prom_en = ~t6;
    wire any   = shell | missile;
    wire [1:0] bs_rg = {any, b6};
    wire [1:0] bs_b  = {any, shell & ~bullet_az};
    // CLUT address and status outputs
    assign clut_a      = {c6, v6};
    assign stars_off_n = t6;
    assign cblx        = b6;
    // 6M colour latch updates
    always @(posedge clk) begin
        if (reset) begin
            c6 <= 3'd0;
            v6 <= 2'd0;
            t6 <= 1'b0;
            b6 <= 1'b0;
        end else if (ce_pf) begin
            if (cblnx) begin
                c6 <= col;
                v6 <= vid;
                t6 <= (vid == 2'b00);
                b6 <= 1'b1;
            end else begin
                c6 <= 3'd0;
                v6 <= 2'd0;
                t6 <= 1'b0;
                b6 <= 1'b0;
            end
        end
    end
    // d0 strobe (ce_pr delayed one cycle)
    always @(posedge clk) begin
        if (reset) d0 <= 1'b0;
        else d0 <= ce_pr;
    end
    // Output register update using old 6M state
    always @(posedge clk) begin
        if (reset) begin
            r <= 8'd0;
            g <= 8'd0;
            b <= 8'd0;
        end else if (d0) begin
            r <= RG(prom_en, clut_q[2:0], star_en, star_r, bs_rg);
            g <= RG(prom_en, clut_q[5:3], star_en, star_g, bs_rg);
            b <= B(prom_en, clut_q[7:6], star_en, star_b, bs_b);
        end
    end
    // Functions implementing level tables
    function [7:0] RG(input pe, input [2:0] pc, input se, input [1:0] sc, input [1:0] bs);
    begin
        if (pe) begin
            case (bs)
                2'b11: case (pc)
                    3'd0: RG = 8'd139;
                    3'd1: RG = 8'd153;
                    3'd2: RG = 8'd169;
                    3'd3: RG = 8'd183;
                    3'd4: RG = 8'd202;
                    3'd5: RG = 8'd216;
                    3'd6: RG = 8'd232;
                    3'd7: RG = 8'd246;
                    default: RG = 8'd0;
                endcase
                2'b10: case (pc)
                    3'd0: RG = 8'd0;
                    3'd1: RG = 8'd14;
                    3'd2: RG = 8'd30;
                    3'd3: RG = 8'd43;
                    3'd4: RG = 8'd63;
                    3'd5: RG = 8'd77;
                    3'd6: RG = 8'd93;
                    3'd7: RG = 8'd107;
                    default: RG = 8'd0;
                endcase
                default: case (pc)
                    3'd0: RG = 8'd0;
                    3'd1: RG = 8'd28;
                    3'd2: RG = 8'd60;
                    3'd3: RG = 8'd88;
                    3'd4: RG = 8'd128;
                    3'd5: RG = 8'd156;
                    3'd6: RG = 8'd187;
                    3'd7: RG = 8'd216;
                    default: RG = 8'd0;
                endcase
            endcase
        end else if (se) begin
            RG = STAR(bs, sc);
        end else begin
            if (bs == 2'b11) RG = 8'd227;
            else RG = 8'd0;
        end
    end
    endfunction
    function [7:0] B(input pe, input [1:0] pc, input se, input [1:0] sc, input [1:0] bs);
    begin
        if (pe) begin
            case (bs)
                2'b11: case (pc)
                    2'd0: B = 8'd146;
                    2'd1: B = 8'd178;
                    2'd2: B = 8'd213;
                    2'd3: B = 8'd244;
                    default: B = 8'd0;
                endcase
                2'b10: case (pc)
                    2'd0: B = 8'd0;
                    2'd1: B = 8'd31;
                    2'd2: B = 8'd67;
                    2'd3: B = 8'd98;
                    default: B = 8'd0;
                endcase
                default: case (pc)
                    2'd0: B = 8'd0;
                    2'd1: B = 8'd67;
                    2'd2: B = 8'd142;
                    2'd3: B = 8'd209;
                    default: B = 8'd0;
                endcase
            endcase
        end else if (se) begin
            B = STAR(bs, sc);
        end else begin
            if (bs == 2'b11) B = 8'd227;
            else B = 8'd0;
        end
    end
    endfunction
    function [7:0] STAR(input [1:0] bs, input [1:0] sc);
    begin
        case (bs)
            2'b11: case (sc)
                2'd0: STAR = 8'd96;
                2'd1: STAR = 8'd159;
                2'd2: STAR = 8'd191;
                2'd3: STAR = 8'd255;
                default: STAR = 8'd0;
            endcase
            2'b10: case (sc)
                2'd0: STAR = 8'd0;
                2'd1: STAR = 8'd64;
                2'd2: STAR = 8'd96;
                2'd3: STAR = 8'd159;
                default: STAR = 8'd0;
            endcase
            default: case (sc)
                2'd0: STAR = 8'd0;
                2'd1: STAR = 8'd98;
                2'd2: STAR = 8'd147;
                2'd3: STAR = 8'd244;
                default: STAR = 8'd0;
            endcase
        endcase
    end
    endfunction
endmodule
`default_nettype wire
