// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_snd_fire.v -- FIRE sound (Galaxian manual p.22 zones 14-15: 8L 7400, R47 / C28 envelope, R46 / R48 / C29 CV
// network, 7S 555 with R44 / R45 / C27, R90 / D2 into C25, 7R 4066, R41, LM324 7T buffer), as a fixed-point logic
// model.  Topology per MAME galaxian_a.cpp:428-450, with the schematic's R90 1K charge path, C29 and the 555's
// internal 5K / 5K / 5K divider loading pin 5, which MAME leaves out.
// Constants: tools/gx_snd_coefs.py (--check verifies this file).  Voltages Q4.24; every product >>> 28.
//
// One shared multiplier, sequenced in the clocks after each ce_1m5; fire / noise sampled at ce_1m5.
`default_nettype none
module gx_snd_fire (
    input  wire        clk,
    input  wire        reset,
    input  wire        ce_1m5,
    input  wire        ce_48k,
    input  wire        fire,
    input  wire        noise,
    output wire [15:0] v_fire
);

// --------------------------------------------------
// Local parameter constants (decimal)
// --------------------------------------------------
localparam signed [31:0] V5        = 83886080;
localparam signed [31:0] U_DIODE   = 55364813;
localparam signed [31:0] FIRE_A28  = 54080;
localparam signed [31:0] FIRE_VENV = 67108864;
localparam signed [31:0] FIRE_KE   = 142784817;
localparam signed [31:0] FIRE_CVB  = 19632912;
localparam signed [31:0] FIRE_NT   = 7853165;
localparam signed [31:0] FIRE_A29  = 14526432;
localparam signed [31:0] FIRE_ACH  = 545584;
localparam signed [31:0] FIRE_ADIS = 793200;
localparam signed [31:0] FIRE_A25C = 174704;
localparam signed [31:0] FIRE_A25D = 1748;
localparam signed [31:0] CVE_RESET = 55329116;

// --------------------------------------------------
// Registers - power-up values as specified
// --------------------------------------------------
reg  [5:0]  ph      = 6'd0;              // slot marker
reg  [0:0]  fire_s  = 1'b0;              // sampled fire
reg  [0:0]  noise_s = 1'b0;              // sampled noise
reg  [0:0]  req     = 1'b0;              // 48kHz request pending
reg  [0:0]  srv     = 1'b0;              // request served flag
reg signed [31:0] e      = FIRE_VENV;     // envelope
reg signed [31:0] cve    = CVE_RESET;    // CV target
reg signed [31:0] cv     = CVE_RESET;    // envelope capacitor node
reg signed [31:0] vc     = 32'sd0;        // 555 capacitor
reg  [0:0]  q       = 1'b0;              // 555 output
reg signed [31:0] v25    = 32'sd0;        // C25 voltage
reg  [31:0] acc      = 32'd0;            // accumulator
reg  [15:0] vout     = 16'd0;            // output register

// --------------------------------------------------
// Combinational signals
// --------------------------------------------------
wire signed [31:0] cvt = cve + (noise_s ? FIRE_NT : 32'd0);
wire signed [31:0] u   = fire_s ? U_DIODE : 32'd0;
wire signed [31:0] et  = fire_s ? 32'd0 : FIRE_VENV;

// --------------------------------------------------
// Multiplier logic - single shared multiplier
// --------------------------------------------------
reg signed [31:0] mx32;
reg signed [31:0] my32;
always @* begin
    mx32 = 32'd0;
    my32 = 32'd0;
    if (ph[0]) begin
        mx32 = cvt - cv;
        my32 = FIRE_A29;
    end else if (ph[1]) begin
        if (q) begin
            mx32 = V5 - vc;
            my32 = FIRE_ACH;
        end else begin
            mx32 = vc;
            my32 = FIRE_ADIS;
        end
    end else if (ph[2]) begin
        mx32 = u - v25;
        my32 = FIRE_A25C;
    end else if (ph[3]) begin
        mx32 = v25;
        my32 = FIRE_A25D;
    end else if (ph[4]) begin
        mx32 = et - e;
        my32 = FIRE_A28;
    end else begin
        mx32 = e;
        my32 = FIRE_KE;
    end
end
wire signed [56:0] prod = $signed(mx32[27:0]) * $signed({1'b0, my32[27:0]});
wire signed [31:0] p32  = {{3{prod[56]}}, prod[56:28]};

// --------------------------------------------------
// Unused product bits sink to silence Verilator
// --------------------------------------------------
wire unused = &{1'b0, prod[27:0], mx32[31:28], my32[31:28]};

// --------------------------------------------------
// Output assignment
// --------------------------------------------------
assign v_fire = vout;

// --------------------------------------------------
// Main state machine - synchronous logic on clk
// --------------------------------------------------
always @(posedge clk) begin
    if (reset) begin
        ph      <= 6'd0;
        fire_s  <= 1'b0;
        noise_s <= 1'b0;
        req     <= 1'b0;
        srv     <= 1'b0;
        e       <= FIRE_VENV;
        cve     <= CVE_RESET;
        cv      <= CVE_RESET;
        vc      <= 32'sd0;
        q       <= 1'b0;
        v25     <= 32'sd0;
        acc     <= 32'd0;
        vout    <= 16'd0;
    end else begin
        // phase and sampled inputs
        ph      <= {ph[4:0], ce_1m5};
        fire_s  <= ce_1m5 ? fire : fire_s;
        noise_s <= ce_1m5 ? noise : noise_s;
        // request logic
        req <= ce_48k ? 1'b1 : ((ph[4] && req) ? 1'b0 : req);
        // service flag
        srv <= ph[4] ? req : srv;
        // slot 0 - envelope capacitor
        if (ph[0]) cv <= cv + p32;
        // slot 1 - 555 capacitor and output
        if (ph[1]) begin
            if (q) begin
                vc <= vc + p32;
                q  <= (vc + p32 >= cv) ? 1'b0 : 1'b1;
            end else begin
                vc <= vc - p32;
                q  <= (vc - p32 <= (cv >>> 1)) ? 1'b1 : 1'b0;
            end
        end
        // slot 2 - C25 charge (guarded)
        if (ph[2] && u > v25) v25 <= v25 + p32;
        // slot 3 - C25 discharge and accumulator (guarded)
        if (ph[3] && q) begin
            v25 <= v25 - p32;
            acc <= acc + $unsigned(v25 - p32);
        end
        // slot 4 - envelope, output and accumulator reset (guarded by req)
        if (ph[4] && req) begin
            e    <= e + p32;
            vout <= {1'b0, acc[31:17]};
            acc  <= 32'd0;
        end
        // slot 5 - CV target update (guarded by srv)
        if (ph[5] && srv) begin
            cve <= p32 + FIRE_CVB;
        end
    end
end

endmodule
`default_nettype wire
