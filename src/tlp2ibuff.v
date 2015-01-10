/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tlp2ibuff.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects tx circuitry
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

module tlp2ibuff # (
    // HST NOTIFICATIONS
    parameter DSCW = 1,
    parameter DSC_CPL_MSG = 32'hCACABEEF,
    parameter DSC_BASE_QW = 0,
    parameter GC_BASE_QW = 1,
    // MISC
    parameter BW = 9
    ) (

    input                    clk,
    input                    rst,

    // TRN tx
    output       [63:0]      trn_td,
    output       [7:0]       trn_trem_n,
    output                   trn_tsof_n,
    output                   trn_teof_n,
    output                   trn_tsrc_rdy_n,
    input                    trn_tdst_rdy_n,
    input        [3:0]       trn_tbuf_av,

    // TRN rx
    input        [63:0]      trn_rd,
    input        [7:0]       trn_rrem_n,
    input                    trn_rsof_n,
    input                    trn_reof_n,
    input                    trn_rsrc_rdy_n,
    input                    trn_rerrfwd_n,
    input        [6:0]       trn_rbar_hit_n,

    // CFG
    input        [15:0]      cfg_completer_id,
    input        [2:0]       cfg_max_rd_req_size,

    // lbuf_mgmt
    input        [63:0]      cpl_addr,
    input                    rd_lbuf1,
    input                    rd_lbuf2,
    output                   wt_lbuf1,
    output                   wt_lbuf2,

    input        [63:0]      lbuf_addr,
    input        [31:0]      lbuf_len,
    input                    lbuf_en,
    input                    lbuf64b,
    output                   lbuf_dn,

    // ibuff2mac
    output       [BW:0]      committed_prod,

    // ibuff
    output       [BW-1:0]    wr_addr,
    output       [63:0]      wr_data,

    // irq_gen
    output       [63:0]      hw_ptr,

    // EP arb
    input        [4:0]       tag_trn,
    output                   tag_inc,
    input                    my_trn,
    output                   drv_ep
    );

    //-------------------------------------------------------
    // Local mem_rd
    //-------------------------------------------------------
    // ibuf_mgmt
    wire         [63:0]      hst_addr;
    wire                     rd;
    wire         [8:0]       rd_qw;
    wire                     rd_ack;
    wire         [4:0]       rd_tag;
    // dsc_mgmt
    wire                     dsc_rdy;
    wire                     dsc_rdy_ack;
    // gc_mgmt
    wire         [63:0]      gc_addr;
    wire                     gc_updt;
    wire                     gc_updt_ack;

    //-------------------------------------------------------
    // mem_rd
    //-------------------------------------------------------
    mem_rd #(
        .DSCW(DSCW),
        .DSC_CPL_MSG(DSC_CPL_MSG),
        .DSC_BASE_QW(DSC_BASE_QW),
        .GC_BASE_QW(GC_BASE_QW)
    ) mem_rd_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // TRN tx
        .trn_td(rx_trn_td),                                    // O [63:0]
        .trn_trem_n(rx_trn_trem_n),                            // O [7:0]
        .trn_tsof_n(rx_trn_tsof_n),                            // O
        .trn_teof_n(rx_trn_teof_n),                            // O
        .trn_tsrc_rdy_n(rx_trn_tsrc_rdy_n),                    // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n),                       // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        // CFG
        .cfg_completer_id(cfg_completer_id),                   // I [15:0]
        // lbuf_mgmt
        .cpl_addr(cpl_addr),                                   // I [63:0]
        .lbuf64b(lbuf64b),                                     // I
        // ibuf_mgmt
        .hst_addr(hst_addr),                                   // I [63:0]
        .rd(rd),                                               // I
        .rd_qw(rd_qw),                                         // I [8:0]
        .rd_ack(rd_ack),                                       // O
        .rd_tag(rd_tag),                                       // O [4:0]
        // dsc_mgmt
        .dsc_rdy(dsc_rdy),                                     // I
        .dsc_rdy_ack(dsc_rdy_ack),                             // O
        // gc_mgmt
        .gc_addr(gc_addr),                                     // I [63:0]
        .gc_updt(gc_updt),                                     // I
        .gc_updt_ack(gc_updt_ack),                             // O
        .hw_ptr(hw_ptr),                                       // O [63:0]
        // EP arb
        .tag_trn(tag_trn),                                     // I [4:0]
        .tag_inc(tag_inc),                                     // O
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep)                                        // O
        );

endmodule // tlp2ibuff

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////