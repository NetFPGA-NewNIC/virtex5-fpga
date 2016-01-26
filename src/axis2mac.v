/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        axis2mac.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        From axis to v5 mac I/F. Testing only.
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

module axis2mac # (
    parameter BW = 9,
    parameter DST_PORT = 8'h00
    ) (

    // MAC tx
    input                    mac_clk,
    input                    mac_rst,
    output                   mac_tx_underrun,
    output       [63:0]      mac_tx_data,
    output       [7:0]       mac_tx_data_valid,
    output                   mac_tx_start,
    input                    mac_tx_ack,

    // AXIS
    input                    s_axis_aclk,
    input                    s_axis_aresetp,
    input        [63:0]      s_axis_tdata,
    input        [7:0]       s_axis_tstrb,
    input        [127:0]     s_axis_tuser,
    input                    s_axis_tvalid,
    input                    s_axis_tlast,
    output                   s_axis_tready
    );

    //-------------------------------------------------------
    // Local ibuf2mac
    //-------------------------------------------------------
    wire         [BW:0]      committed_cons;

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
    // Local axis2ibuf
    //-------------------------------------------------------
    wire         [BW:0]      committed_prod;

    //-------------------------------------------------------
    // ibuf2mac
    //-------------------------------------------------------
    ibuf2mac #(.BW(BW)) ibuf2mac_mod (
        .clk(mac_clk),                                         // I
        .rst(mac_rst),                                         // I
        // MAC tx
        .tx_underrun(mac_tx_underrun),                         // O
        .tx_data(mac_tx_data),                                 // O [63:0]
        .tx_data_valid(mac_tx_data_valid),                     // O [7:0]
        .tx_start(mac_tx_start),                               // O
        .tx_ack(mac_tx_ack),                                   // I
        // ibuf
        .rd_addr(rd_addr),                                     // O [BW-1:0]
        .rd_data(rd_data),                                     // I [63:0]
        // bwd logic
        .committed_cons(committed_cons),                       // O [BW:0]
        .committed_prod(committed_prod_sync)                   // I [BW:0]
        );

    //-------------------------------------------------------
    // ibuf
    //-------------------------------------------------------
    xge_ibuf #(.AW(BW), .DW(64)) ibuf_mod (
        .a(wr_addr),                                           // I [BW-1:0]
        .d(wr_data),                                           // I [63:0]
        .dpra(rd_addr),                                        // I [BW-1:0]
        .clk(s_axis_aclk),                                     // I 
        .qdpo_clk(mac_clk),                                    // I
        .qdpo(rd_data)                                         // O [63:0]
        );

    //-------------------------------------------------------
    // prod_sync
    //-------------------------------------------------------
    xge_sync_type0 #(.W(BW+1)) prod_sync_mod (
        .clk_out(mac_clk),                                     // I
        .rst_out(mac_rst),                                     // I
        .clk_in(s_axis_aclk),                                  // I
        .rst_in(s_axis_aresetp),                               // I
        .in(committed_prod),                                   // I [BW:0]
        .out(committed_prod_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // cons_sync
    //-------------------------------------------------------
    xge_sync_type1 #(.W(BW+1)) cons_sync_mod (
        .clk_out(s_axis_aclk),                                 // I
        .rst_out(s_axis_aresetp),                              // I
        .clk_in(mac_clk),                                      // I
        .rst_in(mac_rst),                                      // I
        .in(committed_cons),                                   // I [BW:0]
        .out(committed_cons_sync)                              // O [BW:0]
        );

    //-------------------------------------------------------
    // axis2ibuf
    //-------------------------------------------------------
    axis2ibuf #(
        .BW(BW),
        .DST_PORT(DST_PORT)
    ) axis2ibuf_mod (
        .s_axis_aclk(s_axis_aclk),                             // I
        .s_axis_aresetp(s_axis_aresetp),                       // I
        // AXIS
        .s_axis_tdata(s_axis_tdata),                           // I [63:0]
        .s_axis_tstrb(s_axis_tstrb),                           // I [7:0]
        .s_axis_tuser(s_axis_tuser),                           // I [127:0]
        .s_axis_tvalid(s_axis_tvalid),                         // I
        .s_axis_tlast(s_axis_tlast),                           // I
        .s_axis_tready(s_axis_tready),                         // O
        // ibuf2mac
        .committed_prod(committed_prod),                       // O [BW:0]
        .committed_cons(committed_cons_sync),                  // I [BW:0]
        // ibuf
        .wr_addr(wr_addr),                                     // O [BW-1:0]
        .wr_data(wr_data)                                      // O [63:0]
        );

endmodule // axis2mac

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////