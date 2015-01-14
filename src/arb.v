/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        arb.v
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

module arb (

    input                    clk,
    input                    rst,

    // CHN trn
    input                    chn_trn,
    output reg               chn_drvn,
    output reg               chn_reqep,

    // ARB

    // Tx
    output reg               tx_trn,
    input                    tx_drvn,
    input                    tx_reqep,

    // Rx
    output reg               rx_trn,
    input                    rx_drvn,

    // IRQ
    output reg               irq_trn,
    input                    irq_drvn,
    input                    irq_reqep
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
    // Local ARB
    //-------------------------------------------------------   
    reg          [7:0]       arb_fsm;
    reg                      turn_bit;

    ////////////////////////////////////////////////
    // ARB
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            arb_fsm <= s0;
        end
        
        else begin  // not rst

            chn_reqep <= 1'b1;
            tx_trn <= 1'b0;
            rx_trn <= 1'b0;
            irq_trn <= 1'b0;

            case (arb_fsm)

                s0 : begin
                    chn_drvn <= 1'b0;
                    arb_fsm <= s1;
                end

                s1 : begin
                    if (chn_trn) begin
                        chn_drvn <= 1'b1;
                        if (irq_reqep) begin
                            irq_trn <= 1'b1;
                        end
                        else if (tx_reqep && turn_bit) begin
                            tx_trn <= 1'b1;
                        end
                        else begin
                            rx_trn <= 1'b1;
                        end
                        turn_bit <= ~turn_bit;
                        arb_fsm <= s2;
                    end
                end

                s2 : arb_fsm <= s3;

                s3 : begin
                    if ((!tx_drvn) && (!rx_drvn) && (!irq_drvn)) begin
                        chn_drvn <= 1'b0;
                        arb_fsm <= s1;
                    end
                end

                default : begin 
                    arb_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // arb

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////