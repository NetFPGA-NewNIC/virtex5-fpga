/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_rd_addr_synch.v
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

module tx_rd_addr_synch (

    input    clk_out,
    input    reset_n_clk_out,

    input    clk_in,
    input    reset_n_clk_in,

    input         [9:0]     commited_rd_addr_in,
    output reg    [9:0]     commited_rd_addr_out
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
    reg     [9:0]  bus_in_last;
    reg              synch;
    reg     [9:0]  cross;

    //-------------------------------------------------------
    // Local b
    //-------------------------------------------------------
    reg              synch_reg0;
    reg              synch_reg1;
    reg     [9:0]  cross_reg0;

    ////////////////////////////////////////////////
    // a
    ////////////////////////////////////////////////
    always @( posedge clk_in or negedge reset_n_clk_in ) begin

        if (!reset_n_clk_in ) begin  // reset
            bus_in_last <= 'b0;
            synch <= 1'b0;
            fsm_a <= s0;
        end
        
        else begin  // not reset

            case (fsm_a)

                s0 : begin
                    if (bus_in_last != commited_rd_addr_in) begin
                        cross <= commited_rd_addr_in;
                        fsm_a <= s1;
                    end
                end

                s1 : begin
                    bus_in_last <= cross;
                    synch <= 1'b1;
                    fsm_a <= s2;
                end

                s2 : begin
                    synch <= 1'b0;
                    fsm_a <= s3;
                end

                s3 : fsm_a <= s4;
                s4 : fsm_a <= s5;
                s5 : fsm_a <= s6;
                s6 : fsm_a <= s0;

                default : begin 
                    fsm_a <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // b
    ////////////////////////////////////////////////
    always @( posedge clk_out or negedge reset_n_clk_out ) begin

        if (!reset_n_clk_out ) begin  // reset
            commited_rd_addr_out <= 'b0;
            synch_reg0 <= 1'b0;
            synch_reg1 <= 1'b0;
        end
        
        else begin  // not reset

            cross_reg0 <= cross;
            synch_reg0 <= synch;
            synch_reg1 <= synch_reg0;

            if (synch_reg1) begin
                commited_rd_addr_out <= cross_reg0;
            end

        end     // not reset
    end  //always

endmodule // tx_rd_addr_synch

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////