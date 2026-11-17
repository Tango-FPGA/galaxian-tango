// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_snd_mix.v -- the sound mixers and output coupling of four boards: Galaxian (manual p.22 zones 10-16: R24 / R27 /
// R30 and C20, R49-R52, the two R34s, R40, R43 + C26, R91, C46 / R92), Moon Cresta Gremlin 800-3121 (MCG p1: C20,
// R34 15K, one node, C39 / R42), King & Balloon (KB p14-15: as Gremlin with C20 0.1 uF, C29 / R42 and the speech join)
// and Nichibutsu MC-1 (MCS PDF 20: the background on the node with C20, no R34 or R50, the VR 2K pot, no coupling
// capacitor).  Constants, the coefficient table and a bit-exact model:
// tools/gx_mix_coefs.py (--check verifies this file).
//
// Board: kb ? KB (2) : mc1 ? MC1 (3) : mix_moon ? MCG (1) : GAL (0); cfg = {board, vol2, vol1} selects 30 coefficients.
// Each network is linear with two states, vA (the voltage on C20) and vc (on C26, fire side minus R43 side), and four
// sources held for the 48 kHz step: X (the mean of the three 555 outputs, behind R24 || R27 || R30), J (the pitch bits'
// Thevenin voltage, 4 V x count / 32 weighted by WA / WC / WD), H and v_fire.  H is v_hit (the HIT band-pass, behind
// R40) on GAL / MCG / KB and v_flash (gx_snd_hit's gated C21, MC-1's FLASH behind R35) on MC1.  Per sample, with
// u = (X, J, H, F):
//   y  = CM . (vA, vc) + DM . u           the step's mean node voltage (exact for held inputs)
//   vA' = PA . (vA, vc) + GMA . u;  vc' = PC . (vA, vc) + GMC . u    (the exact step, Phi and Gamma)
// X from bg: gx_snd_bg outputs its own unloaded C20 node (bg[k] = bg[k-1] + A0 (X[k] - bg[k-1]), floored to Q4.12;
// X = m x 3/64 V, m = 0..96), so m = round(bg[k-1] / 192 + (bg[k] - bg[k-1]) / (192 A0)), clamped to 0..96 (KR0, KR1;
// the floors move it by at most 0.09 of a step, so m is exact).
// Pre-charge: the first sample after reset starts every state at the DC operating point of that sample's inputs:
// m = round(bg / 192), vA = GA . u, vc = v_fire - HD . u (HD . u: the node at DC, C26 open), and z = y, so the first
// output sample is 0 and no start-up step reaches the output.
// K&B: the speech board's output joins at the volume pot: y += KS speech (KS = (Rth + R42) / R33, per {vol2, vol1}:
// Rth is N's resistance in that VOL state; table entry 29, 0 on the other boards).
// Output coupling, a first-order high-pass of y: z += A46 (y - z); the output is y - z (GAL C46 into R92 100K, MCG
// C39 / R42 / 1K, KB C29 / R42 / 1K || R33, MC1 none on the board: the DC is removed at tau 10 ms).
// The pitch bits are box-averaged over each 48 kHz sample: qa / qc / qd are counted at ce_1m5 (the 1.536 MHz rate at
// which the 9K/8K counter steps), 32 per sample.
//
// Timing: at ce_48k the counts, bg, H, v_fire, speech, vol1 / vol2 and the board are latched (the leaves' outputs
// of the previous sample), then 35 clocks of one shared 27 x 18 multiplier compute the sample.
// Formats: voltages Q6.20 (V x 2^20, 27-bit signed operands); coefficients Q0.17 signed; products >>> 17.  Inputs: bg
// and v_fire Q4.12 unsigned volts, v_hit and v_flash Q4.12 signed, speech Q5.11 signed.
// audio: signed 16-bit, Q3.13 volts (1 LSB = 1/8192 V, +-4 V full scale; floor, saturated), updated 35 clk after
// each ce_48k.  It is the coupled node voltage with no further gain; for K&B it is half of it (y - z >>> 8), as its
// speech peaks near 3.3 V.  The wrapper adds its DC blocker and Audio Boost.
// reset (synchronous): states, counts and audio 0; the next sample is a pre-charge sample.
`default_nettype none
module gx_snd_mix (
    input  wire               clk,
    input  wire               reset,
    input  wire               ce_1m5,
    input  wire               ce_48k,
    input  wire               mix_moon,
    input  wire               kb,
    input  wire               mc1,
    input  wire               vol1,
    input  wire               vol2,
    input  wire               qa,
    input  wire               qc,
    input  wire               qd,
    input  wire        [15:0] bg,
    input  wire signed [15:0] v_hit,
    input  wire signed [15:0] v_flash,
    input  wire        [15:0] v_fire,
    input  wire signed [15:0] speech,
    output reg  signed [15:0] audio
);
    localparam signed [17:0] MIX_KR0 = 18'sd683;
    localparam signed [17:0] MIX_KR1 = 18'sd11268;
    localparam signed [17:0] MIX_A46_GAL = 18'sd269;
    localparam signed [17:0] MIX_A46_MCG = 18'sd1100;
    localparam signed [17:0] MIX_A46_KB = 18'sd1101;
    localparam signed [17:0] MIX_A46_MC1 = 18'sd273;

    // coefficient k (0..29, tools/gx_mix_coefs.py KEYS) of cfg c: cf({c, k})
    function signed [17:0] cf(input [8:0] a);
        case (a)
            // BEGIN gx_mix_coefs table
            9'd0: cf =  18'sd52429;   // GAL_0 WA
            9'd1: cf =  18'sd78643;   // GAL_0 WC
            9'd3: cf =  18'sd97376;   // GAL_0 GA_X
            9'd4: cf =  18'sd11571;   // GAL_0 GA_J
            9'd5: cf =  18'sd18135;   // GAL_0 GA_H
            9'd7: cf =  18'sd11969;   // GAL_0 HD_X
            9'd8: cf =  18'sd7647;   // GAL_0 HD_J
            9'd9: cf =  18'sd91357;   // GAL_0 HD_H
            9'd11: cf =  18'sd10686;   // GAL_0 CM_A
            9'd12: cf = -18'sd40585;   // GAL_0 CM_C
            9'd13: cf =  18'sd324;   // GAL_0 DM_X
            9'd14: cf =  18'sd4336;   // GAL_0 DM_J
            9'd15: cf =  18'sd61591;   // GAL_0 DM_H
            9'd16: cf =  18'sd40585;   // GAL_0 DM_F
            9'd17: cf =  18'sd120419;   // GAL_0 PA_A
            9'd18: cf = -18'sd663;   // GAL_0 PA_C
            9'd19: cf =  18'sd7854;   // GAL_0 GM_A_X
            9'd20: cf =  18'sd902;   // GAL_0 GM_A_J
            9'd21: cf =  18'sd1012;   // GAL_0 GM_A_H
            9'd22: cf =  18'sd663;   // GAL_0 GM_A_F
            9'd23: cf = -18'sd6629;   // GAL_0 PC_A
            9'd24: cf =  18'sd74616;   // GAL_0 PC_C
            9'd25: cf = -18'sd230;   // GAL_0 GM_C_X
            9'd26: cf = -18'sd2709;   // GAL_0 GM_C_J
            9'd27: cf = -18'sd38433;   // GAL_0 GM_C_H
            9'd28: cf =  18'sd56456;   // GAL_0 GM_C_F
            9'd32: cf =  18'sd22599;   // GAL_1 WA
            9'd33: cf =  18'sd108473;   // GAL_1 WC
            9'd35: cf =  18'sd93252;   // GAL_1 GA_X
            9'd36: cf =  18'sd20732;   // GAL_1 GA_J
            9'd37: cf =  18'sd14006;   // GAL_1 GA_H
            9'd39: cf =  18'sd9244;   // GAL_1 HD_X
            9'd40: cf =  18'sd13702;   // GAL_1 HD_J
            9'd41: cf =  18'sd88628;   // GAL_1 HD_H
            9'd43: cf =  18'sd8661;   // GAL_1 CM_A
            9'd44: cf = -18'sd39970;   // GAL_1 CM_C
            9'd45: cf =  18'sd263;   // GAL_1 DM_X
            9'd46: cf =  18'sd8153;   // GAL_1 DM_J
            9'd47: cf =  18'sd60675;   // GAL_1 DM_H
            9'd48: cf =  18'sd39970;   // GAL_1 DM_F
            9'd49: cf =  18'sd119998;   // GAL_1 PA_A
            9'd50: cf = -18'sd537;   // GAL_1 PA_C
            9'd51: cf =  18'sd7841;   // GAL_1 GM_A_X
            9'd52: cf =  18'sd1695;   // GAL_1 GM_A_J
            9'd53: cf =  18'sd820;   // GAL_1 GM_A_H
            9'd54: cf =  18'sd537;   // GAL_1 GM_A_F
            9'd55: cf = -18'sd5370;   // GAL_1 PC_A
            9'd56: cf =  18'sd74246;   // GAL_1 PC_C
            9'd57: cf = -18'sd187;   // GAL_1 GM_C_X
            9'd58: cf = -18'sd5091;   // GAL_1 GM_C_J
            9'd59: cf = -18'sd37851;   // GAL_1 GM_C_H
            9'd60: cf =  18'sd56826;   // GAL_1 GM_C_F
            9'd64: cf =  18'sd27888;   // GAL_2 WA
            9'd65: cf =  18'sd41831;   // GAL_2 WC
            9'd66: cf =  18'sd61353;   // GAL_2 WD
            9'd67: cf =  18'sd94401;   // GAL_2 GA_X
            9'd68: cf =  18'sd18180;   // GAL_2 GA_J
            9'd69: cf =  18'sd15156;   // GAL_2 GA_H
            9'd71: cf =  18'sd10003;   // GAL_2 HD_X
            9'd72: cf =  18'sd12015;   // GAL_2 HD_J
            9'd73: cf =  18'sd89388;   // GAL_2 HD_H
            9'd75: cf =  18'sd9245;   // GAL_2 CM_A
            9'd76: cf = -18'sd40147;   // GAL_2 CM_C
            9'd77: cf =  18'sd281;   // GAL_2 DM_X
            9'd78: cf =  18'sd7052;   // GAL_2 DM_J
            9'd79: cf =  18'sd60940;   // GAL_2 DM_H
            9'd80: cf =  18'sd40147;   // GAL_2 DM_F
            9'd81: cf =  18'sd120119;   // GAL_2 PA_A
            9'd82: cf = -18'sd573;   // GAL_2 PA_C
            9'd83: cf =  18'sd7845;   // GAL_2 GM_A_X
            9'd84: cf =  18'sd1467;   // GAL_2 GM_A_J
            9'd85: cf =  18'sd875;   // GAL_2 GM_A_H
            9'd86: cf =  18'sd573;   // GAL_2 GM_A_F
            9'd87: cf = -18'sd5733;   // GAL_2 PC_A
            9'd88: cf =  18'sd74353;   // GAL_2 PC_C
            9'd89: cf = -18'sd199;   // GAL_2 GM_C_X
            9'd90: cf = -18'sd4404;   // GAL_2 GM_C_J
            9'd91: cf = -18'sd38018;   // GAL_2 GM_C_H
            9'd92: cf =  18'sd56719;   // GAL_2 GM_C_F
            9'd96: cf =  18'sd16384;   // GAL_3 WA
            9'd97: cf =  18'sd78643;   // GAL_3 WC
            9'd98: cf =  18'sd36045;   // GAL_3 WD
            9'd99: cf =  18'sd91409;   // GAL_3 GA_X
            9'd100: cf =  18'sd24828;   // GAL_3 GA_J
            9'd101: cf =  18'sd12160;   // GAL_3 GA_H
            9'd103: cf =  18'sd8026;   // GAL_3 HD_X
            9'd104: cf =  18'sd16408;   // GAL_3 HD_J
            9'd105: cf =  18'sd87408;   // GAL_3 HD_H
            9'd107: cf =  18'sd7690;   // GAL_3 CM_A
            9'd108: cf = -18'sd39676;   // GAL_3 CM_C
            9'd109: cf =  18'sd234;   // GAL_3 DM_X
            9'd110: cf =  18'sd9985;   // GAL_3 DM_J
            9'd111: cf =  18'sd60236;   // GAL_3 DM_H
            9'd112: cf =  18'sd39676;   // GAL_3 DM_F
            9'd113: cf =  18'sd119797;   // GAL_3 PA_A
            9'd114: cf = -18'sd477;   // GAL_3 PA_C
            9'd115: cf =  18'sd7834;   // GAL_3 GM_A_X
            9'd116: cf =  18'sd2076;   // GAL_3 GM_A_J
            9'd117: cf =  18'sd728;   // GAL_3 GM_A_H
            9'd118: cf =  18'sd477;   // GAL_3 GM_A_F
            9'd119: cf = -18'sd4767;   // GAL_3 PC_A
            9'd120: cf =  18'sd74069;   // GAL_3 PC_C
            9'd121: cf = -18'sd166;   // GAL_3 GM_C_X
            9'd122: cf = -18'sd6233;   // GAL_3 GM_C_J
            9'd123: cf = -18'sd37572;   // GAL_3 GM_C_H
            9'd124: cf =  18'sd57003;   // GAL_3 GM_C_F
            9'd128: cf =  18'sd52429;   // MCG_0 WA
            9'd129: cf =  18'sd78643;   // MCG_0 WC
            9'd131: cf =  18'sd109463;   // MCG_0 GA_X
            9'd132: cf =  18'sd3087;   // MCG_0 GA_J
            9'd133: cf =  18'sd18522;   // MCG_0 GA_H
            9'd135: cf =  18'sd12224;   // MCG_0 HD_X
            9'd136: cf =  18'sd16978;   // MCG_0 HD_J
            9'd137: cf =  18'sd101869;   // MCG_0 HD_H
            9'd139: cf =  18'sd6956;   // MCG_0 CM_A
            9'd140: cf = -18'sd44014;   // MCG_0 CM_C
            9'd141: cf =  18'sd2310;   // MCG_0 DM_X
            9'd142: cf =  18'sd11113;   // MCG_0 DM_J
            9'd143: cf =  18'sd66679;   // MCG_0 DM_H
            9'd144: cf =  18'sd44014;   // MCG_0 DM_F
            9'd145: cf =  18'sd61720;   // MCG_0 PA_A
            9'd146: cf = -18'sd4134;   // MCG_0 PA_C
            9'd147: cf =  18'sd57533;   // MCG_0 GM_A_X
            9'd148: cf =  18'sd1098;   // MCG_0 GM_A_J
            9'd149: cf =  18'sd6587;   // MCG_0 GM_A_H
            9'd150: cf =  18'sd4134;   // MCG_0 GM_A_F
            9'd151: cf = -18'sd4134;   // MCG_0 PC_A
            9'd152: cf =  18'sd76693;   // MCG_0 PC_C
            9'd153: cf = -18'sd1619;   // MCG_0 GM_C_X
            9'd154: cf = -18'sd6947;   // MCG_0 GM_C_J
            9'd155: cf = -18'sd41679;   // MCG_0 GM_C_H
            9'd156: cf =  18'sd54379;   // MCG_0 GM_C_F
            9'd160: cf =  18'sd22599;   // MCG_1 WA
            9'd161: cf =  18'sd108473;   // MCG_1 WC
            9'd163: cf =  18'sd109139;   // MCG_1 GA_X
            9'd164: cf =  18'sd6116;   // MCG_1 GA_J
            9'd165: cf =  18'sd15817;   // MCG_1 GA_H
            9'd167: cf =  18'sd10439;   // MCG_1 HD_X
            9'd168: cf =  18'sd33638;   // MCG_1 HD_J
            9'd169: cf =  18'sd86995;   // MCG_1 HD_H
            9'd171: cf =  18'sd6250;   // MCG_1 CM_A
            9'd172: cf = -18'sd39532;   // MCG_1 CM_C
            9'd173: cf =  18'sd2086;   // MCG_1 DM_X
            9'd174: cf =  18'sd23201;   // MCG_1 DM_J
            9'd175: cf =  18'sd60002;   // MCG_1 DM_H
            9'd176: cf =  18'sd39532;   // MCG_1 DM_F
            9'd177: cf =  18'sd61651;   // MCG_1 PA_A
            9'd178: cf = -18'sd3704;   // MCG_1 PA_C
            9'd179: cf =  18'sd57509;   // MCG_1 GM_A_X
            9'd180: cf =  18'sd2289;   // MCG_1 GM_A_J
            9'd181: cf =  18'sd5919;   // MCG_1 GM_A_H
            9'd182: cf =  18'sd3704;   // MCG_1 GM_A_F
            9'd183: cf = -18'sd3704;   // MCG_1 PC_A
            9'd184: cf =  18'sd73995;   // MCG_1 PC_C
            9'd185: cf = -18'sd1461;   // MCG_1 GM_C_X
            9'd186: cf = -18'sd14475;   // MCG_1 GM_C_J
            9'd187: cf = -18'sd37436;   // MCG_1 GM_C_H
            9'd188: cf =  18'sd57077;   // MCG_1 GM_C_F
            9'd192: cf =  18'sd27888;   // MCG_2 WA
            9'd193: cf =  18'sd41831;   // MCG_2 WC
            9'd194: cf =  18'sd61353;   // MCG_2 WD
            9'd195: cf =  18'sd109236;   // MCG_2 GA_X
            9'd196: cf =  18'sd5210;   // MCG_2 GA_J
            9'd197: cf =  18'sd16626;   // MCG_2 GA_H
            9'd199: cf =  18'sd10973;   // MCG_2 HD_X
            9'd200: cf =  18'sd28653;   // MCG_2 HD_J
            9'd201: cf =  18'sd91446;   // MCG_2 HD_H
            9'd203: cf =  18'sd6469;   // MCG_2 CM_A
            9'd204: cf = -18'sd40922;   // MCG_2 CM_C
            9'd205: cf =  18'sd2156;   // MCG_2 DM_X
            9'd206: cf =  18'sd19450;   // MCG_2 DM_J
            9'd207: cf =  18'sd62075;   // MCG_2 DM_H
            9'd208: cf =  18'sd40922;   // MCG_2 DM_F
            9'd209: cf =  18'sd61673;   // MCG_2 PA_A
            9'd210: cf = -18'sd3837;   // MCG_2 PA_C
            9'd211: cf =  18'sd57516;   // MCG_2 GM_A_X
            9'd212: cf =  18'sd1920;   // MCG_2 GM_A_J
            9'd213: cf =  18'sd6126;   // MCG_2 GM_A_H
            9'd214: cf =  18'sd3837;   // MCG_2 GM_A_F
            9'd215: cf = -18'sd3837;   // MCG_2 PC_A
            9'd216: cf =  18'sd74830;   // MCG_2 PC_C
            9'd217: cf = -18'sd1511;   // MCG_2 GM_C_X
            9'd218: cf = -18'sd12142;   // MCG_2 GM_C_J
            9'd219: cf = -18'sd38752;   // MCG_2 GM_C_H
            9'd220: cf =  18'sd56242;   // MCG_2 GM_C_F
            9'd224: cf =  18'sd16384;   // MCG_3 WA
            9'd225: cf =  18'sd78643;   // MCG_3 WC
            9'd226: cf =  18'sd36045;   // MCG_3 WD
            9'd227: cf =  18'sd108970;   // MCG_3 GA_X
            9'd228: cf =  18'sd7688;   // MCG_3 GA_J
            9'd229: cf =  18'sd14414;   // MCG_3 GA_H
            9'd231: cf =  18'sd9513;   // MCG_3 HD_X
            9'd232: cf =  18'sd42281;   // MCG_3 HD_J
            9'd233: cf =  18'sd79277;   // MCG_3 HD_H
            9'd235: cf =  18'sd5854;   // MCG_3 CM_A
            9'd236: cf = -18'sd37017;   // MCG_3 CM_C
            9'd237: cf =  18'sd1960;   // MCG_3 DM_X
            9'd238: cf =  18'sd29997;   // MCG_3 DM_J
            9'd239: cf =  18'sd56244;   // MCG_3 DM_H
            9'd240: cf =  18'sd37017;   // MCG_3 DM_F
            9'd241: cf =  18'sd61613;   // MCG_3 PA_A
            9'd242: cf = -18'sd3464;   // MCG_3 PA_C
            9'd243: cf =  18'sd57495;   // MCG_3 GM_A_X
            9'd244: cf =  18'sd2956;   // MCG_3 GM_A_J
            9'd245: cf =  18'sd5543;   // MCG_3 GM_A_H
            9'd246: cf =  18'sd3464;   // MCG_3 GM_A_F
            9'd247: cf = -18'sd3464;   // MCG_3 PC_A
            9'd248: cf =  18'sd72486;   // MCG_3 PC_C
            9'd249: cf = -18'sd1372;   // MCG_3 GM_C_X
            9'd250: cf = -18'sd18695;   // MCG_3 GM_C_J
            9'd251: cf = -18'sd35054;   // MCG_3 GM_C_H
            9'd252: cf =  18'sd58586;   // MCG_3 GM_C_F
            9'd256: cf =  18'sd52429;   // KB_0 WA
            9'd257: cf =  18'sd78643;   // KB_0 WC
            9'd259: cf =  18'sd109463;   // KB_0 GA_X
            9'd260: cf =  18'sd3087;   // KB_0 GA_J
            9'd261: cf =  18'sd18522;   // KB_0 GA_H
            9'd263: cf =  18'sd12224;   // KB_0 HD_X
            9'd264: cf =  18'sd16978;   // KB_0 HD_J
            9'd265: cf =  18'sd101869;   // KB_0 HD_H
            9'd267: cf =  18'sd9401;   // KB_0 CM_A
            9'd268: cf = -18'sd43851;   // KB_0 CM_C
            9'd269: cf =  18'sd284;   // KB_0 DM_X
            9'd270: cf =  18'sd11077;   // KB_0 DM_J
            9'd271: cf =  18'sd66460;   // KB_0 DM_H
            9'd272: cf =  18'sd43851;   // KB_0 DM_F
            9'd273: cf =  18'sd121558;   // KB_0 PA_A
            9'd274: cf = -18'sd584;   // KB_0 PA_C
            9'd275: cf =  18'sd7891;   // KB_0 GM_A_X
            9'd276: cf =  18'sd148;   // KB_0 GM_A_J
            9'd277: cf =  18'sd890;   // KB_0 GM_A_H
            9'd278: cf =  18'sd584;   // KB_0 GM_A_F
            9'd279: cf = -18'sd5844;   // KB_0 PC_A
            9'd280: cf =  18'sd76580;   // KB_0 PC_C
            9'd281: cf = -18'sd202;   // KB_0 GM_C_X
            9'd282: cf = -18'sd6921;   // KB_0 GM_C_J
            9'd283: cf = -18'sd41525;   // KB_0 GM_C_H
            9'd284: cf =  18'sd54492;   // KB_0 GM_C_F
            9'd285: cf =  18'sd66121;   // KB_0 KS
            9'd288: cf =  18'sd22599;   // KB_1 WA
            9'd289: cf =  18'sd108473;   // KB_1 WC
            9'd291: cf =  18'sd109139;   // KB_1 GA_X
            9'd292: cf =  18'sd6116;   // KB_1 GA_J
            9'd293: cf =  18'sd15817;   // KB_1 GA_H
            9'd295: cf =  18'sd10439;   // KB_1 HD_X
            9'd296: cf =  18'sd33638;   // KB_1 HD_J
            9'd297: cf =  18'sd86995;   // KB_1 HD_H
            9'd299: cf =  18'sd8461;   // KB_1 CM_A
            9'd300: cf = -18'sd39400;   // KB_1 CM_C
            9'd301: cf =  18'sd257;   // KB_1 DM_X
            9'd302: cf =  18'sd23132;   // KB_1 DM_J
            9'd303: cf =  18'sd59824;   // KB_1 DM_H
            9'd304: cf =  18'sd39400;   // KB_1 DM_F
            9'd305: cf =  18'sd121546;   // KB_1 PA_A
            9'd306: cf = -18'sd525;   // KB_1 PA_C
            9'd307: cf =  18'sd7890;   // KB_1 GM_A_X
            9'd308: cf =  18'sd310;   // KB_1 GM_A_J
            9'd309: cf =  18'sd801;   // KB_1 GM_A_H
            9'd310: cf =  18'sd525;   // KB_1 GM_A_F
            9'd311: cf = -18'sd5249;   // KB_1 PC_A
            9'd312: cf =  18'sd73903;   // KB_1 PC_C
            9'd313: cf = -18'sd182;   // KB_1 GM_C_X
            9'd314: cf = -18'sd14427;   // KB_1 GM_C_J
            9'd315: cf = -18'sd37310;   // KB_1 GM_C_H
            9'd316: cf =  18'sd57169;   // KB_1 GM_C_F
            9'd317: cf =  18'sd65425;   // KB_1 KS
            9'd320: cf =  18'sd27888;   // KB_2 WA
            9'd321: cf =  18'sd41831;   // KB_2 WC
            9'd322: cf =  18'sd61353;   // KB_2 WD
            9'd323: cf =  18'sd109236;   // KB_2 GA_X
            9'd324: cf =  18'sd5210;   // KB_2 GA_J
            9'd325: cf =  18'sd16626;   // KB_2 GA_H
            9'd327: cf =  18'sd10973;   // KB_2 HD_X
            9'd328: cf =  18'sd28653;   // KB_2 HD_J
            9'd329: cf =  18'sd91446;   // KB_2 HD_H
            9'd331: cf =  18'sd8752;   // KB_2 CM_A
            9'd332: cf = -18'sd40780;   // KB_2 CM_C
            9'd333: cf =  18'sd265;   // KB_2 DM_X
            9'd334: cf =  18'sd19390;   // KB_2 DM_J
            9'd335: cf =  18'sd61884;   // KB_2 DM_H
            9'd336: cf =  18'sd40780;   // KB_2 DM_F
            9'd337: cf =  18'sd121550;   // KB_2 PA_A
            9'd338: cf = -18'sd543;   // KB_2 PA_C
            9'd339: cf =  18'sd7891;   // KB_2 GM_A_X
            9'd340: cf =  18'sd260;   // KB_2 GM_A_J
            9'd341: cf =  18'sd829;   // KB_2 GM_A_H
            9'd342: cf =  18'sd543;   // KB_2 GM_A_F
            9'd343: cf = -18'sd5434;   // KB_2 PC_A
            9'd344: cf =  18'sd74732;   // KB_2 PC_C
            9'd345: cf = -18'sd188;   // KB_2 GM_C_X
            9'd346: cf = -18'sd12100;   // KB_2 GM_C_J
            9'd347: cf = -18'sd38617;   // KB_2 GM_C_H
            9'd348: cf =  18'sd56340;   // KB_2 GM_C_F
            9'd349: cf =  18'sd65633;   // KB_2 KS
            9'd352: cf =  18'sd16384;   // KB_3 WA
            9'd353: cf =  18'sd78643;   // KB_3 WC
            9'd354: cf =  18'sd36045;   // KB_3 WD
            9'd355: cf =  18'sd108970;   // KB_3 GA_X
            9'd356: cf =  18'sd7688;   // KB_3 GA_J
            9'd357: cf =  18'sd14414;   // KB_3 GA_H
            9'd359: cf =  18'sd9513;   // KB_3 HD_X
            9'd360: cf =  18'sd42281;   // KB_3 HD_J
            9'd361: cf =  18'sd79277;   // KB_3 HD_H
            9'd363: cf =  18'sd7931;   // KB_3 CM_A
            9'd364: cf = -18'sd36900;   // KB_3 CM_C
            9'd365: cf =  18'sd241;   // KB_3 DM_X
            9'd366: cf =  18'sd29913;   // KB_3 DM_J
            9'd367: cf =  18'sd56087;   // KB_3 DM_H
            9'd368: cf =  18'sd36900;   // KB_3 DM_F
            9'd369: cf =  18'sd121539;   // KB_3 PA_A
            9'd370: cf = -18'sd492;   // KB_3 PA_C
            9'd371: cf =  18'sd7890;   // KB_3 GM_A_X
            9'd372: cf =  18'sd401;   // KB_3 GM_A_J
            9'd373: cf =  18'sd751;   // KB_3 GM_A_H
            9'd374: cf =  18'sd492;   // KB_3 GM_A_F
            9'd375: cf = -18'sd4916;   // KB_3 PC_A
            9'd376: cf =  18'sd72406;   // KB_3 PC_C
            9'd377: cf = -18'sd171;   // KB_3 GM_C_X
            9'd378: cf = -18'sd18636;   // KB_3 GM_C_J
            9'd379: cf = -18'sd34943;   // KB_3 GM_C_H
            9'd380: cf =  18'sd58666;   // KB_3 GM_C_F
            9'd381: cf =  18'sd65064;   // KB_3 KS
            9'd384: cf =  18'sd131071;   // MC1_0 WA
            9'd387: cf =  18'sd46981;   // MC1_0 GA_X
            9'd388: cf =  18'sd4746;   // MC1_0 GA_J
            9'd389: cf =  18'sd1044;   // MC1_0 GA_H
            9'd391: cf =  18'sd46981;   // MC1_0 HD_X
            9'd392: cf =  18'sd4746;   // MC1_0 HD_J
            9'd393: cf =  18'sd1044;   // MC1_0 HD_H
            9'd395: cf =  18'sd116292;   // MC1_0 CM_A
            9'd396: cf = -18'sd4248;   // MC1_0 CM_C
            9'd397: cf =  18'sd3775;   // MC1_0 DM_X
            9'd398: cf =  18'sd381;   // MC1_0 DM_J
            9'd399: cf =  18'sd84;   // MC1_0 DM_H
            9'd400: cf =  18'sd4248;   // MC1_0 DM_F
            9'd401: cf =  18'sd103804;   // MC1_0 PA_A
            9'd402: cf = -18'sd6990;   // MC1_0 PA_C
            9'd403: cf =  18'sd7268;   // MC1_0 GM_A_X
            9'd404: cf =  18'sd734;   // MC1_0 GM_A_J
            9'd405: cf =  18'sd162;   // MC1_0 GM_A_H
            9'd406: cf =  18'sd6990;   // MC1_0 GM_A_F
            9'd407: cf = -18'sd69903;   // MC1_0 PC_A
            9'd408: cf =  18'sd53763;   // MC1_0 PC_C
            9'd409: cf = -18'sd2655;   // MC1_0 GM_C_X
            9'd410: cf = -18'sd268;   // MC1_0 GM_C_J
            9'd411: cf = -18'sd59;   // MC1_0 GM_C_H
            9'd412: cf =  18'sd77309;   // MC1_0 GM_C_F
            9'd416: cf =  18'sd30482;   // MC1_1 WA
            9'd417: cf =  18'sd100590;   // MC1_1 WC
            9'd419: cf =  18'sd41967;   // MC1_1 GA_X
            9'd420: cf =  18'sd18228;   // MC1_1 GA_J
            9'd421: cf =  18'sd933;   // MC1_1 GA_H
            9'd423: cf =  18'sd41967;   // MC1_1 HD_X
            9'd424: cf =  18'sd18228;   // MC1_1 HD_J
            9'd425: cf =  18'sd933;   // MC1_1 HD_H
            9'd427: cf =  18'sd115142;   // MC1_1 CM_A
            9'd428: cf = -18'sd4217;   // MC1_1 CM_C
            9'd429: cf =  18'sd3750;   // MC1_1 DM_X
            9'd430: cf =  18'sd1629;   // MC1_1 DM_J
            9'd431: cf =  18'sd83;   // MC1_1 DM_H
            9'd432: cf =  18'sd4217;   // MC1_1 DM_F
            9'd433: cf =  18'sd101686;   // MC1_1 PA_A
            9'd434: cf = -18'sd6910;   // MC1_1 PA_C
            9'd435: cf =  18'sd7196;   // MC1_1 GM_A_X
            9'd436: cf =  18'sd3126;   // MC1_1 GM_A_J
            9'd437: cf =  18'sd160;   // MC1_1 GM_A_H
            9'd438: cf =  18'sd6910;   // MC1_1 GM_A_F
            9'd439: cf = -18'sd69099;   // MC1_1 PC_A
            9'd440: cf =  18'sd53740;   // MC1_1 PC_C
            9'd441: cf = -18'sd2636;   // MC1_1 GM_C_X
            9'd442: cf = -18'sd1145;   // MC1_1 GM_C_J
            9'd443: cf = -18'sd59;   // MC1_1 GM_C_H
            9'd444: cf =  18'sd77332;   // MC1_1 GM_C_F
            9'd448: cf =  18'sd40960;   // MC1_2 WA
            9'd450: cf =  18'sd90112;   // MC1_2 WD
            9'd451: cf =  18'sd43515;   // MC1_2 GA_X
            9'd452: cf =  18'sd14065;   // MC1_2 GA_J
            9'd453: cf =  18'sd967;   // MC1_2 GA_H
            9'd455: cf =  18'sd43515;   // MC1_2 HD_X
            9'd456: cf =  18'sd14065;   // MC1_2 HD_J
            9'd457: cf =  18'sd967;   // MC1_2 HD_H
            9'd459: cf =  18'sd115524;   // MC1_2 CM_A
            9'd460: cf = -18'sd4227;   // MC1_2 CM_C
            9'd461: cf =  18'sd3758;   // MC1_2 DM_X
            9'd462: cf =  18'sd1215;   // MC1_2 DM_J
            9'd463: cf =  18'sd84;   // MC1_2 DM_H
            9'd464: cf =  18'sd4227;   // MC1_2 DM_F
            9'd465: cf =  18'sd102387;   // MC1_2 PA_A
            9'd466: cf = -18'sd6937;   // MC1_2 PA_C
            9'd467: cf =  18'sd7220;   // MC1_2 GM_A_X
            9'd468: cf =  18'sd2334;   // MC1_2 GM_A_J
            9'd469: cf =  18'sd160;   // MC1_2 GM_A_H
            9'd470: cf =  18'sd6937;   // MC1_2 GM_A_F
            9'd471: cf = -18'sd69366;   // MC1_2 PC_A
            9'd472: cf =  18'sd53748;   // MC1_2 PC_C
            9'd473: cf = -18'sd2642;   // MC1_2 GM_C_X
            9'd474: cf = -18'sd854;   // MC1_2 GM_C_J
            9'd475: cf = -18'sd59;   // MC1_2 GM_C_H
            9'd476: cf =  18'sd77324;   // MC1_2 GM_C_F
            9'd480: cf =  18'sd20165;   // MC1_3 WA
            9'd481: cf =  18'sd66544;   // MC1_3 WC
            9'd482: cf =  18'sd44363;   // MC1_3 WD
            9'd483: cf =  18'sd39179;   // MC1_3 GA_X
            9'd484: cf =  18'sd25724;   // MC1_3 GA_J
            9'd485: cf =  18'sd871;   // MC1_3 GA_H
            9'd487: cf =  18'sd39179;   // MC1_3 HD_X
            9'd488: cf =  18'sd25724;   // MC1_3 HD_J
            9'd489: cf =  18'sd871;   // MC1_3 HD_H
            9'd491: cf =  18'sd114384;   // MC1_3 CM_A
            9'd492: cf = -18'sd4197;   // MC1_3 CM_C
            9'd493: cf =  18'sd3734;   // MC1_3 DM_X
            9'd494: cf =  18'sd2451;   // MC1_3 DM_J
            9'd495: cf =  18'sd83;   // MC1_3 DM_H
            9'd496: cf =  18'sd4197;   // MC1_3 DM_F
            9'd497: cf =  18'sd100298;   // MC1_3 PA_A
            9'd498: cf = -18'sd6857;   // MC1_3 PA_C
            9'd499: cf =  18'sd7149;   // MC1_3 GM_A_X
            9'd500: cf =  18'sd4694;   // MC1_3 GM_A_J
            9'd501: cf =  18'sd159;   // MC1_3 GM_A_H
            9'd502: cf =  18'sd6857;   // MC1_3 GM_A_F
            9'd503: cf = -18'sd68570;   // MC1_3 PC_A
            9'd504: cf =  18'sd53725;   // MC1_3 PC_C
            9'd505: cf = -18'sd2623;   // MC1_3 GM_C_X
            9'd506: cf = -18'sd1722;   // MC1_3 GM_C_J
            9'd507: cf = -18'sd58;   // MC1_3 GM_C_H
            9'd508: cf =  18'sd77347;   // MC1_3 GM_C_F
            // END gx_mix_coefs table
            default: cf = 18'sd0;
        endcase
    endfunction

    // ---- pitch-bit counts over the sample (ce_1m5 steps; a ce_1m5 on the ce_48k clock belongs to the old sample)
    reg  [5:0] na_c, nc_c, nd_c;      // running counts
    reg  [5:0] la, lc, ld;            // latched at ce_48k
    wire [5:0] na_n = na_c + {5'd0, ce_1m5 & qa};
    wire [5:0] nc_n = nc_c + {5'd0, ce_1m5 & qc};
    wire [5:0] nd_n = nd_c + {5'd0, ce_1m5 & qd};
    always @(posedge clk) begin
        if (reset) begin
            na_c <= 6'd0; nc_c <= 6'd0; nd_c <= 6'd0;
            la <= 6'd0; lc <= 6'd0; ld <= 6'd0;
        end else if (ce_48k) begin
            la <= na_n; lc <= nc_n; ld <= nd_n;
            na_c <= 6'd0; nc_c <= 6'd0; nd_c <= 6'd0;
        end else begin
            na_c <= na_n; nc_c <= nc_n; nd_c <= nd_n;
        end
    end

    // ---- per-sample sequence
    reg        [5:0]  st;             // 0 idle, 1..35 busy
    reg        [3:0]  sel;            // {board, vol2, vol1}
    reg               pre;            // this sample (or the next) is the pre-charge sample
    reg        [15:0] bg_s, fire_s, bp;
    reg signed [15:0] hit_s, sp_s;
    reg signed [33:0] racc;           // m x 2^17
    reg signed [26:0] ux, uj;         // X, J (Q6.20)
    reg signed [31:0] acc;            // y (Q.20); the DC node during the pre-charge
    reg signed [31:0] va, vc, na, nc, z;

    wire [1:0] board = kb ? 2'd2 : mc1 ? 2'd3 : mix_moon ? 2'd1 : 2'd0;
    wire       kb_s  = (sel[3:2] == 2'd2);
    wire signed [17:0] c_a46 = (sel[3:2] == 2'd0) ? MIX_A46_GAL : (sel[3:2] == 2'd1) ? MIX_A46_MCG :
                               (sel[3:2] == 2'd2) ? MIX_A46_KB : MIX_A46_MC1;
    wire signed [26:0] uh = {{3{hit_s[15]}}, hit_s, 8'd0};
    wire signed [26:0] uf = {3'd0, fire_s, 8'd0};
    wire signed [16:0] dbg = $signed({1'b0, bg_s}) - $signed({1'b0, bp});

    // step -> coefficient index (KEYS order) and operand
    reg        [4:0]  k;
    reg signed [26:0] ma;
    reg signed [17:0] mc;
    always @* begin
        k = 5'd0; ma = 27'sd0; mc = 18'sd0;
        case (st)
            6'd1:  begin ma = $signed({11'd0, pre ? bg_s : bp}); mc = MIX_KR0; end
            6'd2:  begin ma = {{10{dbg[16]}}, dbg}; mc = pre ? 18'sd0 : MIX_KR1; end
            6'd3:  begin k = 5'd0;  ma = $signed({4'd0, la, 17'd0}); end
            6'd4:  begin k = 5'd1;  ma = $signed({4'd0, lc, 17'd0}); end
            6'd5:  begin k = 5'd2;  ma = $signed({4'd0, ld, 17'd0}); end
            6'd6:  begin k = 5'd3;  ma = ux; end
            6'd7:  begin k = 5'd4;  ma = uj; end
            6'd8:  begin k = 5'd5;  ma = uh; end
            6'd9:  begin k = 5'd6;  ma = uf; end
            6'd10: begin k = 5'd7;  ma = ux; end
            6'd11: begin k = 5'd8;  ma = uj; end
            6'd12: begin k = 5'd9;  ma = uh; end
            6'd13: begin k = 5'd10; ma = uf; end
            6'd15: begin k = 5'd11; ma = va[26:0]; end
            6'd16: begin k = 5'd12; ma = vc[26:0]; end
            6'd17: begin k = 5'd13; ma = ux; end
            6'd18: begin k = 5'd14; ma = uj; end
            6'd19: begin k = 5'd15; ma = uh; end
            6'd20: begin k = 5'd16; ma = uf; end
            6'd21: begin k = 5'd17; ma = va[26:0]; end
            6'd22: begin k = 5'd18; ma = vc[26:0]; end
            6'd23: begin k = 5'd19; ma = ux; end
            6'd24: begin k = 5'd20; ma = uj; end
            6'd25: begin k = 5'd21; ma = uh; end
            6'd26: begin k = 5'd22; ma = uf; end
            6'd27: begin k = 5'd23; ma = va[26:0]; end
            6'd28: begin k = 5'd24; ma = vc[26:0]; end
            6'd29: begin k = 5'd25; ma = ux; end
            6'd30: begin k = 5'd26; ma = uj; end
            6'd31: begin k = 5'd27; ma = uh; end
            6'd32: begin k = 5'd28; ma = uf; end
            6'd33: begin k = 5'd29; ma = {{2{sp_s[15]}}, sp_s, 9'd0}; end
            6'd34: begin ma = acc[26:0] - z[26:0]; mc = c_a46; end
            default: ;
        endcase
        if (st >= 6'd3 && st <= 6'd33) mc = cf({sel, k});
    end
    wire signed [44:0] prod = ma * mc;
    wire signed [27:0] p17s = prod[44:17];
    wire signed [31:0] p17  = {{4{p17s[27]}}, p17s};
    wire signed [33:0] rr   = racc + 34'sd65536;            // round(m)
    wire signed [16:0] mr   = rr[33:17];
    wire        [6:0]  m    = mr[16] ? 7'd0 : (mr > 17'sd96) ? 7'd96 : mr[6:0];
    wire signed [31:0] y    = acc - z;
    wire signed [24:0] y7   = kb_s ? {y[31], y[31:8]} : y[31:7];

    always @(posedge clk) begin
        if (reset) begin
            st <= 6'd0; sel <= 4'd0; pre <= 1'b1;
            bg_s <= 16'd0; fire_s <= 16'd0; bp <= 16'd0; hit_s <= 16'sd0; sp_s <= 16'sd0;
            racc <= 34'sd0; ux <= 27'sd0; uj <= 27'sd0;
            acc <= 32'sd0; va <= 32'sd0; vc <= 32'sd0; na <= 32'sd0; nc <= 32'sd0; z <= 32'sd0; audio <= 16'sd0;
        end else if (ce_48k) begin
            st <= 6'd1; sel <= {board, vol2, vol1};
            bg_s <= bg; fire_s <= v_fire; hit_s <= (board == 2'd3) ? v_flash : v_hit; sp_s <= speech;
        end else if (st != 6'd0) begin
            st <= (st == 6'd35) ? 6'd0 : st + 6'd1;
            case (st)
                6'd1:  racc <= prod[33:0];
                6'd2:  racc <= racc + prod[33:0];
                6'd3:  begin ux <= $signed({5'd0, m, 15'd0}) + $signed({6'd0, m, 14'd0}); bp <= bg_s;
                             uj <= p17[26:0]; end                    // m x 3/64 V = m x 49152
                6'd4, 6'd5: uj <= uj + p17[26:0];
                6'd6:  na <= p17;
                6'd7, 6'd8, 6'd9: na <= na + p17;
                6'd10: acc <= p17;
                6'd11, 6'd12, 6'd13: acc <= acc + p17;
                6'd14: if (pre) begin va <= na; vc <= {{5{uf[26]}}, uf} - acc; end
                6'd15: acc <= p17;
                6'd16, 6'd17, 6'd18, 6'd19, 6'd20: acc <= acc + p17;
                6'd21: na <= p17;
                6'd22, 6'd23, 6'd24, 6'd25, 6'd26: na <= na + p17;
                6'd27: nc <= p17;
                6'd28, 6'd29, 6'd30, 6'd31, 6'd32: nc <= nc + p17;
                6'd33: begin if (kb_s) acc <= acc + p17; va <= na; vc <= nc; end
                6'd34: z <= pre ? acc : z + p17;
                6'd35: begin
                    audio <= (y7 > 25'sd32767) ? 16'sd32767 : (y7 < -25'sd32768) ? -16'sd32768 : y7[15:0];
                    pre <= 1'b0;
                end
                default: ;
            endcase
        end
    end

    wire unused_ok = &{1'b0, prod[16:0], y[6:0], rr[16:0], mr[15:7], va[31:27], vc[31:27]};
endmodule
`default_nettype wire
