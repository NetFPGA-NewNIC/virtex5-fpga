/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        ibuf2mac.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects blocks.
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

module ibuf2mac # (
    parameter BW = 9
    ) (

    input                    clk,
    input                    rst,

    // MAC tx
    output                   tx_underrun,
    output       [63:0]      tx_data,
    output       [7:0]       tx_data_valid,
    output                   tx_start,
    input                    tx_ack,

    // ibuf
    output       [BW-1:0]    rd_addr,
    input        [63:0]      rd_data,

    // bwd logic
    output       [BW:0]      committed_cons,
    input        [BW:0]      committed_prod
    );

    //-------------------------------------------------------
    // Local frm_sync
    //-------------------------------------------------------
    wire         [BW:0]      diff;
    wire                     trig;
    wire         [12:0]      qw_len;
    wire         [7:0]       lst_ben;
    wire                     rsk;
    wire                     rsk_tk;
    wire                     sync;

    //-------------------------------------------------------
    // frm_sync
    //-------------------------------------------------------
    tx_frm_sync #(.BW(BW)) frm_sync_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // ibuf
        .rd_addr(rd_addr),                                     // I [BW-1:0]
        .rd_data(rd_data),                                     // I [63:0]
        // bwd logic
        .committed_prod(committed_prod),                       // I [BW:0]
        // frm_sync
        .diff(diff),                                           // O [BW:0]
        .trig(trig),                                           // O
        .qw_len(qw_len),                                       // O [12:0]
        .lst_ben(lst_ben),                                     // O [7:0]
        .rsk(rsk),                                             // O
        .rsk_tk(rsk_tk),                                       // I
        .sync(sync)                                            // I
        );

    //-------------------------------------------------------
    // eth
    //-------------------------------------------------------
    tx_eth #(.BW(BW)) eth_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // MAC tx
        .tx_underrun(tx_underrun),                             // O
        .tx_data(tx_data),                                     // O [63:0]
        .tx_data_valid(tx_data_valid),                         // O [7:0]
        .tx_start(tx_start),                                   // O
        .tx_ack(tx_ack),                                       // I
        // ibuf
        .rd_addr(rd_addr),                                     // O [BW-1:0]
        .rd_data(rd_data),                                     // I [63:0]
        // bwd logic
        .committed_cons(committed_cons),                       // O [BW:0]
        .committed_prod(committed_prod),                       // I [BW:0]
        // frm_sync
        .diff(diff),                                           // I [BW:0]
        .trig(trig),                                           // I
        .qw_len(qw_len),                                       // I [12:0]
        .lst_ben(lst_ben),                                     // I [7:0]
        .rsk(rsk),                                             // I
        .rsk_tk(rsk_tk),                                       // O
        .sync(sync)                                            // O
        );

endmodule // ibuf2mac

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////