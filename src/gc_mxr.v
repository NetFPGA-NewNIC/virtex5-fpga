/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        gc_mxr.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Updates gc in order.
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

module gc_mxr (

    input                    clk,
    input                    rst,

    // gc updt 1
    input        [63:0]      gc1_addr,
    input                    gc1_updt,
    output reg               gc1_updt_ack,

    // gc updt 2
    input        [63:0]      gc2_addr,
    input                    gc2_updt,
    output reg               gc2_updt_ack,

    // gc updt
    output reg   [63:0]      gc_addr,
    output reg               gc_updt,
    input                    gc_updt_ack
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
    // Local gc_mxr
    //-------------------------------------------------------   
    reg          [7:0]       mxr_fsm;

    ////////////////////////////////////////////////
    // gc_mxr
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            mxr_fsm <= s0;
        end
        
        else begin  // not rst

            gc1_updt_ack <= 1'b0;
            gc2_updt_ack <= 1'b0;

            case (mxr_fsm)

                s0 : begin
                    gc_updt <= 1'b0;
                    mxr_fsm <= s1;
                end

                s1 : begin
                    gc_addr <= gc1_addr;
                    if (gc1_updt) begin
                        gc1_updt_ack <= 1'b1;
                        gc_updt <= 1'b1;
                        mxr_fsm <= s2;
                    end
                end

                s2 : begin
                    if (gc_updt_ack) begin
                        gc_updt <= 1'b0;
                        mxr_fsm <= s3;
                    end
                end

                s3 : begin
                    gc_addr <= gc2_addr;
                    if (gc2_updt) begin
                        gc2_updt_ack <= 1'b1;
                        gc_updt <= 1'b1;
                        mxr_fsm <= s4;
                    end
                end

                s4 : begin
                    if (gc_updt_ack) begin
                        gc_updt <= 1'b0;
                        mxr_fsm <= s1;
                    end
                end

                default : begin 
                    mxr_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // gc_mxr

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////