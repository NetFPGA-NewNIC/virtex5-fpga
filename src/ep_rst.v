/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        ep_rst.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Synchronizes active high reset
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

module ep_rst (

    input                    clk250,
    input                    trn_reset_n,
    input                    trn_lnk_up_n,
    output reg               rst250
    );

    // localparam
    localparam s0  = 15'b000000000000000;
    localparam s1  = 15'b000000000000001;
    localparam s2  = 15'b000000000000010;
    localparam s3  = 15'b000000000000100;
    localparam s4  = 15'b000000000001000;
    localparam s5  = 15'b000000000010000;
    localparam s6  = 15'b000000000100000;
    localparam s7  = 15'b000000001000000;
    localparam s8  = 15'b000000010000000;
    localparam s9  = 15'b000000100000000;
    localparam s10 = 15'b000001000000000;
    localparam s11 = 15'b000010000000000;
    localparam s12 = 15'b000100000000000;
    localparam s13 = 15'b001000000000000;
    localparam s14 = 15'b010000000000000;
    localparam s15 = 15'b100000000000000;

    //-------------------------------------------------------
    // Local reset
    //-------------------------------------------------------
    reg          [14:0]      reset_fsm = 'b0;

    ////////////////////////////////////////////////
    // reset
    ////////////////////////////////////////////////
    always @(posedge clk250) begin

        if (!trn_reset_n) begin  // reset
            rst250 <= 1'b1;
            reset_fsm <= s0;
        end
        
        else begin  // not reset

            case (reset_fsm)

                s0 : begin
                    rst250 <= 1'b1;
                    reset_fsm <= s1;
                end

                s1 : reset_fsm <= s2;
                s2 : reset_fsm <= s3;
                s3 : reset_fsm <= s4;
                s4 : reset_fsm <= s5;

                s5 : begin
                    if (!trn_lnk_up_n) begin
                        reset_fsm <= s6;
                    end
                end

                s6 : begin
                    rst250 <= 1'b0;
                    reset_fsm <= s7;
                end

                s7 : begin
                    if (trn_lnk_up_n) begin
                        reset_fsm <= s0;
                    end
                end

                default : begin 
                    reset_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

endmodule // ep_rst

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////