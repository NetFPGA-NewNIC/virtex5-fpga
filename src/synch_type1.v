/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        synch_type1.v
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
`include "includes.v"

module synch_type1 #(
    parameter W = 32,
    parameter SENSITIVE_OUTPUT = 0) (

    input    clk_out,                       // freq(clk_out) > freq(clk_in)
    input    reset_clk_out,

    input    clk_in,
    input    reset_clk_in,

    input         [W:0]        in,
    output reg    [W:0]        out,

    output reg                 update
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
    // Local a
    //-------------------------------------------------------
    reg     [7:0]    fsm_a;
    reg     [W:0]    bus_in_last;
    reg              synch;
    reg     [W:0]    cross;

    //-------------------------------------------------------
    // Local b
    //-------------------------------------------------------
    reg              synch_reg0;
    reg              synch_reg1;

    ////////////////////////////////////////////////
    // a
    ////////////////////////////////////////////////
    always @(posedge clk_in) begin

        if (reset_clk_in) begin  // reset
            synch <= 1'b0;
            fsm_a <= s0;
        end
        
        else begin  // not reset

            case (fsm_a)

                s0 : begin
                    bus_in_last <= 'b0;
                    fsm_a <= s1;
                end

                s1 : begin
                    if (bus_in_last != in) begin
                        cross <= in;
                        fsm_a <= s2;
                    end
                end

                s2 : begin
                    bus_in_last <= cross;
                    synch <= 1'b1;
                    fsm_a <= s3;
                end

                s3 : begin
                    synch <= 1'b0;
                    fsm_a <= s4;
                end

                s4 : fsm_a <= s5;
                s5 : fsm_a <= s6;
                s6 : fsm_a <= s7;
                s7 : fsm_a <= s1;

                default : begin 
                    fsm_a <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // b
    ////////////////////////////////////////////////
    always @(posedge clk_out) begin

        if (reset_clk_out) begin  // reset
            synch_reg0 <= 1'b0;
            synch_reg1 <= 1'b0;
            update <= 1'b0;
            if (SENSITIVE_OUTPUT)
                out <= 'b0;
        end
        
        else begin  // not reset

            synch_reg0 <= synch;
            synch_reg1 <= synch_reg0;

            update <= 1'b0;

            if (synch_reg1) begin
                update <= 1'b1;
                out <= cross;
            end

        end     // not reset
    end  //always

endmodule // synch_type1

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////