/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        sync_type0.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Synchronizes signals that cross clock domains. Other modules do not have
*        to care about synchronization.
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

module sync_type0 # (
    parameter W = 32
    ) (

    input                    clk_out,         // freq(clk_out) < freq(clk_in)
    input                    rst_out,

    input                    clk_in,
    input                    rst_in,

    input        [W-1:0]     in,
    output reg   [W-1:0]     out
    );

    // localparam
    localparam s0 = 9'b000000000;
    localparam s1 = 9'b000000001;
    localparam s2 = 9'b000000010;
    localparam s3 = 9'b000000100;
    localparam s4 = 9'b000001000;
    localparam s5 = 9'b000010000;
    localparam s6 = 9'b000100000;
    localparam s7 = 9'b001000000;
    localparam s8 = 9'b010000000;
    localparam s9 = 9'b100000000;

    //-------------------------------------------------------
    // Local a
    //-------------------------------------------------------
    reg          [8:0]       fsm_a;
    reg                      sync;
    reg          [W-1:0]     cross;

    //-------------------------------------------------------
    // Local b
    //-------------------------------------------------------
    reg          [8:0]       fsm_b;
    reg                      sync_reg0;
    reg                      sync_reg1;

    ////////////////////////////////////////////////
    // a
    ////////////////////////////////////////////////
    always @(posedge clk_in) begin

        if (rst_in) begin  // rst
            sync <= 1'b0;
            fsm_a <= s0;
        end
        
        else begin  // not rst

            sync <= 1'b0;

            case (fsm_a)

                s0 : fsm_a <= s1;

                s1 : begin
                    cross <= in;
                    fsm_a <= s2;
                end

                s2 : begin
                    sync <= 1'b1;
                    fsm_a <= s3;
                end

                s3 : begin
                    sync <= 1'b1;
                    fsm_a <= s4;
                end

                s4 : fsm_a <= s5;
                s5 : fsm_a <= s6;
                s6 : fsm_a <= s7;
                s7 : fsm_a <= s8;
                s8 : fsm_a <= s9;
                s9 : fsm_a <= s0;

                default : begin 
                    fsm_a <= s0;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // b
    ////////////////////////////////////////////////
    always @(posedge clk_out) begin

        if (rst_out) begin  // rst
            fsm_b <= s0;
        end
        
        else begin  // not rst

            sync_reg0 <= sync;
            sync_reg1 <= sync_reg0;

            case (fsm_b)

                s0 : begin
                    sync_reg0 <= 1'b0;
                    sync_reg1 <= 1'b0;
                    out <= 'b0;
                    fsm_b <= s1;
                end

                s1 : begin
                    if (sync_reg1) begin
                        out <= cross;
                    end
                end

                default : begin 
                    fsm_b <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // sync_type0

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////