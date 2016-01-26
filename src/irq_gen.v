/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        irq_gen.v
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

module irq_gen (

    input                    clk,
    input                    rst,

    input                    hw_ptr_update,
    input                    hst_rdy,
    input        [63:0]      hw_ptr,
    input        [63:0]      sw_ptr,

    output reg               send_irq
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
    // Local irq_gen
    //-------------------------------------------------------  
    reg          [7:0]       irq_gen_fsm;
    reg                      update_reg0;
    reg                      update_reg1;

    ////////////////////////////////////////////////
    // irq_gen
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            send_irq <= 1'b0;
            irq_gen_fsm <= s0;
        end
        
        else begin  // not rst

            update_reg0 <= hw_ptr_update;
            update_reg1 <= update_reg0;

            case (irq_gen_fsm)

                s0 : begin
                    update_reg0 <= 1'b0;
                    update_reg1 <= 1'b0;
                    irq_gen_fsm <= s1;
                end

                s1 : begin
                    if (hst_rdy) begin
                        irq_gen_fsm <= s2;
                    end
                end

                s2 : begin
                    if (update_reg1) begin
                        send_irq <= 1'b1;
                        irq_gen_fsm <= s3;
                    end
                end

                s3 : begin
                    if (update_reg1 || (hw_ptr != sw_ptr)) begin
                        send_irq <= 1'b1;
                    end
                    else begin
                        send_irq <= 1'b0;
                    end
                end

                default : begin
                    irq_gen_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // irq_gen

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////