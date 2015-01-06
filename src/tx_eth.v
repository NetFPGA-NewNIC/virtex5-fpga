/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_eth.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Sends Ethernet frames.
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
`default_nettype none

module tx_eth # (
    parameter BW = 9
    ) (

    input                    clk,
    input                    rst,

    // MAC tx
    output reg               tx_underrun,
    output reg   [63:0]      tx_data,
    output reg   [7:0]       tx_data_valid,
    output reg               tx_start,
    input                    tx_ack,

    // buff
    output       [BW-1:0]    rd_addr,
    input        [63:0]      rd_data,

    // bwd logic
    output reg   [BW:0]      committed_cons,
    input        [BW:0]      committed_prod,

    // frm_sync
    input                    trig,
    input        [12:0]      qw_len,
    input        [7:0]       lst_ben,
    input                    rsk,
    output reg               rsk_tk,
    output reg               sync
    );

    // localparam
    localparam s0 = 8'b00000000;
    localparam s1 = 8'b00000001;
    localparam s2 = 8'b00000010;
    localparam s3 = 8'b00000100;
    localparam s4 = 8'b00001000;
    localparam s5 = 8'b00010000;
    localparam s6 = 8'b00100000;
    localparam s7 = 8'b01000000;
    localparam s8 = 8'b10000000;

    //-------------------------------------------------------
    // Local eth
    //-------------------------------------------------------
    reg          [7:0]       snd_fsm;
    reg          [12:0]      qw_snt;
    reg          [BW:0]      rd_addr_i;
    reg          [BW:0]      nxt_rd_addr;
    reg          [BW:0]      sof_rd_addr;
    reg          [BW:0]      rd_addr_prev0;
    reg          [63:0]      aux_rd_data;
    reg                      eof;

    assign rd_addr = rd_addr_i;

    ////////////////////////////////////////////////
    // eth
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            tx_underrun <= 1'b0;
            tx_start <= 1'b0;
            tx_data_valid <= 'b0;
            snd_fsm <= s0;
        end
        
        else begin  // not rst

            sync <= 1'b0;
            tx_underrun <= 1'b0;
            tx_start <= 1'b0;
            tx_data_valid <= 'b0;
            rd_addr_prev0 <= rd_addr_i;
            eof <= 1'b0;

            if (eof) begin
                committed_cons <= rd_addr_prev0;
            end

            case (snd_fsm)

                s0 : begin
                    rd_addr_i <= 'b0;
                    committed_cons <= 'b0;
                    rsk_tk <= 1'b0;
                    snd_fsm <= s1;
                end

                s1: begin
                    nxt_rd_addr <= rd_addr_i + 1;
                    if (trig) begin
                        rd_addr_i <= nxt_rd_addr;
                        snd_fsm <= s2;
                    end
                end

                s2 : begin
                    sof_rd_addr <= rd_addr_prev0;
                    rd_addr_i <= rd_addr_i + 1;
                    tx_start <= 1'b1;
                    snd_fsm <= s3;
                end

                s3 : begin
                    rsk_tk <= 1'b0;
                    tx_data <= rd_data;
                    tx_data_valid <= 'hFF;
                    rd_addr_i <= rd_addr_i + 1;
                    snd_fsm <= s4;
                end

                s4 : begin
                    tx_data_valid <= 'hFF;
                    nxt_rd_addr <= rd_addr_i + 1;
                    aux_rd_data <= rd_data;
                    snd_fsm <= s5;
                end

                s5 : begin
                    tx_data_valid <= 'hFF;
                    qw_snt <= 'h003;
                    if (tx_ack) begin
                        tx_data <= aux_rd_data;
                        rd_addr_i <= nxt_rd_addr;
                        snd_fsm <= s6;
                    end
                end

                s6 : begin
                    tx_data <= rd_data;
                    rd_addr_i <= rd_addr_i + 1;
                    tx_data_valid <= 'hFF;
                    qw_snt <= qw_snt + 1;
                    if (qw_len == qw_snt) begin
                        sync <= 1'b1;
                        eof <= 1'b1;
                        tx_data_valid <= lst_ben;
                        if (!rsk) begin                    // the normal case
                            rd_addr_i <= rd_addr_i;
                            snd_fsm <= s1;
                        end
                        else begin
                            rsk_tk <= 1'b1;
                            tx_frame_fsm <= s2;
                        end
                    end
                    else if (diff == 'h1) begin
                        tx_underrun <= 1'b1;
                        rd_addr_i <= sof_rd_addr;
                        snd_fsm <= s7;
                    end
                end

                s7 : begin
                    sync <= 1'b1;
                    snd_fsm <= s1;
                end
            
                default : begin 
                    snd_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // tx_eth

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////