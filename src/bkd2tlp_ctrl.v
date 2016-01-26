/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        bkd2tlp_ctrl.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        When enough (good) data is in the internal buffer, a TLP is sent.
*        Backend packet boundaries are not taken in consideration.
*
*
*    This code is initially developed for the Network-as-a-Service (NaaS) project.
*
*  Copyright notice:
*        Copyright (C) 2014 University of Cambridge
*
*  Licence:
*        This file is part of the NetFPGA 10G development base package.
*
*        This file is free code: you can redistribute it and/or modify it under
*        the terms of the GNU Lesser General Public License version 2.1 as
*        published by the Free Software Foundation.
*
*        This package is distributed in the hope that it will be useful, but
*        WITHOUT ANY WARRANTY; without even the implied warranty of
*        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
*        Lesser General Public License for more details.
*
*        You should have received a copy of the GNU Lesser General Public
*        License along with the NetFPGA source package.  If not, see
*        http://www.gnu.org/licenses/.
*
*/

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps
//`default_nettype none

module bkd2tlp_ctrl # (
    parameter BW = 10
    ) (

    input                    clk,
    input                    rst,

    // CFG
    input        [2:0]       cfg_max_payload_size,

    // bkd2ibuf
    input        [BW:0]      committed_prod,
    input                    bkd_activity,

    // bkd2tlp_ctrl
    output reg               trig_tlp,
    input                    trig_tlp_ack,
    output reg               chng_lbuf,
    input                    chng_lbuf_ack,
    output reg               send_qws,
    input                    send_qws_ack,
    output reg   [5:0]       qw_cnt
    );

    // localparam
    localparam s0  = 18'b000000000000000000;
    localparam s1  = 18'b000000000000000001;
    localparam s2  = 18'b000000000000000010;
    localparam s3  = 18'b000000000000000100;
    localparam s4  = 18'b000000000000001000;
    localparam s5  = 18'b000000000000010000;
    localparam s6  = 18'b000000000000100000;
    localparam s7  = 18'b000000000001000000;
    localparam s8  = 18'b000000000010000000;
    localparam s9  = 18'b000000000100000000;
    localparam s10 = 18'b000000001000000000;
    localparam s11 = 18'b000000010000000000;
    localparam s12 = 18'b000000100000000000;
    localparam s13 = 18'b000001000000000000;
    localparam s14 = 18'b000010000000000000;
    localparam s15 = 18'b000100000000000000;
    localparam s16 = 18'b001000000000000000;
    localparam s17 = 18'b010000000000000000;
    localparam s18 = 18'b100000000000000000;

    //-------------------------------------------------------
    // Local timeout-generation
    //-------------------------------------------------------
    reg          [5:0]       free_running;
    reg                      timeout;
    reg                      bkd_activity_reg0;
    reg                      bkd_activity_reg1;

    //-------------------------------------------------------
    // Local trigger-logic
    //-------------------------------------------------------
    reg          [17:0]      trigger_fsm;
    reg          [BW:0]      diff;
    reg          [BW:0]      diff_reg;
    reg          [BW:0]      cons_i;
    reg          [BW:0]      nxt_cons_i;
    reg                      huge_page_dirty;
    reg          [18:0]      lbuf_qw_offst;
    reg          [18:0]      nxt_lbuf_qw_offst;
    reg          [18:0]      eolbuf_chk;
    reg          [3:0]       qw_lft;
    reg          [BW-4:0]    tlp_snt;
    reg          [BW-4:0]    nxt_tlp_snt128;
    reg          [BW-4:0]    nxt_tlp_snt256;
    reg          [BW-4:0]    tlp2snd;
    reg          [BW-3:0]    diff_tlp;
    reg                      rx_idle;
    reg                      double_inc;
    reg                      mx256;
    reg          [2:0]       cfg_max_payload_size_reg;

    ////////////////////////////////////////////////
    // timeout logic
    ////////////////////////////////////////////////
    always @(posedge clk) begin
        if (rst) begin  // rst
        end
        
        else begin  // not rst

            bkd_activity_reg0 <= bkd_activity;
            bkd_activity_reg1 <= bkd_activity_reg0;

            if (rx_idle && !bkd_activity_reg1) begin
                free_running <= free_running +1;
                if (free_running == 'h3F) begin
                    timeout <= 1'b1;
                end
            end
            else begin
                timeout <= 1'b0;
                free_running <= 'b0;
            end

        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // trigger-logic
    ////////////////////////////////////////////////
    always @(posedge clk) begin
        
        if (rst) begin  // rst
            trigger_fsm <= s0;
        end

        else begin  // not rst

            rx_idle <= 1'b0;

            diff <= committed_prod + (~cons_i) +1;
            diff_tlp <= tlp2snd + (~tlp_snt) +1;

            cfg_max_payload_size_reg <= cfg_max_payload_size;
            mx256 <= | cfg_max_payload_size_reg;
            
            case (trigger_fsm)

                s0 : begin
                    trig_tlp <= 1'b0;
                    chng_lbuf <= 1'b0;
                    send_qws <= 1'b0;
                    diff <= 'b0;
                    cons_i <= 'b0;
                    lbuf_qw_offst <= 'h10;
                    huge_page_dirty <= 1'b0;
                    qw_lft <= 'b0;
                    trigger_fsm <= s1;
                end

                s1 : begin
                    rx_idle <= 1'b1;
                    eolbuf_chk <= lbuf_qw_offst + diff;
                    diff_reg <= diff;
                    tlp2snd <= diff[BW:4];
                    double_inc <= 1'b0;

                    if (diff >= 'h10) begin
                        trigger_fsm <= s2;
                    end
                    else if ((huge_page_dirty) && (timeout)) begin
                        trigger_fsm <= s13;
                    end
                    else if ((diff) && (timeout)) begin
                        trigger_fsm <= s18;
                    end
                end

                s2 : begin
                    huge_page_dirty <= 1'b1;
                    tlp_snt <= 'b0;
                    qw_cnt <= 'h10;
                    if (eolbuf_chk[18]) begin       // 2MB
                        trigger_fsm <= s8;
                    end
                    else begin
                        trig_tlp <= 1'b1;
                        qw_lft <= diff_reg[3:0];
                        trigger_fsm <= s3;
                    end
                end

                s3 : begin
                    nxt_cons_i <= cons_i + qw_cnt;
                    nxt_tlp_snt128 <= tlp_snt +1;
                    nxt_tlp_snt256 <= tlp_snt +2;
                    nxt_lbuf_qw_offst <= lbuf_qw_offst + qw_cnt;
                    if (trig_tlp_ack) begin
                        trig_tlp <= 1'b0;
                        trigger_fsm <= s4;
                    end
                end

                s4 : begin
                    cons_i <= nxt_cons_i;
                    tlp_snt <= double_inc ? nxt_tlp_snt256 : nxt_tlp_snt128;
                    lbuf_qw_offst <= nxt_lbuf_qw_offst;
                    trigger_fsm <= s5;
                end

                s5 : begin
                    //delay: diff_tlp
                    if (mx256 && (lbuf_qw_offst[8:4] != 5'h1F)) begin                 // not the last in a 4kpage
                        trigger_fsm <= s6;
                    end
                    else begin
                        trigger_fsm <= s7;
                    end
                end

                s6 : begin
                    qw_cnt <= 'h20;
                    double_inc <= 1'b1;
                    if (diff_tlp > 'h1) begin
                        trig_tlp <= 1'b1;
                        trigger_fsm <= s3;
                    end
                    else begin
                        trigger_fsm <= s7;
                    end
                end

                s7 : begin
                    double_inc <= 1'b0;
                    qw_cnt <= 'h10;
                    if (diff_tlp) begin
                        trig_tlp <= 1'b1;
                        trigger_fsm <= s3;
                    end
                    else begin
                        trigger_fsm <= s1;
                    end
                end

                s8 : begin
                    if (!qw_lft) begin
                        chng_lbuf <= 1'b1;
                        trigger_fsm <= s9;
                    end
                    else begin
                        qw_cnt <= {2'b0, qw_lft};
                        trig_tlp <= 1'b1;
                        trigger_fsm <= s10;
                    end
                end

                s9 : begin
                    huge_page_dirty <= 1'b0;
                    lbuf_qw_offst <= 'h10;
                    if (chng_lbuf_ack) begin
                        chng_lbuf <= 1'b0;
                        trigger_fsm <= s1;
                    end
                end

                s10 : begin
                    nxt_cons_i <= cons_i + qw_cnt;
                    if (trig_tlp_ack) begin
                        trig_tlp <= 1'b0;
                        chng_lbuf <= 1'b1;
                        trigger_fsm <= s11;
                    end
                end

                s11 : begin
                    cons_i <= nxt_cons_i;
                    lbuf_qw_offst <= 'h10;
                    qw_lft <= 'b0;
                    huge_page_dirty <= 1'b0;
                    if (chng_lbuf_ack) begin
                        chng_lbuf <= 1'b0;
                        trigger_fsm <= s12;
                    end
                end

                s12 : begin
                    // delay: diff
                    trigger_fsm <= s1;
                end

                s13 : begin
                    if (!qw_lft) begin
                        send_qws <= 1'b1;
                        trigger_fsm <= s14;
                    end
                    else begin
                        trigger_fsm <= s15;
                    end
                end

                s14 : begin
                    huge_page_dirty <= 1'b0;
                    if (send_qws_ack) begin
                        send_qws <= 1'b0;
                        trigger_fsm <= s1;
                    end
                end

                s15 : begin
                    nxt_lbuf_qw_offst <= lbuf_qw_offst + 'h10;
                    qw_cnt <= {2'b0, qw_lft};
                    trig_tlp <= 1'b1;
                    if (lbuf_qw_offst[17:4] == 'h3FFF) begin      // the last in the 2MB hp
                        trigger_fsm <= s10;
                    end
                    else begin
                        trigger_fsm <= s16;
                    end
                end

                s16 : begin
                    nxt_cons_i <= cons_i + qw_cnt;
                    if (trig_tlp_ack) begin
                        trig_tlp <= 1'b0;
                        send_qws <= 1'b1;
                        trigger_fsm <= s17;
                    end
                end

                s17 : begin
                    cons_i <= nxt_cons_i;
                    lbuf_qw_offst <= nxt_lbuf_qw_offst;
                    qw_lft <= 'b0;
                    huge_page_dirty <= 1'b0;
                    if (send_qws_ack) begin
                        send_qws <= 1'b0;
                        trigger_fsm <= s12;
                    end
                end

                s18 : begin
                    nxt_lbuf_qw_offst <= lbuf_qw_offst + 'h10;
                    qw_cnt <= diff_reg;
                    trig_tlp <= 1'b1;
                    if (lbuf_qw_offst[17:4] == 'h3FFF) begin      // the last in the 2MB hp
                        trigger_fsm <= s10;
                    end
                    else begin
                        trigger_fsm <= s16;
                    end
                end

                default : begin
                    trigger_fsm <= s0;
                end

            endcase

        end     // not rst
    end  //always

endmodule // bkd2tlp_ctrl

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////