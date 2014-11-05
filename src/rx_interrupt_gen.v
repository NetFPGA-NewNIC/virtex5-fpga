/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_interrupt_gen.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Rx interrupt generation.
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

module rx_interrupt_gen (

    input    clk,
    input    reset,

    output reg              cfg_interrupt_n,
    input                   cfg_interrupt_rdy_n,

    input                   rx_activity,
    input                   trigger_tlp,
    input                   trigger_tlp_ack,
    input                   change_huge_page,
    input                   change_huge_page_ack,
    input                   send_numb_qws,
    input                   send_numb_qws_ack,
    input                   huge_page_status_1,
    input                   huge_page_status_2,
    input                   interrupts_enabled,
    input       [31:0]      interrupt_period
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

    // Local wires and reg

    //-------------------------------------------------------
    // Local interrupts_gen
    //-------------------------------------------------------  
    reg     [7:0]   interrupt_gen_fsm;
    reg     [31:0]  counter;
    reg     [31:0]  max_count;
    reg             rx_activity_reg0;
    reg             rx_activity_reg1;

    ////////////////////////////////////////////////
    // interrupts_gen
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (reset) begin  // reset
            cfg_interrupt_n <= 1'b1;
            rx_activity_reg0 <= 1'b0;
            rx_activity_reg1 <= 1'b0;
            interrupt_gen_fsm <= s0;
        end
        
        else begin  // not reset

            rx_activity_reg0 <= rx_activity;
            rx_activity_reg1 <= rx_activity_reg0;

            max_count <= interrupt_period;

            case (interrupt_gen_fsm)

                s0 : begin
                    if (rx_activity_reg1) begin
                        interrupt_gen_fsm <= s1;
                    end
                    else if (trigger_tlp && trigger_tlp_ack) begin
                        interrupt_gen_fsm <= s1;
                    end
                    else if (change_huge_page && change_huge_page_ack) begin
                        interrupt_gen_fsm <= s1;
                    end
                    else if (send_numb_qws && send_numb_qws_ack) begin
                        interrupt_gen_fsm <= s1;
                    end
                end

                s1 : begin
                    counter <= 'b0;
                    if (interrupts_enabled && (huge_page_status_1 || huge_page_status_2)) begin
                        cfg_interrupt_n <= 1'b0;
                        interrupt_gen_fsm <= s2;
                    end
                    else begin
                        interrupt_gen_fsm <= s3;
                    end
                end

                s2 : begin
                    if (!cfg_interrupt_rdy_n) begin
                        cfg_interrupt_n <= 1'b1;
                        interrupt_gen_fsm <= s3;
                    end
                end

                s3 : begin
                    counter <= counter + 1;
                    if (counter == max_count) begin
                        interrupt_gen_fsm <= s0;
                    end
                end

                default : begin
                    interrupt_gen_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // rx_interrupt_gen

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////