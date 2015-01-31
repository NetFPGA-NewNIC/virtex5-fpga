/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mac2axis.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        From v5 mac I/F to axis. Testing only.
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

module mac2axis # (
    parameter BW = 10
    ) (

    // MAC rx
    input                    mac_clk,
    input                    mac_rst,
    input        [63:0]      mac_rx_data,
    input        [7:0]       mac_rx_data_valid,
    input                    mac_rx_good_frame,
    input                    mac_rx_bad_frame,

    // AXIS
    input                    m_axis_aclk,
    input                    m_axis_aresetp,
    output       [63:0]      m_axis_tdata,
    output       [7:0]       m_axis_tstrb,
    output       [127:0]     m_axis_tuser,
    output                   m_axis_tvalid,
    output                   m_axis_tlast,
    input                    m_axis_tready
    );

    //-------------------------------------------------------
    // Local mac2ibuf
    //-------------------------------------------------------
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
    // Local ibuf2axis
    //-------------------------------------------------------
    wire         [BW:0]      committed_cons;

    //-------------------------------------------------------
    // mac2ibuf
    //-------------------------------------------------------
    mac2ibuf #(.BW(BW)) mac2ibuf_mod (
        .clk(mac_clk),                                         // I
        .rst(mac_rst),                                         // I
        // MAC rx
        .rx_data(mac_rx_data),                                 // I [63:0]
        .rx_data_valid(mac_rx_data_valid),                     // I [7:0]
        .rx_good_frame(mac_rx_good_frame),                     // I
        .rx_bad_frame(mac_rx_bad_frame),                       // I
        // ibuf
        .wr_addr(wr_addr),                                     // O [BW-1:0]
        .wr_data(wr_data),                                     // O [63:0]
        // fwd logic
        .committed_prod(committed_prod),                       // O [BW:0]
        .committed_cons(committed_cons_sync),                  // I [BW:0]
        .dropped_pkts(dropped_pkts_cnt)                        // O [15:0]
        );

    //-------------------------------------------------------
    // ibuf
    //-------------------------------------------------------
    xge_ibuf #(.AW(BW), .DW(64)) ibuf_mod (
        .a(wr_addr),                                           // I [BW-1:0]
        .d(wr_data),                                           // I [63:0]
        .dpra(rd_addr),                                        // I [BW-1:0]
        .clk(mac_clk),                                         // I 
        .qdpo_clk(m_axis_aclk),                                // I
        .qdpo(rd_data)                                         // O [63:0]
        );

    //-------------------------------------------------------
    // prod_sync
    //-------------------------------------------------------
    xge_sync_type1 #(.W(BW+1)) prod_sync_mod (
        .clk_out(m_axis_aclk),                                 // I
        .rst_out(m_axis_aresetp),                              // I
        .clk_in(mac_clk),                                      // I
        .rst_in(mac_rst),                                      // I
        .in(committed_prod),                                   // I [BW:0]
        .out(committed_prod_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // cons_sync
    //-------------------------------------------------------
    xge_sync_type0 #(.W(BW+1)) cons_sync_mod (
        .clk_out(mac_clk),                                     // I
        .rst_out(mac_rst),                                     // I
        .clk_in(m_axis_aclk),                                  // I
        .rst_in(m_axis_aresetp),                               // I
        .in(committed_cons),                                   // I [BW:0]
        .out(committed_cons_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // dropped_pkts_cnt_sync
    //-------------------------------------------------------
    xge_sync_type1 #(.W(16)) dropped_pkts_cnt_sync_mod (
        .clk_out(m_axis_aclk),                                 // I
        .rst_out(m_axis_aresetp),                              // I
        .clk_in(mac_clk),                                      // I
        .rst_in(mac_rst),                                      // I
        .in(dropped_pkts_cnt),                                 // I [15:0]
        .out(dropped_pkts_cnt_sync)                            // O [15:0]
        );

    //-------------------------------------------------------
    // ibuf2axis
    //-------------------------------------------------------
    ibuf2axis #(.BW(BW)) ibuf2axis_mod (
        .m_axis_aclk(m_axis_aclk),                             // I
        .m_axis_aresetp(m_axis_aresetp),                       // I
        // AXIS
        .m_axis_tdata(m_axis_tdata),                           // O [63:0]
        .m_axis_tstrb(m_axis_tstrb),                           // O [7:0]
        .m_axis_tuser(m_axis_tuser),                           // O [127:0]
        .m_axis_tvalid(m_axis_tvalid),                         // O
        .m_axis_tlast(m_axis_tlast),                           // O
        .m_axis_tready(m_axis_tready)                          // I
        // mac2ibuf
        .committed_prod(committed_prod_sync),                  // I [BW:0]
        .committed_cons(committed_cons),                       // O [BW:0]
        // ibuf
        .rd_addr(rd_addr),                                     // O [BW-1:0]
        .rd_data(rd_data)                                      // I [63:0]
        );

endmodule // mac2axis

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////