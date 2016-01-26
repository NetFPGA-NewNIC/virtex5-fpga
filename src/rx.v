/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects rx
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

module rx # (
    // BAR MAPPING
    parameter BARHIT = 2,
    parameter BARMP_LBUF1_ADDR = 6'bxxxxxx,
    parameter BARMP_LBUF1_EN = 6'bxxxxxx,
    parameter BARMP_LBUF2_ADDR = 6'bxxxxxx,
    parameter BARMP_LBUF2_EN = 6'bxxxxxx,
    parameter BARMP_WRBCK = 6'bxxxxxx,
    // MISC
    parameter BW = 10,
    parameter CONFIG_TIMESTAMP = 0
    ) (

    input                    bkd_clk,
    input                    bkd_rst,

    input                    pcie_clk,
    input                    pcie_rst,

    // BKD rx
    input        [63:0]      s_axis_tdata,
    input        [7:0]       s_axis_tstrb,
    input        [127:0]     s_axis_tuser,
    input                    s_axis_tvalid,
    input                    s_axis_tlast,
    output                   s_axis_tready,

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
    input        [2:0]       cfg_max_payload_size,
    output                   send_irq,

    // EP arb
    input                    my_trn,
    output                   drv_ep
    );

    //-------------------------------------------------------
    // Local bkd2ibuf
    //-------------------------------------------------------
    wire                     bkd_activity;
    wire         [BW:0]      committed_prod;
    wire         [15:0]      dropped_pkts_cnt;

    //-------------------------------------------------------
    // Local ibuf
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
    // Local dropped_pkts_cnt_sync
    //-------------------------------------------------------
    wire         [15:0]      dropped_pkts_cnt_sync;

    //-------------------------------------------------------
    // Local bkd2tlp_ctrl
    //-------------------------------------------------------
    wire                     trig_tlp;
    wire                     trig_tlp_ack;
    wire                     chng_lbuf;
    wire                     chng_lbuf_ack;
    wire                     send_qws;
    wire                     send_qws_ack;
    wire         [5:0]       qw_cnt;

    //-------------------------------------------------------
    // Local ibuf2tlp
    //-------------------------------------------------------
    wire         [BW:0]      committed_cons;

    //-------------------------------------------------------
    // Local lbuf_mgmt
    //-------------------------------------------------------
    wire         [63:0]      lbuf_addr;
    wire                     lbuf_en;
    wire                     lbuf64b;
    wire                     lbuf_dn;
    
    //-------------------------------------------------------
    // Local irq_gen
    //-------------------------------------------------------
    wire         [63:0]      hw_ptr;
    wire         [63:0]      sw_ptr;

    //-------------------------------------------------------
    // bkd2ibuf
    //-------------------------------------------------------
    bkd2ibuf #(
        .BW(BW),
        .CONFIG_TIMESTAMP(CONFIG_TIMESTAMP)
    ) bkd2ibuf_mod (
        .clk(bkd_clk),                                         // I
        .rst(bkd_rst),                                         // I
        // BKD rx
        .s_axis_tdata(s_axis_tdata),                           // I [63:0]
        .s_axis_tstrb(s_axis_tstrb),                           // I [7:0]
        .s_axis_tuser(s_axis_tuser),                           // I [127:0]
        .s_axis_tvalid(s_axis_tvalid),                         // I
        .s_axis_tlast(s_axis_tlast),                           // I
        .s_axis_tready(s_axis_tready),                         // O
        // ibuf
        .wr_addr(wr_addr),                                     // O [BW-1:0]
        .wr_data(wr_data),                                     // O [63:0]
        // fwd logic
        .hst_rdy(lbuf_en),                                     // I
        .activity(bkd_activity),                               // O
        .committed_prod(committed_prod),                       // O [BW:0]
        //.committed_cons(committed_cons_sync),                  // I [BW:0]
        .committed_cons(committed_cons_sync)                  // I [BW:0]
        //.dropped_pkts(dropped_pkts_cnt)                        // O [15:0]
        );

    //-------------------------------------------------------
    // ibuf
    //-------------------------------------------------------
    rx_ibuf #(.AW(BW), .DW(64)) ibuf_mod (
        .a(wr_addr),                                           // I [BW-1:0]
        .d(wr_data),                                           // I [63:0]
        .dpra(rd_addr),                                        // I [BW-1:0]
        .clk(bkd_clk),                                         // I 
        .qdpo_clk(pcie_clk),                                   // I
        .qdpo(rd_data)                                         // O [63:0]
        );

    //-------------------------------------------------------
    // prod_sync
    //-------------------------------------------------------
    sync_type1 #(.W(BW+1)) prod_sync_mod (
        .clk_out(pcie_clk),                                    // I
        .rst_out(pcie_rst),                                    // I
        .clk_in(bkd_clk),                                      // I
        .rst_in(bkd_rst),                                      // I
        .in(committed_prod),                                   // I [BW:0]
        .out(committed_prod_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // cons_sync
    //-------------------------------------------------------
    sync_type0 #(.W(BW+1)) cons_sync_mod (
        .clk_out(bkd_clk),                                     // I
        .rst_out(bkd_rst),                                     // I
        .clk_in(pcie_clk),                                     // I
        .rst_in(pcie_rst),                                     // I
        .in(committed_cons),                                   // I [BW:0]
        .out(committed_cons_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // dropped_pkts_cnt_sync
    //-------------------------------------------------------
    sync_type1 #(.W(16)) dropped_pkts_cnt_sync_mod (
        .clk_out(pcie_clk),                                    // I
        .rst_out(pcie_rst),                                    // I
        .clk_in(bkd_clk),                                      // I
        .rst_in(bkd_rst),                                      // I
        .in(dropped_pkts_cnt),                                 // I [15:0]
        .out(dropped_pkts_cnt_sync)                            // O [15:0]
        );

    //-------------------------------------------------------
    // bkd2tlp_ctrl
    //-------------------------------------------------------
    bkd2tlp_ctrl #(.BW(BW)) bkd2tlp_ctrl_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // CFG
        .cfg_max_payload_size(cfg_max_payload_size),           // I [2:0]
        // bkd2ibuf
        .committed_prod(committed_prod_sync),                  // I [BW:0]
        .bkd_activity(bkd_activity),                           // I
        // bkd2tlp_ctrl
        .trig_tlp(trig_tlp),                                   // O
        .trig_tlp_ack(trig_tlp_ack),                           // I
        .chng_lbuf(chng_lbuf),                                 // O
        .chng_lbuf_ack(chng_lbuf_ack),                         // I
        .send_qws(send_qws),                                   // O
        .send_qws_ack(send_qws_ack),                           // I
        .qw_cnt(qw_cnt)                                        // O [5:0]
        );

    //-------------------------------------------------------
    // ibuf2tlp
    //-------------------------------------------------------
    ibuf2tlp ibuf2tlp_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
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
        .lbuf_addr(lbuf_addr),                                 // I [63:0]
        .lbuf_en(lbuf_en),                                     // I
        .lbuf64b(lbuf64b),                                     // I
        .lbuf_dn(lbuf_dn),                                     // O
        // bkd2tlp_ctrl
        .trig_tlp(trig_tlp),                                   // I
        .trig_tlp_ack(trig_tlp_ack),                           // O
        .chng_lbuf(chng_lbuf),                                 // I
        .chng_lbuf_ack(chng_lbuf_ack),                         // O
        .send_qws(send_qws),                                   // I
        .send_qws_ack(send_qws_ack),                           // O
        .qw_cnt(qw_cnt),                                       // I [5:0]
        // bkd2ibuf
        .committed_cons(committed_cons),                       // O [BW:0]
        // ibuf
        .rd_addr(rd_addr),                                     // O [BW-1:0]
        .rd_data(rd_data),                                     // I [63:0]
        // irq_gen
        .hw_ptr(hw_ptr),                                       // O [63:0]
        // ep arb
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep),                                       // O
        // stats
        //.dropped_pkts(dropped_pkts_cnt_sync)                   // I [15:0]
        .dropped_pkts(15'b0)                                   // I [15:0]
        );

    //-------------------------------------------------------
    // lbuf_mgmt
    //-------------------------------------------------------
    lbuf_mgmt # (
        .BARHIT(BARHIT),
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
        .wt_lbuf1(1'b0),                                       // I
        .wt_lbuf2(1'b0),                                       // I
        .lbuf_addr(lbuf_addr),                                 // O [63:0]
        .lbuf_en(lbuf_en),                                     // O
        .lbuf64b(lbuf64b),                                     // O
        .lbuf_dn(lbuf_dn)                                      // I
        );

    //-------------------------------------------------------
    // sw_wrbck
    //-------------------------------------------------------
    sw_wrbck #(
        .BARHIT(BARHIT),
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
    irq_gen irq_gen_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        .hw_ptr_update(bkd_activity),                          // I
        .hst_rdy(lbuf_en),                                     // I
        .hw_ptr(hw_ptr),                                       // I [63:0]
        .sw_ptr(sw_ptr),                                       // I [63:0]
        .send_irq(send_irq)                                    // O
        );

endmodule // rx

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////