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

module rx ( 

    input                    mac_clk,
    input                    mac_rst,

    input                    pcie_clk,
    input                    pcie_rst,

    // MAC rx
    input        [63:0]      mac_rx_data,
    input        [7:0]       mac_rx_data_valid,
    input                    mac_rx_good_frame,
    input                    mac_rx_bad_frame,

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
    input        [2:0]       cfg_max_payload_size,
    output                   send_interrupt,

    // EP arb
    input                    my_trn,
    output                   drv_ep
    );

    //-------------------------------------------------------
    // Local mac2buff
    //-------------------------------------------------------
    wire         [`BF:0]     committed_prod;
    wire                     mac_activity;
    wire         [15:0]      dropped_pkts_cnt;

    //-------------------------------------------------------
    // Local buff
    //-------------------------------------------------------
    wire         [`BF:0]     wr_addr;
    wire         [63:0]      wr_data;
    wire         [`BF:0]     rd_addr;
    wire         [63:0]      rd_data;

    //-------------------------------------------------------
    // Local buff2tlp
    //-------------------------------------------------------
    
    //-------------------------------------------------------
    // Local irq_gen
    //-------------------------------------------------------
    wire         [63:0]      hw_pointer;
    wire         [63:0]      sw_pointer;
    wire                     hst_rdy;

    //-------------------------------------------------------
    // mac2buff
    //-------------------------------------------------------
    mac2buff mac2buff_mod (
        .clk(mac_clk),                                         // I
        .rst(mac_rst),                                         // I
        .rx_data(mac_rx_data),                                 // I [63:0]
        .rx_data_valid(mac_rx_data_valid),                     // I [7:0]
        .rx_good_frame(mac_rx_good_frame),                     // I
        .rx_bad_frame(mac_rx_bad_frame),                       // I
        .wr_addr(wr_addr),                                     // O [`BF:0]
        .wr_data(wr_data),                                     // O [63:0]
        .activity(mac_activity),                               // O
        .committed_prod(committed_prod),                       // O [`BF:0]
        .committed_cons(committed_cons),                       // I [`BF:0]
        .dropped_pkts(dropped_pkts_cnt)                        // O [15:0]
        );

    //-------------------------------------------------------
    // buff
    //-------------------------------------------------------
    rx_buff #(.AW(`BF+1), .DW(64)) buff_mod (
        .a(wr_addr),                                           // I [`BF:0]
        .d(wr_data),                                           // I [63:0]
        .dpra(rd_addr),                                        // I [`BF:0]
        .clk(mac_clk),                                         // I 
        .qdpo_clk(pcie_clk),                                   // I
        .qdpo(rd_data)                                         // O [63:0]
        );

    //-------------------------------------------------------
    // prod_sync
    //-------------------------------------------------------
    sync_type1 #(.W(`BF+1)) prod_sync_mod (
        .clk_out(pcie_clk),                                    // I
        .rst_out(pcie_rst),                                    // I
        .clk_in(mac_clk),                                      // I
        .rst_in(mac_rst),                                      // I
        .in(committed_prod),                                   // I [`BF:0]
        .out(committed_prod_sync)                              // O [`BF:0]
        );

    //-------------------------------------------------------
    // cons_sync
    //-------------------------------------------------------
    synch_type0 #(.W(`BF+1)) cons_sync_mod (
        .clk_out(mac_clk),                                     // I
        .rst_out(reset156_25),                                 // I
        .clk_in(pcie_clk),                                     // I
        .rst_in(pcie_rst),                                     // I
        .in(committed_cons),                                   // I [`BF:0]
        .out(committed_cons_sync)                              // O [`BF:0]
        );

    //-------------------------------------------------------
    // dropped_pkts_cnt_sync
    //-------------------------------------------------------
    synch_type1 #(15,1) dropped_pkts_cnt_sync_mod (
        .clk_out(pcie_clk),                                    // I
        .rst_out(pcie_rst),                                    // I
        .clk_in(mac_clk),                                      // I
        .rst_in(mac_rst),                                      // I
        .in(dropped_pkts_cnt),                                 // I [15:0]
        .out(dropped_pkts_cnt_sync)                            // O [15:0]
        );

    //-------------------------------------------------------
    // eth2tlp_ctrl
    //-------------------------------------------------------
    eth2tlp_ctrl eth2tlp_ctrl_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        .cfg_max_payload_size(cfg_max_payload_size),           // I [2:0]
        .committed_prod(committed_prod_sync),                  // I [`BF:0]
        .mac_activity(mac_activity),                           // I
        .trig_tlp(trig_tlp),                                   // O
        .trig_tlp_ack(trig_tlp_ack),                           // I
        .chng_lbuf(chng_lbuf),                                 // O
        .chng_lbuf_ack(chng_lbuf_ack),                         // I
        .send_qws(send_qws),                                   // O
        .send_qws_ack(send_qws_ack),                           // I
        .qw_cnt(qw_cnt)                                        // O [5:0]
        );

    //-------------------------------------------------------
    // buff2tlp
    //-------------------------------------------------------
    buff2tlp buff2tlp_mod (
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
        .cfg_completer_id(cfg_completer_id),                   // I [15:0]
        // lbuf_mgmt
        .lbuf1_addr(lbuf1_addr),                               // I [63:0]
        .lbuf1_av(lbuf1_av),                                   // I
        .lbuf1_dn(lbuf1_dn),                                   // O
        .lbuf2_addr(lbuf1_addr),                               // I [63:0]
        .lbuf2_av(lbuf1_av),                                   // I
        .lbuf2_dn(lbuf1_dn),                                   // O
        // eth2tlp_ctrl
        .trig_tlp(trig_tlp),                                   // I
        .trig_tlp_ack(trig_tlp_ack),                           // O
        .chng_lbuf(chng_lbuf),                                 // I
        .chng_lbuf_ack(chng_lbuf_ack),                         // O
        .send_qws(send_qws),                                   // I
        .send_qws_ack(send_qws_ack),                           // O
        .qw_cnt(qw_cnt),                                       // I [5:0]
        // mac2buff
        .committed_cons(committed_cons),                       // O [`BF:0]
        // buff
        .rd_addr(rd_addr),                                     // O [`BF:0]
        .rd_data(rd_data),                                     // I [63:0]
        // irq_gen
        .hw_pointer(hw_pointer),                               // O [63:0]
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep),                                       // O
        .dropped_pkts(dropped_pkts_cnt_sync)                   // I [15:0]
        );

    //-------------------------------------------------------
    // lbuf_mgmt
    //-------------------------------------------------------
    lbuf_mgmt # (
        .BARMP_lbuf1(6'bxxxxxx),
        .BARMP_lbuf2(6'bxxxxxx)
    ) lbuf_mgmt_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem),                                 // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // lbuf_mgmt
        .lbuf1_addr(lbuf1_addr),                               // O [63:0]
        .lbuf1_av(lbuf1_av),                                   // O
        .lbuf1_dn(lbuf1_dn),                                   // I
        .lbuf2_addr(lbuf1_addr),                               // O [63:0]
        .lbuf2_av(lbuf1_av),                                   // O
        .lbuf2_dn(lbuf1_dn)                                    // I
        );

    //-------------------------------------------------------
    // sw_wr_back
    //-------------------------------------------------------
    sw_wr_back #(
        .BARMP(6'b011110)
    ) sw_wr_back_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem),                                 // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        .sw_pointer(sw_pointer)                                // O [63:0]
        );

    //-------------------------------------------------------
    // irq_gen
    //-------------------------------------------------------
    assign hst_rdy = lbuf1_av | lbuf2_av;

    irq_gen irq_gen_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        .mac_activity(mac_activity),                           // I
        .hw_pointer(hw_pointer),                               // I [63:0]
        .sw_pointer(sw_pointer),                               // I [63:0]
        .hst_rdy(hst_rdy),                                     // I
        .send_interrupt(send_interrupt)                        // O
        );

endmodule // rx

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////