/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        col_irq.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Collapses irq.
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

module col_irq (

    input                    clk,
    input                    rst,

    input                    wt_lbuf1,
    input                    wt_lbuf2,

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
    // Local col_irq
    //-------------------------------------------------------   
    reg          [7:0]       col_fsm;

    ////////////////////////////////////////////////
    // col_irq
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            col_fsm <= s0;
        end
        
        else begin  // not rst

            send_irq <= 1'b0;

            case (col_fsm)

                s0 : begin
                    col_fsm <= s1;
                end

                s1 : begin
                    if (wt_lbuf1 || wt_lbuf2) begin
                        col_fsm <= s2;
                    end
                end

                s2 : begin
                    if (!wt_lbuf1 && !wt_lbuf2) begin
                        send_irq <= 1'b1;
                        col_fsm <= s1;
                    end
                end

                default : begin 
                    col_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // col_irq

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////