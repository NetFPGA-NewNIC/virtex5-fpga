/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects tx
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

module tx # (
    // BAR MAPPING
    parameter BARHIT = 2,
    parameter BARMP_CPL_ADDR = 6'b111111,
    parameter BARMP_LBUF1_ADDR = 6'b111111,
    parameter BARMP_LBUF1_EN = 6'b111111,
    parameter BARMP_LBUF2_ADDR = 6'b111111,
    parameter BARMP_LBUF2_EN = 6'b111111,
    parameter BARMP_CPL_BUFF = 6'b111111,
    parameter BARMP_WRBCK = 6'b111111,
    // MISC
    parameter BW = 9
    ) (

    input                    mac_clk,
    input                    mac_rst,

    input                    pcie_clk,
    input                    pcie_rst,

    // MAC tx
    output                   mac_tx_underrun,
    output       [63:0]      mac_tx_data,
    output       [7:0]       mac_tx_data_valid,
    output                   mac_tx_start,
    input                    mac_tx_ack,

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
    output                   send_irq,

    // EP arb
    input        [4:0]       tag_trn,
    output                   tag_inc,
    input                    my_trn,
    output                   drv_ep,
    output                   req_ep
    );

    //-------------------------------------------------------
    // Local ibuff2mac
    //-------------------------------------------------------
    wire         [BW:0]      committed_cons;

    //-------------------------------------------------------
    // Local ibuff
    //-------------------------------------------------------
    wire         [BW-1:0]    wr_addr;
    wire         [63:0]      wr_data;
    wire         [BW-1:0]    rd_addr;
    wire         [63:0]      rd_data;

    //-------------------------------------------------------
    // Local prod_sync
    //-------------------------------------------------------
    wire         [BW:0]      committed_prod_sync;

    //-------------------------------------------------------
    // Local cons_sync
    //-------------------------------------------------------
    wire         [BW:0]      committed_cons_sync;

    //-------------------------------------------------------
    // Local tlp2ibuff
    //-------------------------------------------------------
    wire         [BW:0]      committed_prod;

    //-------------------------------------------------------
    // Local lbuf_mgmt
    //-------------------------------------------------------
    wire         [63:0]      cpl_addr;
    wire                     rd_lbuf1;
    wire                     rd_lbuf2;
    wire                     wt_lbuf1;
    wire                     wt_lbuf2;
    wire         [63:0]      lbuf_addr;
    wire         [31:0]      lbuf_len;
    wire                     lbuf_en;
    wire                     lbuf64b;
    wire                     lbuf_dn;
    
    //-------------------------------------------------------
    // Local irq_gen
    //-------------------------------------------------------
    wire                     dta_rdy;
    wire         [63:0]      hw_ptr;
    wire         [63:0]      sw_ptr;

    //-------------------------------------------------------
    // ibuff2mac
    //-------------------------------------------------------
    ibuff2mac #(.BW(BW)) ibuff2mac_mod (
        .clk(mac_clk),                                         // I
        .rst(mac_rst),                                         // I
        // MAC tx
        .tx_underrun(mac_tx_underrun),                         // O
        .tx_data(mac_tx_data),                                 // O [63:0]
        .tx_data_valid(mac_tx_data_valid),                     // O [7:0]
        .tx_start(mac_tx_start),                               // O
        .tx_ack(mac_tx_ack),                                   // I
        // ibuff
        .rd_addr(rd_addr),                                     // O [BW-1:0]
        .rd_data(rd_data),                                     // I [63:0]
        // bwd logic
        .committed_cons(committed_cons),                       // O [BW:0]
        .committed_prod(committed_prod_sync)                   // I [BW:0]
        );

    //-------------------------------------------------------
    // ibuff
    //-------------------------------------------------------
    tx_ibuff #(.AW(BW), .DW(64)) ibuff_mod (
        .a(wr_addr),                                           // I [BW-1:0]
        .d(wr_data),                                           // I [63:0]
        .dpra(rd_addr),                                        // I [BW-1:0]
        .clk(mac_clk),                                         // I 
        .qdpo_clk(pcie_clk),                                   // I
        .qdpo(rd_data)                                         // O [63:0]
        );

    //-------------------------------------------------------
    // prod_sync
    //-------------------------------------------------------
    sync_type0 #(.W(BW+1)) prod_sync_mod (
        .clk_out(mac_clk),                                     // I
        .rst_out(mac_rst),                                     // I
        .clk_in(pcie_clk),                                     // I
        .rst_in(pcie_rst),                                     // I
        .in(committed_prod),                                   // I [BW:0]
        .out(committed_prod_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // cons_sync
    //-------------------------------------------------------
    sync_type1 #(.W(BW+1)) cons_sync_mod (
        .clk_out(pcie_clk),                                    // I
        .rst_out(pcie_rst),                                    // I
        .clk_in(mac_clk),                                      // I
        .rst_in(mac_rst),                                      // I
        .in(committed_cons),                                   // I [BW:0]
        .out(committed_cons_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // tlp2ibuff
    //-------------------------------------------------------
    tlp2ibuff #(
        // HST NOTIFICATIONS
        .DSCW(1),
        .DSC_CPL_MSG(32'hCACABEEF),
        .DSC_BASE_QW(0),
        .GC_BASE_QW(1),
        // MISC
        .BW(BW)
    ) tlp2ibuff_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN tx
        .trn_td(rx_trn_td),                                    // O [63:0]
        .trn_trem_n(rx_trn_trem_n),                            // O [7:0]
        .trn_tsof_n(rx_trn_tsof_n),                            // O
        .trn_teof_n(rx_trn_teof_n),                            // O
        .trn_tsrc_rdy_n(rx_trn_tsrc_rdy_n),                    // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n),                       // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // CFG
        .cfg_completer_id(cfg_completer_id),                   // I [15:0]
        .cfg_max_rd_req_size(cfg_max_rd_req_size),             // I [2:0]
        // lbuf_mgmt
        .cpl_addr(cpl_addr),                                   // I [63:0]
        .rd_lbuf1(rd_lbuf1),                                   // I
        .rd_lbuf2(rd_lbuf2),                                   // I
        .wt_lbuf1(wt_lbuf1),                                   // O
        .wt_lbuf2(wt_lbuf2),                                   // O
        .lbuf_addr(lbuf_addr),                                 // I [63:0]
        .lbuf_len(lbuf_len),                                   // I [31:0]
        .lbuf_en(lbuf_en),                                     // I
        .lbuf64b(lbuf64b),                                     // I
        .lbuf_dn(lbuf_dn),                                     // O
        // ibuff2mac
        .committed_prod(committed_prod),                       // O [BW:0]
        // ibuff
        .wr_addr(wr_addr),                                     // O [BW-1:0]
        .wr_data(wr_data),                                     // O [63:0]
        // irq_gen
        .send_irq(dta_rdy),                                    // O
        .hw_ptr(hw_ptr),                                       // O [63:0]
        // EP arb
        .tag_trn(tag_trn),                                     // I [4:0]
        .tag_inc(tag_inc),                                     // O
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep),                                       // O
        .req_ep(req_ep)                                        // O
        );

    //-------------------------------------------------------
    // lbuf_mgmt
    //-------------------------------------------------------
    lbuf_mgmt # (
        .BARHIT(BARHIT),
        .BARMP_CPL_ADDR(BARMP_CPL_ADDR),
        .BARMP_LBUF1_ADDR(BARMP_LBUF1_ADDR),
        .BARMP_LBUF1_EN(BARMP_LBUF1_EN),
        .BARMP_LBUF2_ADDR(BARMP_LBUF2_ADDR),
        .BARMP_LBUF2_EN(BARMP_LBUF2_EN)
    ) lbuf_mgmt_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // lbuf_mgmt
        .cpl_addr(cpl_addr),                                   // O [63:0]
        .rd_lbuf1(rd_lbuf1),                                   // O
        .rd_lbuf2(rd_lbuf2),                                   // O
        .wt_lbuf1(wt_lbuf1),                                   // I
        .wt_lbuf2(wt_lbuf2),                                   // I
        .lbuf_addr(lbuf_addr),                                 // O [63:0]
        .lbuf_len(lbuf_len),                                   // O [31:0]
        .lbuf_en(lbuf_en),                                     // O
        .lbuf64b(lbuf64b),                                     // O
        .lbuf_dn(lbuf_dn)                                      // I
        );

    //-------------------------------------------------------
    // sw_wrbck
    //-------------------------------------------------------
    sw_wrbck #(
        .BARMP(BARMP_WRBCK)
    ) sw_wrbck_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        .sw_ptr(sw_ptr)                                        // O [63:0]
        );

    //-------------------------------------------------------
    // irq_gen
    //-------------------------------------------------------
    tx_irq_gen irq_gen_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        .dta_rdy(dta_rdy),                                     // I
        .hw_ptr(hw_ptr),                                       // I [63:0]
        .sw_ptr(sw_ptr),                                       // I [63:0]
        .send_irq(send_irq)                                    // O
        );

endmodule // tx

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////