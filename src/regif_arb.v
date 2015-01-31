/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        regif_arb.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Arbitrates access to PCIe endpoint between subsystems.
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

module regif_arb (

    input                    reg_int_clk,
    input                    reg_int_reset_n,

    input                    pcie_clk,
    input                    pcie_rst,

    // CHN trn
    input                    chn_trn,
    output reg               chn_drvn,
    output reg               chn_reqep,

    // EP ARB

    // WRIF
    output reg               ep_wrif_trn,
    input                    ep_wrif_drvn,
    input                    ep_wrif_reqep,

    // RDIF
    output reg               ep_rdif_trn,
    input                    ep_rdif_drvn,
    input                    ep_rdif_reqep,

    // REGIF ARB

    // WRIF
    output reg               wrif_trn,
    input                    wrif_drvn,

    // RDIF
    output reg               rdif_trn,
    input                    rdif_drvn
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
    // Local EP ARB
    //-------------------------------------------------------   
    reg          [7:0]       ep_arb_fsm;
    reg                      ep_turn_bit;

    //-------------------------------------------------------
    // Local REGIF ARB
    //-------------------------------------------------------   
    reg          [7:0]       regif_arb_fsm;
    reg                      regif_turn_bit;

    ////////////////////////////////////////////////
    // EP ARB
    ////////////////////////////////////////////////
    always @(posedge pcie_clk) begin

        if (pcie_rst) begin  // rst
            ep_arb_fsm <= s0;
        end
        
        else begin  // not rst

            ep_wrif_trn <= 1'b0;
            ep_rdif_trn <= 1'b0;

            case (ep_arb_fsm)

                s0 : begin
                    chn_drvn <= 1'b0;
                    chn_reqep <= 1'b0;
                    ep_arb_fsm <= s1;
                end

                s1 : begin
                    if (ep_wrif_reqep || ep_rdif_reqep) begin
                        chn_reqep <= 1'b1;
                        ep_arb_fsm <= s2;
                    end
                end

                s2 : begin
                    if (chn_trn) begin
                        chn_drvn <= 1'b1;
                        chn_reqep <= 1'b0;
                        if (ep_wrif_reqep) begin
                            ep_wrif_trn <= 1'b1;
                        end
                        else begin
                            ep_rdif_trn <= 1'b1;
                        end
                        ep_turn_bit <= ~ep_turn_bit;
                        ep_arb_fsm <= s3;
                    end
                end

                s3 : ep_arb_fsm <= s4;

                s4 : begin
                    if ((!ep_wrif_drvn) && (!ep_rdif_drvn)) begin
                        chn_drvn <= 1'b0;
                        ep_arb_fsm <= s1;
                    end
                end

                default : begin 
                    ep_arb_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // REGIF ARB
    ////////////////////////////////////////////////
    always @(posedge reg_int_clk) begin

        if (!reg_int_reset_n) begin  // rst
            regif_arb_fsm <= s0;
        end
        
        else begin  // not rst

            wrif_trn <= 1'b0;
            rdif_trn <= 1'b0;

            case (regif_arb_fsm)

                s0 : begin
                    regif_arb_fsm <= s1;
                end

                s1 : begin
                    if ((!wrif_drvn) && (!rdif_drvn)) begin
                        regif_turn_bit <= ~regif_turn_bit;
                        if (!regif_turn_bit) begin
                            wrif_trn <= 1'b1;
                        end
                        else begin
                            rdif_trn <= 1'b1;
                        end
                        regif_arb_fsm <= s0;
                    end
                end

                default : begin 
                    regif_arb_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // regif_arb

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////