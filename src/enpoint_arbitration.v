/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        enpoint_arbitration.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Arbitrates access to PCIe endpoint between all subsystems.
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

module enpoint_arbitration (

    input    trn_clk,
    input    trn_lnk_up_n,

    // Rx
    output reg             rx_turn,
    input                  rx_driven,

    // Tx
    output reg             tx_turn,
    input                  tx_driven

    );

    wire            reset_n;
    
    // localparam
    localparam s0 = 8'b00000000;
    localparam s1 = 8'b00000001;
    localparam s2 = 8'b00000010;
    localparam s3 = 8'b00000100;

    //-------------------------------------------------------
    // Local send_tlps_machine
    //-------------------------------------------------------   
    reg     [7:0]   fsm;
    reg             turn_bit;

    assign reset_n = ~trn_lnk_up_n;


    ////////////////////////////////////////////////
    // Arbitration
    ////////////////////////////////////////////////
    always @( posedge trn_clk or negedge reset_n ) begin

        if (!reset_n ) begin  // reset
            rx_turn <= 1'b0;
            tx_turn <= 1'b0;
            turn_bit <= 1'b0;
            fsm <= s0;
        end
        
        else begin  // not reset

            case (fsm)

                s0 : begin
                    if ( (!rx_driven) && (!tx_driven) ) begin
                        turn_bit <= ~turn_bit;
                        if (!turn_bit) begin
                            rx_turn <= 1'b1;
                        end
                        else begin
                            tx_turn <= 1'b1;
                        end
                        fsm <= s1;
                    end
                end

                s1 : begin
                    rx_turn <= 1'b0;
                    tx_turn <= 1'b0;
                    fsm <= s0;
                end

                default : begin 
                    fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // enpoint_arbitration

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////