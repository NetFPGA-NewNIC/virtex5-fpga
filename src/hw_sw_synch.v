/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        hw_sw_synch.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Generates interrupt if hw and sw are out of synch
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
`include "includes.v"

module hw_sw_synch (

    input                   trn_clk,
    input                   reset,

    input       [63:0]      trn_rd,
    input       [7:0]       trn_rrem_n,
    input                   trn_rsof_n,
    input                   trn_reof_n,
    input                   trn_rsrc_rdy_n,
    input                   trn_rsrc_dsc_n,
    input       [6:0]       trn_rbar_hit_n,
    input                   trn_rdst_rdy_n,
    
    input       [63:0]      hw_pointer,
    output reg              resend_interrupt,
    input                   resend_interrupt_ack
    );
    parameter BARMAPPING = 0;

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
    // Local rcv host_pointer
    //-------------------------------------------------------
    reg     [7:0]      host_last_seen_fsm;
    reg     [31:0]     aux_dw;
    reg     [63:0]     host_pointer;
    reg                synch_hw_sw;

    //-------------------------------------------------------
    // Local synch
    //-------------------------------------------------------
    reg     [7:0]      synch_fsm;

    ////////////////////////////////////////////////
    // rcv host_pointer
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            synch_hw_sw <= 1'b0;
            host_last_seen_fsm <= s0;
        end
        
        else begin  // not reset

            synch_hw_sw <= 1'b0;

            case (host_last_seen_fsm)

                s0 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n) && (!trn_rbar_hit_n[2])) begin
                        if (trn_rd[62:56] == `MEM_WR32_FMT_TYPE) begin
                            host_last_seen_fsm <= s1;
                        end
                        else if (trn_rd[62:56] == `MEM_WR64_FMT_TYPE) begin
                            host_last_seen_fsm <= s3;
                        end
                    end
                end

                s1 : begin
                    aux_dw <= trn_rd[31:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[39:34])

                            BARMAPPING : begin     // host synch
                                host_last_seen_fsm <= s2;
                            end

                            default : begin //other addresses
                                host_last_seen_fsm <= s0;
                            end
                        endcase
                    end
                end

                s2 : begin
                    synch_hw_sw <= 1'b1;

                    host_pointer[7:0] <= aux_dw[31:24];
                    host_pointer[15:8] <= aux_dw[23:16];
                    host_pointer[23:16] <= aux_dw[15:8];
                    host_pointer[31:24] <= aux_dw[7:0];

                    host_pointer[39:32] <= trn_rd[63:56];
                    host_pointer[47:40] <= trn_rd[55:48];
                    host_pointer[55:48] <= trn_rd[47:40];
                    host_pointer[63:56] <= trn_rd[39:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        host_last_seen_fsm <= s0;
                    end
                end

                s3 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[7:2])

                            BARMAPPING : begin     // host synch
                                host_last_seen_fsm <= s4;
                            end

                            default : begin //other addresses
                                host_last_seen_fsm <= s0;
                            end
                        endcase
                    end
                end

                s4 : begin
                    synch_hw_sw <= 1'b1;

                    host_pointer[7:0]   <= trn_rd[63:56];
                    host_pointer[15:8]  <= trn_rd[55:48];
                    host_pointer[23:16] <= trn_rd[47:40];
                    host_pointer[31:24] <= trn_rd[39:32];

                    host_pointer[39:32] <= trn_rd[31:24];
                    host_pointer[47:40] <= trn_rd[23:16];
                    host_pointer[55:48] <= trn_rd[15:8];
                    host_pointer[63:56] <= trn_rd[7:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        host_last_seen_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    host_last_seen_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // synch
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            resend_interrupt <= 1'b0;
            synch_fsm <= s0;
        end
        
        else begin  // not reset

            case (synch_fsm)

                s0 : begin
                    if (synch_hw_sw) begin
                        synch_fsm <= s1;                    // host is going to sleep
                    end
                end

                s1 : begin
                    if (hw_pointer == host_pointer) begin   // hw and sw are synch
                        synch_fsm <= s0;
                    end
                    else begin
                        resend_interrupt <= 1'b1;
                        synch_fsm <= s2;
                    end
                end

                s2 : begin
                    if (resend_interrupt_ack) begin
                        resend_interrupt <= 1'b0;
                        synch_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    synch_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // hw_sw_synch

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////