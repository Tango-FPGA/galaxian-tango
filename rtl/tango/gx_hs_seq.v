// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (c) 2026 the Tango authors
// gx_hs_seq.v -- the core reset sequencer that orders the hi-score restore.
// reset_out (the wrapper's game_reset, shared by gx_top and hiscore.v) is held from power-on until the first index-0
// download, then until no download has happened for QUIET clocks (SETTLE), so the game boots with its DIP word and
// hi-score dump in.  Any later download of an index other than 254 (DIP) and 255 (cheats) re-asserts it for the
// download plus STRETCH clocks, so hiscore.v sees a reset falling edge after a late dump; a new index-0 download
// returns to SETTLE.  por and sys_reset also assert it directly.  seq_state is the state (0 WAIT_ROM, 1 SETTLE,
// 2 RUN).
`default_nettype none
module gx_hs_seq #(
    parameter integer QUIET   = 16777216,
    parameter integer STRETCH = 16
) (
    input  wire       clk,
    input  wire       por,
    input  wire       sys_reset,
    input  wire       ioctl_download,
    input  wire [7:0] ioctl_index,
    output wire       reset_out,
    output wire [1:0] seq_state
);
    // State encoding
    localparam [1:0] WAIT_ROM = 2'd0,
                     SETTLE   = 2'd1,
                     RUN      = 2'd2;

    // Hold indices: all except 254 and 255
    wire hold_idx = (ioctl_index != 8'd254) & (ioctl_index != 8'd255);

    // Registers with initialisers matching reset values
    reg [1:0] state = WAIT_ROM;
    reg [31:0] qcnt = 32'd0;
    reg [31:0] scnt = 32'd0;

    // Reset and synchronous logic
    always @(posedge clk) begin
        if (por) begin
            state <= WAIT_ROM;
            qcnt  <= 32'd0;
            scnt  <= 32'd0;
        end else begin
            // scnt update: runs in every state
            if (ioctl_download & hold_idx) begin
                scnt <= STRETCH;
            end else if (scnt != 32'd0) begin
                scnt <= scnt - 32'd1;
            end

            // state and qcnt update
            case (state)
                WAIT_ROM: begin
                    if (ioctl_download & (ioctl_index == 8'd0)) begin
                        state <= SETTLE;
                        qcnt  <= 32'd0;
                    end
                end
                SETTLE: begin
                    if (ioctl_download) begin
                        qcnt <= 32'd0;
                    end else if (qcnt == QUIET-32'd1) begin
                        state <= RUN;
                    end else begin
                        qcnt <= qcnt + 32'd1;
                    end
                end
                RUN: begin
                    if (ioctl_download & (ioctl_index == 8'd0)) begin
                        state <= SETTLE;
                        qcnt  <= 32'd0;
                    end
                end
                default: begin
                    // No operation; preserve current state
                end
            endcase
        end
    end

    // Combinational outputs
    assign reset_out = por | sys_reset | (state != RUN) | (ioctl_download & hold_idx) | (scnt != 32'd0);
    assign seq_state = state;

endmodule
`default_nettype wire
