/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        ibuf_mgmt.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives clp tlps.
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

module ibuf_mgmt # (
    parameter MX_OS_RQ = 4,
    // MISC
    parameter BW = 9
    ) (

    input                    clk,
    input                    rst,

    // TRN rx
    input        [63:0]      trn_rd,
    input        [7:0]       trn_rrem_n,
    input                    trn_rsof_n,
    input                    trn_reof_n,
    input                    trn_rsrc_rdy_n,
    input        [6:0]       trn_rbar_hit_n,

    // CFG
    input        [15:0]      cfg_completer_id,
    input        [2:0]       cfg_max_rd_req_size,

    // lbuf_mgmt
    input                    rd_lbuf1,
    input                    rd_lbuf2,
    input                    wt_lbuf1,
    input                    wt_lbuf2,

    input        [63:0]      lbuf_addr,
    input        [31:0]      lbuf_len,
    input                    lbuf_en,
    output reg               lbuf_dn,

    // ibuff2mac
    output reg   [BW:0]      committed_prod,

    // ibuff
    output       [BW-1:0]    wr_addr,
    output reg   [63:0]      wr_data,

    // gc
    output reg               cpl1_rcved,
    output reg               cpl2_rcved,
    output reg   [9:0]       cpl_dws,

    // mem_rd
    output reg   [63:0]      hst_addr,
    output reg               rd,
    output reg   [8:0]       rd_qw,
    input                    rd_ack,
    input        [4:0]       rd_tag,

    // dsc_mgmt
    output reg               dsc_rdy,
    input                    dsc_rdy_ack
    );

    `include "includes.v"
    // localparam
    localparam s0  = 15'b000000000000000;
    localparam s1  = 15'b000000000000001;
    localparam s2  = 15'b000000000000010;
    localparam s3  = 15'b000000000000100;
    localparam s4  = 15'b000000000001000;
    localparam s5  = 15'b000000000010000;
    localparam s6  = 15'b000000000100000;
    localparam s7  = 15'b000000001000000;
    localparam s8  = 15'b000000010000000;
    localparam s9  = 15'b000000100000000;
    localparam s10 = 15'b000001000000000;
    localparam s11 = 15'b000010000000000;
    localparam s12 = 15'b000100000000000;
    localparam s13 = 15'b001000000000000;
    localparam s14 = 15'b010000000000000;
    localparam s15 = 15'b100000000000000;

    //-------------------------------------------------------
    // Local rd_fsm
    //-------------------------------------------------------   
    reg          [14:0]      rd_fsm;
    reg          [63:0]      ntx_hst_addr;
    reg          [BW:0]      diff;
    reg          [31:0]      lbuf_len_reg;
    reg          [31:0]      qw_cnt;
    reg          [31:0]      nxt_qw_cnt;
    reg          [4:0]       os_req;
    reg          [4:0]       snt_rq;
    reg          [4:0]       cpl_rq;
    reg          [4:0]       nxt_snt_rq;
    reg          [2:0]       mx_rdrq_reg;
    reg                      rd256;
    reg                      rd512;
    reg                      rd1k;
    reg          [8:0]       mx_qw;
    reg          [8:0]       rd_qw_i;
    reg          [BW:0]      ax0_diff;
    reg          [BW:0]      ax1_diff;
    reg          [4:0]       rd_tag_reg;
    reg          [8:0]       rq_len[0:MX_OS_RQ-1];
    reg          [BW:0]      iprod;
    reg          [BW:0]      iprod_reg;
    reg          [BW:0]      nxt_iprod;
    reg                      rq2lbuf[0:MX_OS_RQ-1];

    ////////////////////////////////////////////////
    // rd_fsm
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            rd_fsm <= s0;
        end
        
        else begin  // not rst

            lbuf_dn <= 1'b0;

            qw_lft <= lbuf_len_reg + (~qw_cnt) + 1;
            os_req <= snt_rq + (~cpl_rq) + 1;

            ax0_diff <= diff + qw_lft;
            ax1_diff <= diff + mx_qw;

            mx_rdrq_reg <= cfg_max_rd_req_size;
            rd256 <= mx_rdrq_reg[0];
            rd512 <= mx_rdrq_reg[1];
            rd1k <= mx_rdrq_reg[2] | (& mx_rdrq_reg[1:0]);

            if (rd1k) begin
                mx_qw <= 'h80;
            end
            else if (rd512) begin
                mx_qw <= 'h40;
            end
            else if (rd256) begin
                mx_qw <= 'h20;
            end
            else begin
                mx_qw <= 'h10;
            end

            case (rd_fsm)

                s0 : begin
                    diff <= 'b0;
                    lbuf_dn <= 1'b0;
                    rd <= 1'b0;
                    dsc_rdy <= 1'b0;
                    snt_rq <= 'b0;
                    rd_fsm <= s1;
                end

                s1 : begin
                    hst_addr <= lbuf_addr;
                    lbuf_len_reg <= lbuf_len;
                    qw_cnt <= 'b0;
                    if (lbuf_en) begin
                        rd_fsm <= s2;
                    end
                end

                s2 : begin
                    // dealy for qw_cnt
                    if (os_req < MX_OS_RQ) begin
                        rd_fsm <= s3;
                    end
                end

                s3 : begin
                    nxt_snt_rq <= snt_rq + 1;
                    if (qw_lft > mx_qw) begin
                        rd_fsm <= s4;
                    end
                    else begin
                        rd_fsm <= s5;
                    end
                end

                s4 : begin
                    rd_qw_i <= mx_qw;
                    if (!ax1_diff[BW]) begin
                        rd <= 1'b1;
                        rd_fsm <= s6;
                    end
                end

                s5 : begin
                    rd_qw_i <= remaining_qwords;
                    if (!ax0_diff[BW]) begin
                        rd <= 1'b1;
                        rd_fsm <= s6;
                    end
                end

                s6 : begin
                    nxt_iprod <= iprod + rd_qw_i;
                    ntx_hst_addr <= hst_addr + {rd_qw_i, 3'b0};
                    nxt_qw_cnt <= qw_cnt + rd_qw_i;

                    iprod_reg <= iprod;
                    rq_len[rd_tag] <= rd_qw_i;
                    snt_rq <= nxt_snt_rq;

                    rd_tag_reg <= rd_tag;
                    if (rd_ack) begin
                        rd <= 1'b0;
                        rd_fsm <= s7;
                    end
                end

                s7 : begin
                    iprod <= nxt_iprod;
                    hst_addr <= ntx_hst_addr;
                    qw_cnt <= nxt_qw_cnt;

                    if (rd_lbuf1) begin
                        rq2lbuf[tlp_tag_sent] <= 1'b0;
                    end
                    else begin
                        tag_to_hp[tlp_tag_sent] <= hp2;
                    end
                    trigger_rd_tlp_fsm <= s7;
                end

                default : begin 
                    rd_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // ibuf_mgmt

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////