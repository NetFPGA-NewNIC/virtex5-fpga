/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_interrupt_gen.v
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

module tx_interrupt_gen (

    input                   clk,
    input                   reset,

    input       [63:0]      hw_pointer,
    input       [63:0]      sw_pointer,
    input                   notify_ack,

    output reg              send_interrupt
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

    ////////////////////////////////////////////////
    // interrupts_gen
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (reset) begin  // reset
            send_interrupt <= 1'b0;
            interrupt_gen_fsm <= s0;
        end
        
        else begin  // not reset

            case (interrupt_gen_fsm)

                s0 : begin
                    if (notify_ack) begin
                        send_interrupt <= 1'b1;
                        interrupt_gen_fsm <= s1;
                    end
                end

                s1 : begin
                    if (hw_pointer == sw_pointer) begin
                        send_interrupt <= 1'b0;
                    end
                    else begin
                        send_interrupt <= 1'b1;
                    end
                end

                default : begin
                    interrupt_gen_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // tx_interrupt_gen

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////