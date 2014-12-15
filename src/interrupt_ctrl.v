/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        interrupt_ctrl.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Global interrupt control.
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

module interrupt_ctrl (

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

    output reg              cfg_interrupt_n,
    input                   cfg_interrupt_rdy_n,

    // Arbitrations handshake  //
    input                   my_turn,
    output reg              driving_interface,
    output reg              req_ep,

    input                   send_interrupt
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
    // Local TLP reception
    //-------------------------------------------------------
    reg     [7:0]   tlp_rx_fsm;
    reg             interrupts_reenabled;

    //-------------------------------------------------------
    // Local send_interrupt_fsm
    //-------------------------------------------------------
    reg     [7:0]   send_interrupt_fsm;

    ////////////////////////////////////////////////
    // send_interrupt_fsm
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            req_ep <= 1'b0;
            driving_interface <= 1'b0;
            cfg_interrupt_n <= 1'b1;
            send_interrupt_fsm <= s0;
        end
        
        else begin  // not reset

            case (send_interrupt_fsm)

                s0 : begin
                    if (send_interrupt) begin
                        req_ep <= 1'b1;
                        send_interrupt_fsm <= s1;
                    end
                end

                s1 : begin
                    if (my_turn) begin
                        req_ep <= 1'b0;
                        driving_interface <= 1'b1;
                        cfg_interrupt_n <= 1'b0;
                        send_interrupt_fsm <= s2;
                    end
                end

                s2 : begin
                    if (!cfg_interrupt_rdy_n) begin
                        cfg_interrupt_n <= 1'b1;
                        driving_interface <= 1'b0;
                        send_interrupt_fsm <= s3;
                    end
                end

                s3 : begin
                    if (interrupts_reenabled) begin
                        send_interrupt_fsm <= s0;
                    end
                end

                default : begin
                    send_interrupt_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // interrupts_enabled & TLP reception
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            interrupts_reenabled <= 1'b0;
            tlp_rx_fsm <= s0;
        end
        
        else begin  // not reset

            interrupts_reenabled <= 1'b0;

            case (tlp_rx_fsm)

                s0 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n) && (!trn_rbar_hit_n[2])) begin
                        if (trn_rd[62:56] == `MEM_WR32_FMT_TYPE) begin
                            tlp_rx_fsm <= s1;
                        end
                        else if (trn_rd[62:56] == `MEM_WR64_FMT_TYPE) begin
                            tlp_rx_fsm <= s2;
                        end
                    end
                end

                s1 : begin
                    aux_dw <= trn_rd[31:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[39:34])

                            6'b001000 : begin     // host going to sleep
                                interrupts_reenabled <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end

                        endcase
                    end
                end

                s2 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[7:2])

                            6'b001000 : begin     // interrupts eneable
                                interrupts_reenabled <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end

                        endcase
                    end
                end

                default : begin //other TLPs
                    tlp_rx_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // interrupt_ctrl

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////