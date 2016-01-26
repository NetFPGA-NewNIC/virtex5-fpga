/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tlp2ibuf.v
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

module tlp2ibuf # (
    // HST NOTIFICATIONS
    parameter DSCW = 1,
    parameter DSC_CPL_MSG = 32'hCACABEEF,
    parameter DSC_BASE_QW = 0,
    parameter GC_BASE_QW = 1,
    // MISC
    parameter BW = 9,
    // RQ_TAG_BASE
    parameter RQTB = 5'b00000,
    // Outstanding request width
    parameter OSRW = 4
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

    // ibuf2bkd
    output       [BW:0]      committed_prod,
    input        [BW:0]      committed_cons,

    // ibuf
    output                   wr_en,
    output       [BW-1:0]    wr_addr,
    output       [63:0]      wr_data,

    // irq_gen
    output                   hw_ptr_update,
    output       [63:0]      hw_ptr,

    // EP arb
    input                    my_trn,
    output                   drv_ep,
    output                   req_ep
    );

    //-------------------------------------------------------
    // Local mem_rd
    //-------------------------------------------------------
    // ibuf_mgmt
    wire         [63:0]      hst_addr;
    wire                     rd;
    wire         [8:0]       rd_qw;
    wire                     rd_ack;
    wire         [OSRW-1:0]  rd_tag;
    // dsc_mgmt
    wire                     dsc_rdy;
    wire                     dsc_rdy_ack;

    //-------------------------------------------------------
    // Local gc_mxr
    //-------------------------------------------------------
    // gc updt 1
    wire         [63:0]      gc1_addr;
    wire                     gc1_updt;
    wire                     gc1_updt_ack;
    // gc updt 2
    wire         [63:0]      gc2_addr;
    wire                     gc2_updt;
    wire                     gc2_updt_ack;
    // gc updt
    wire         [63:0]      gc_addr;
    wire                     gc_updt;
    wire                     gc_updt_ack;

    //-------------------------------------------------------
    // Local ibuf_mgmt
    //-------------------------------------------------------
    // gc updt
    wire                     cpl1_rcved;
    wire                     cpl2_rcved;
    wire         [9:0]       cpl_dws;

    //-------------------------------------------------------
    // mem_rd
    //-------------------------------------------------------
    mem_rd #(
        .DSCW(DSCW),
        .DSC_CPL_MSG(DSC_CPL_MSG),
        .DSC_BASE_QW(DSC_BASE_QW),
        .GC_BASE_QW(GC_BASE_QW),
        // RQ_TAG_BASE
        .RQTB(RQTB),
        // Outstanding request width
        .OSRW(OSRW)
    ) mem_rd_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // TRN tx
        .trn_td(trn_td),                                       // O [63:0]
        .trn_trem_n(trn_trem_n),                               // O [7:0]
        .trn_tsof_n(trn_tsof_n),                               // O
        .trn_teof_n(trn_teof_n),                               // O
        .trn_tsrc_rdy_n(trn_tsrc_rdy_n),                       // O
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
        .rd_tag(rd_tag),                                       // O [OSRW-1:0]
        // dsc_mgmt
        .dsc_rdy(dsc_rdy),                                     // I
        .dsc_rdy_ack(dsc_rdy_ack),                             // O
        // gc_mgmt
        .gc_addr(gc_addr),                                     // I [63:0]
        .gc_updt(gc_updt),                                     // I
        .gc_updt_ack(gc_updt_ack),                             // O
        // irq_gen
        .hw_ptr_update(hw_ptr_update),                         // O
        .hw_ptr(hw_ptr),                                       // O [63:0]
        // EP arb
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep),                                       // O
        .req_ep(req_ep)                                        // O
        );

    //-------------------------------------------------------
    // ibuf_mgmt
    //-------------------------------------------------------
    ibuf_mgmt #(
        .BW(BW),
        // RQ_TAG_BASE
        .RQTB(RQTB),
        // Outstanding request width
        .OSRW(OSRW)
    ) ibuf_mgmt_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // CFG
        .cfg_max_rd_req_size(cfg_max_rd_req_size),             // I [2:0]
        // lbuf_mgmt
        .rd_lbuf1(rd_lbuf1),                                   // I
        .rd_lbuf2(rd_lbuf2),                                   // I
        .lbuf_addr(lbuf_addr),                                 // I [63:0]
        .lbuf_len(lbuf_len),                                   // I [31:0]
        .lbuf_en(lbuf_en),                                     // I
        .lbuf_dn(lbuf_dn),                                     // O
        // ibuf2bkd
        .committed_prod(committed_prod),                       // O [BW:0]
        .committed_cons(committed_cons),                       // I [BW:0]
        // ibuf
        .wr_en(wr_en),                                         // O
        .wr_addr(wr_addr),                                     // O [BW-1:0]
        .wr_data(wr_data),                                     // O [63:0]
        // gc
        .cpl1_rcved(cpl1_rcved),                               // O
        .cpl2_rcved(cpl2_rcved),                               // O
        .cpl_dws(cpl_dws),                                     // O [9:0]
        // mem_rd
        .hst_addr(hst_addr),                                   // O [63:0]
        .rd(rd),                                               // O
        .rd_qw(rd_qw),                                         // O [8:0]
        .rd_ack(rd_ack),                                       // I
        .rd_tag(rd_tag),                                       // I [OSRW-1:0]
        // dsc_mgmt
        .dsc_rdy(dsc_rdy),                                     // O
        .dsc_rdy_ack(dsc_rdy_ack)                              // I
        );

    //-------------------------------------------------------
    // gc_mxr
    //-------------------------------------------------------
    gc_mxr gc_mxr_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // gc updt 1
        .gc1_addr(gc1_addr),                                   // I [63:0]
        .gc1_updt(gc1_updt),                                   // I
        .gc1_updt_ack(gc1_updt_ack),                           // O
        // gc updt 2
        .gc2_addr(gc2_addr),                                   // I [63:0]
        .gc2_updt(gc2_updt),                                   // I
        .gc2_updt_ack(gc2_updt_ack),                           // O
        // gc updt
        .gc_addr(gc_addr),                                     // O [63:0]
        .gc_updt(gc_updt),                                     // O
        .gc_updt_ack(gc_updt_ack)                              // I
        );

    //-------------------------------------------------------
    // GC 1
    //-------------------------------------------------------
    gc gc1_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // lbuf_mgmt
        .rd_lbuf(rd_lbuf1),                                    // I
        .wt_lbuf(wt_lbuf1),                                    // O
        .lbuf_addr(lbuf_addr),                                 // I [63:0]
        .lbuf_len(lbuf_len),                                   // I [31:0]
        // ibuf_mgmt
        .cpl_rcved(cpl1_rcved),                                // I
        .cpl_dws(cpl_dws),                                     // I [9:0]
        // gc updt
        .gc_addr(gc1_addr),                                    // O [63:0]
        .gc_updt(gc1_updt),                                    // O
        .gc_updt_ack(gc1_updt_ack)                             // I
        );

    //-------------------------------------------------------
    // GC 2
    //-------------------------------------------------------
    gc gc2_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // lbuf_mgmt
        .rd_lbuf(rd_lbuf2),                                    // I
        .wt_lbuf(wt_lbuf2),                                    // O
        .lbuf_addr(lbuf_addr),                                 // I [63:0]
        .lbuf_len(lbuf_len),                                   // I [31:0]
        // ibuf_mgmt
        .cpl_rcved(cpl2_rcved),                                // I
        .cpl_dws(cpl_dws),                                     // I [9:0]
        // gc updt
        .gc_addr(gc2_addr),                                    // O [63:0]
        .gc_updt(gc2_updt),                                    // O
        .gc_updt_ack(gc2_updt_ack)                             // I
        );

endmodule // tlp2ibuf

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////