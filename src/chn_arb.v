/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        chn_arb.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        arbitrates access to PCIe endpoint between channels.
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

module chn_arb (

    input                    clk,
    input                    rst,

    // CHN0 trn
    output reg               chn0_trn,
    input                    chn0_drvn,
    input                    chn0_reqep,

    // REGIF trn
    output reg               regif_trn,
    input                    regif_drvn,
    input                    regif_reqep
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
    // Local chn_arb
    //-------------------------------------------------------   
    reg          [7:0]       chn_arb_fsm;
    reg                      turn_bit;

    ////////////////////////////////////////////////
    // chn_arb
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            chn_arb_fsm <= s0;
        end
        
        else begin  // not rst

            case (chn_arb_fsm)

                s0 : begin
                    chn0_trn <= 1'b0;
                    regif_trn <= 1'b0;
                    chn_arb_fsm <= s1;
                end

                s1 : begin
                    if (!chn0_drvn && !regif_drvn) begin
                        if (regif_reqep && turn_bit) begin
                            regif_trn <= 1'b1;
                        end
                        else if (chn0_reqep) begin
                            chn0_trn <= 1'b1;
                        end
                        turn_bit <= ~turn_bit;
                        chn_arb_fsm <= s0;
                    end
                end

                default : begin 
                    chn_arb_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // chn_arb

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////