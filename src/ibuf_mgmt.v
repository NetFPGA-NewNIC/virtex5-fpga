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
    parameter MAX_TL_OS_RQ = 4,
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
    input        [2:0]       cfg_max_rd_req_size,

    // lbuf_mgmt
    input                    rd_lbuf1,
    input                    rd_lbuf2,

    input        [63:0]      lbuf_addr,
    input        [31:0]      lbuf_len,
    input                    lbuf_en,
    output reg               lbuf_dn,

    // ibuf2mac
    output reg   [BW:0]      committed_prod,
    input        [BW:0]      committed_cons,

    // ibuf
    output reg   [BW-1:0]    wr_addr,
    output reg   [63:0]      wr_data,

    // gc
    output reg               cpl1_rcved,
    output reg               cpl2_rcved,
    output reg   [9:0]       cpl_dws,

    // mem_rd
    output reg   [63:0]      hst_addr,
    output reg               rd,
    output       [8:0]       rd_qw,
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

    localparam LBF1ID = 2'b01;
    localparam LBF2ID = 2'b10;

    //-------------------------------------------------------
    // Local rd_fsm
    //-------------------------------------------------------   
    reg          [14:0]      rd_fsm;
    reg          [63:0]      ntx_hst_addr;
    reg          [BW:0]      diff;
    reg          [31:0]      lbuf_len_reg;
    reg          [31:0]      qw_cnt;
    reg          [31:0]      nxt_qw_cnt;
    reg          [31:0]      qw_lft;
    reg          [4:0]       os_req;
    reg          [4:0]       snt_rq;
    reg          [4:0]       nxt_snt_rq;
    reg          [2:0]       mx_rdrq_reg;
    reg                      rd256;
    reg                      rd512;
    reg                      rd1k;
    reg          [9:0]       mx_qw;
    reg          [9:0]       rd_qw_i;
    reg          [BW:0]      ax0_diff;
    reg          [BW:0]      ax1_diff;
    reg          [4:0]       rd_tag_reg;
    reg          [9:0]       rq_len[0:MAX_TL_OS_RQ-1];
    reg          [BW:0]      iprod;
    reg          [BW:0]      iprod_reg;
    reg          [BW:0]      nxt_iprod;
    reg          [1:0]       rq2lbuf[0:MAX_TL_OS_RQ-1];
    reg          [4:0]       trgt_tag_lkup[0:MX_OS_RQ-1];

    //-------------------------------------------------------
    // Local ftr_fsm
    //-------------------------------------------------------   
    reg          [14:0]      ftr_fsm;
    reg                      exp_tlp[0:MAX_TL_OS_RQ-1];
    integer                  i;
    reg                      cnsm;
    reg          [9:0]       tlp_len;
    reg          [4:0]       tlp_tag;

    //-------------------------------------------------------
    // Local wr2ibuf
    //-------------------------------------------------------   
    reg          [14:0]      wr_fsm;
    reg          [14:0]      commit_prod_fsm;
    reg          [4:0]       cpl_rq;
    reg          [4:0]       nxt_cpl_rq;
    reg          [63:0]      trn_rd_reg;
    reg                      trn_reof_n_reg;
    reg                      trn_rsrc_rdy_n_reg;
    reg          [4:0]       tlp_tag_reg;
    reg          [8:0]       tlp_len_qw;
    reg          [9:0]       tlp_len_dw;
    reg                      tlp_len_odd;
    reg          [9:0]       rcv_len[0:MAX_TL_OS_RQ-1];
    reg          [9:0]       nxt_rcv_len;
    reg          [BW-1:0]    ibuf_addr[0:MAX_TL_OS_RQ-1];
    reg          [BW-1:0]    nxt_ibuf_addr;
    reg          [BW:0]      nxt_wr_addr;
    reg          [BW:0]      nxt_wr_addr_p1;
    reg          [31:0]      saved_dw[0:MAX_TL_OS_RQ-1];
    reg                      saved_dw_en[0:MAX_TL_OS_RQ-1];
    reg          [31:0]      aux_dw;
    reg                      eo_cpl;
    reg          [4:0]       trgt_tag;
    integer                  j;
    reg                      data_ready[0:MAX_TL_OS_RQ-1];
    reg                      rq_dn;
    reg          [4:0]       tag_dn;

    //-------------------------------------------------------
    // Local ftr_fsm
    //-------------------------------------------------------   
    reg          [14:0]      gc_fsm;
    reg          [4:0]       gc_tlp_tag;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign rd_qw = rd_qw_i;

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

            diff <= iprod + (~committed_cons) + 1;
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
                    iprod <= 'b0;
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
                    rd_qw_i <= qw_lft;
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
                    trgt_tag_lkup[snt_rq] <= rd_tag;

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
                        rq2lbuf[rd_tag_reg] <= LBF1ID;
                    end
                    else begin
                        rq2lbuf[rd_tag_reg] <= LBF2ID;
                    end
                    rd_fsm <= s8;
                end

                s8 : begin
                    // dealy for qw_lft
                    rd_fsm <= s9;
                end

                s9 : begin
                    if (qw_lft) begin
                        rd_fsm <= s2;
                    end
                    else begin
                        lbuf_dn <= 1'b1;
                        dsc_rdy <= 1'b1;
                        rd_fsm <= s10;
                    end
                end

                s10 : begin
                    if (dsc_rdy_ack) begin
                        dsc_rdy <= 1'b0;
                        rd_fsm <= s1;
                    end
                end

                default : begin 
                    rd_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // ftr_fsm
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            ftr_fsm <= s0;
        end
        
        else begin  // not rst

            cnsm <= 1'b0;

            if (rd && rd_ack) begin
                exp_tlp[rd_tag_reg] <= 1'b1;
            end

            if (rq_dn) begin
                exp_tlp[tag_dn] <= 1'b0;
            end

            case (ftr_fsm)

                s0 : begin
                    for (i = 0; i < MAX_TL_OS_RQ-1; i=i+1) begin
                        exp_tlp[i] <= 1'b0;
                    end
                    ftr_fsm <= s1;
                end

                s1 : begin
                    tlp_len <= trn_rd[41:32];
                    if ((!trn_rsrc_rdy_n) && (!trn_rsof_n)) begin
                        if ((trn_rd[62:56] == `CPL_W_DATA_FMT_TYPE) && (trn_rd[15:13] == `SC)) begin
                            ftr_fsm <= s2;
                        end
                    end
                end

                s2 : begin
                    tlp_tag <= trn_rd[44:40];
                    if (!trn_rsrc_rdy_n) begin
                        cnsm <= exp_tlp[trn_rd[44:40]];
                        ftr_fsm <= s1;
                    end
                end

                default : begin 
                    ftr_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // wr2ibuf
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            commit_prod_fsm <= s0;
            wr_fsm <= s0;
        end
        
        else begin  // not rst

            eo_cpl <= 1'b0;
            rq_dn <= 1'b0;

            trn_rd_reg <= trn_rd;
            trn_reof_n_reg <= trn_reof_n;
            trn_rsrc_rdy_n_reg <= trn_rsrc_rdy_n;

            if (rd && rd_ack) begin
                ibuf_addr[rd_tag] <= iprod_reg;
                rcv_len[rd_tag] <= 'b0;
                saved_dw_en[rd_tag] <= 1'b0;
            end

            nxt_cpl_rq <= cpl_rq + 1;
            trgt_tag <= trgt_tag_lkup[cpl_rq];
            case (commit_prod_fsm)

                s0 : begin
                    cpl_rq <= 'b0;
                    trgt_tag <= 'b0;
                    committed_prod <= 'b0;
                    for (j = 0; j < MAX_TL_OS_RQ-1; j=j+1) begin
                        data_ready[j] <= 1'b0;
                    end
                    commit_prod_fsm <= s1;
                end

                s1 : commit_prod_fsm <= s2; // delay for trgt_tag

                s2 : begin
                    if (data_ready[trgt_tag]) begin
                        committed_prod <= ibuf_addr[trgt_tag];
                    end
                    if ((rcv_len[trgt_tag] == rq_len[trgt_tag]) && data_ready[trgt_tag]) begin
                        commit_prod_fsm <= s3;
                    end
                end

                s3 : begin
                    cpl_rq <= nxt_cpl_rq;
                    data_ready[trgt_tag] <= 1'b0;
                    rq_dn <= 1'b1;
                    tag_dn <= trgt_tag;
                    commit_prod_fsm <= s1;
                end

                default : begin
                    commit_prod_fsm <= s0;
                end

            endcase

            case (wr_fsm)

                s0 : begin
                    wr_fsm <= s1;
                end

                s1 : begin
                    tlp_len_qw <= tlp_len[9:1];
                    tlp_len_dw <= tlp_len;
                    tlp_len_odd <= tlp_len[0];
                    tlp_tag_reg <= tlp_tag;
                    if (cnsm) begin
                        wr_fsm <= s2;
                    end
                end

                s2 : begin
                    nxt_ibuf_addr <= ibuf_addr[tlp_tag_reg] + tlp_len_qw;
                    nxt_rcv_len <= rcv_len[tlp_tag_reg] + tlp_len_qw;

                    data_ready[tlp_tag_reg] <= 1'b0;

                    nxt_wr_addr <= ibuf_addr[tlp_tag_reg];
                    nxt_wr_addr_p1 <= ibuf_addr[tlp_tag_reg] + 1;

                    wr_addr <= ibuf_addr[tlp_tag_reg];
                    wr_data[63:32] <= dw_endian_conv(trn_rd_reg[31:0]);
                    wr_data[31:0] <= saved_dw[tlp_tag_reg];

                    aux_dw <= trn_rd_reg[31:0];
                    if (!trn_rsrc_rdy_n_reg) begin
                        case ({saved_dw_en[tlp_tag_reg], tlp_len_odd})                    // my deco
                            2'b00 : begin   // P -> P
                                wr_fsm <= s3;
                            end
                            2'b01 : begin   // P -> I
                                wr_fsm <= s4;
                            end
                            2'b10 : begin   // I -> P
                                wr_fsm <= s5;
                            end
                            2'b11 : begin   // I -> I
                                wr_fsm <= s6;
                            end
                        endcase
                    end
                end

                s3 : begin   // P -> P
                    ibuf_addr[tlp_tag_reg] <= nxt_ibuf_addr;
                    rcv_len[tlp_tag_reg] <= nxt_rcv_len;
                    saved_dw_en[tlp_tag_reg] <= 1'b0;

                    wr_addr <= nxt_wr_addr;
                    wr_data[63:32] <= dw_endian_conv(trn_rd_reg[63:32]);
                    wr_data[31:0] <= dw_endian_conv(aux_dw);
                    if (!trn_rsrc_rdy_n_reg) begin
                        nxt_wr_addr <= nxt_wr_addr + 1;
                        aux_dw <= trn_rd_reg[31:0];
                        if (!trn_reof_n_reg) begin
                            eo_cpl <= 1'b1;
                            data_ready[tlp_tag_reg] <= 1'b1;
                            wr_fsm <= s1;
                        end
                    end
                end

                s4 : begin   // P -> I
                    ibuf_addr[tlp_tag_reg] <= nxt_ibuf_addr;
                    rcv_len[tlp_tag_reg] <= nxt_rcv_len;

                    saved_dw[tlp_tag_reg] <= dw_endian_conv(trn_rd[31:0]);
                    saved_dw_en[tlp_tag_reg] <= 1'b1;

                    wr_addr <= nxt_wr_addr;
                    wr_data[63:32] <= dw_endian_conv(trn_rd_reg[63:32]);
                    wr_data[31:0] <= dw_endian_conv(aux_dw);
                    if (!trn_rsrc_rdy_n_reg) begin
                        nxt_wr_addr <= nxt_wr_addr + 1;
                        aux_dw <= trn_rd_reg[31:0];
                        if (!trn_reof_n_reg) begin
                            eo_cpl <= 1'b1;
                            data_ready[tlp_tag_reg] <= 1'b1;
                            wr_fsm <= s1;
                        end
                    end
                end

                s5 : begin   // I -> P
                    ibuf_addr[tlp_tag_reg] <= nxt_ibuf_addr;
                    rcv_len[tlp_tag_reg] <= nxt_rcv_len;

                    saved_dw[tlp_tag_reg] <= dw_endian_conv(trn_rd[63:31]);
                    saved_dw_en[tlp_tag_reg] <= 1'b1;

                    wr_addr <= nxt_wr_addr_p1;
                    wr_data <= qw_endian_conv(trn_rd_reg);
                    if (!trn_rsrc_rdy_n_reg) begin
                        nxt_wr_addr_p1 <= nxt_wr_addr_p1 + 1;
                        if (!trn_reof_n_reg) begin
                            eo_cpl <= 1'b1;
                            data_ready[tlp_tag_reg] <= 1'b1;
                            wr_fsm <= s1;
                        end
                    end
                end

                s6 : begin   // I -> I
                    ibuf_addr[tlp_tag_reg] <= nxt_ibuf_addr + 1;
                    rcv_len[tlp_tag_reg] <= nxt_rcv_len + 1;
                    saved_dw_en[tlp_tag_reg] <= 1'b1;

                    wr_addr <= nxt_wr_addr_p1;
                    wr_data <= qw_endian_conv(trn_rd_reg);
                    if (!trn_rsrc_rdy_n_reg) begin
                        nxt_wr_addr_p1 <= nxt_wr_addr_p1 + 1;
                        if (!trn_reof_n_reg) begin
                            eo_cpl <= 1'b1;
                            data_ready[tlp_tag_reg] <= 1'b1;
                            wr_fsm <= s1;
                        end
                    end
                end

                default : begin 
                    wr_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // gc_fsm
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            gc_fsm <= s0;
        end
        
        else begin  // not rst

            cpl1_rcved <= 1'b0;
            cpl2_rcved <= 1'b0;

            case (gc_fsm)

                s0 : begin
                    gc_fsm <= s1;
                end

                s1 : begin
                    cpl_dws <= tlp_len_dw;
                    gc_tlp_tag <= tlp_tag_reg;
                    if (eo_cpl) begin
                        gc_fsm <= s2;
                    end
                end

                s2 : begin
                    case (rq2lbuf[gc_tlp_tag])
                        LBF1ID : cpl1_rcved <= 1'b1;
                        LBF2ID : cpl2_rcved <= 1'b1;
                    endcase
                    gc_fsm <= s1;
                end

                default : begin 
                    gc_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // ibuf_mgmt

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////