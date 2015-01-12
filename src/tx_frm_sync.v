/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_frm_sync.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Sync in eth boundaries.
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

module tx_frm_sync # (
    parameter BW = 9
    ) (

    input                    clk,
    input                    rst,

    // ibuf
    input        [BW-1:0]    rd_addr,
    input        [63:0]      rd_data,

    // bwd logic
    input        [BW:0]      committed_prod,

    // frm_sync
    output reg   [BW:0]      diff,
    output reg               trig,
    output reg   [12:0]      qw_len,
    output reg   [7:0]       lst_ben,
    output reg               rsk,
    input                    rsk_tk,
    input                    sync
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
    // Local frm_sync
    //-------------------------------------------------------
    reg          [7:0]       syn_fsm;
    reg          [15:0]      len;

    ////////////////////////////////////////////////
    // frm_sync
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            syn_fsm <= s0;
        end
        
        else begin  // not rst

            trig <= 1'b0;

            rsk <= 1'b0;
            if (diff >= 'h10) begin
                rsk <= 1'b1;
            end

            diff <= committed_prod + (~rd_addr) + 1;

            case (syn_fsm)

                s0 : begin
                    diff <= 'b0;
                    syn_fsm <= s1;
                end

                s1 : begin
                    len <= rd_data[47:32];
                    if (diff) begin
                        qw_len <= rd_data[47:35];
                        syn_fsm <= s2;
                    end
                end

                s2 : begin
                    if (len[2:0]) begin
                        qw_len <= len[15:3] + 1;
                    end

                    case (len[2:0])                    // my deco
                        3'b000 : begin
                            lst_ben <= 8'b11111111;
                        end
                        3'b001 : begin
                            lst_ben <= 8'b00000001;
                        end
                        3'b010 : begin
                            lst_ben <= 8'b00000011;
                        end
                        3'b011 : begin
                            lst_ben <= 8'b00000111;
                        end
                        3'b100 : begin
                            lst_ben <= 8'b00001111;
                        end
                        3'b101 : begin
                            lst_ben <= 8'b00011111;
                        end
                        3'b110 : begin
                            lst_ben <= 8'b00111111;
                        end
                        3'b111 : begin
                            lst_ben <= 8'b01111111;
                        end
                    endcase

                    if (rsk_tk) begin
                        syn_fsm <= s3;
                    end
                    else if (diff > qw_len) begin
                        trig <= 1'b1;
                        syn_fsm <= s3;
                    end
                    else begin
                        syn_fsm <= s1;
                    end
                end

                s3 : begin
                    len <= rd_data[47:32];
                    if (sync) begin
                        qw_len <= rd_data[47:35];
                        syn_fsm <= s2;
                    end
                end
            
                default : begin 
                    syn_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // tx_frm_sync

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////