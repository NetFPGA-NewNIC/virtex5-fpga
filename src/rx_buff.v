/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_buff.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Internal buffers
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

module rx_buff # (
    parameter  AW = 10,
    parameter  DW = 64) ( 

    input      [AW-1:0]     a,
    input      [DW-1:0]     d,
    input      [AW-1:0]     dpra,
    input                   clk,
    input                   qdpo_clk,
    output reg [DW-1:0]     qdpo
    );

    //-------------------------------------------------------
    // Local port a
    //-------------------------------------------------------
    reg     [AW-1:0]     a_reg;
    reg     [DW-1:0]     d_reg;
    reg     [DW-1:0]     dpram_0[(2**(AW-1))-1:0];
    reg     [DW-1:0]     dpram_1[(2**(AW-1))-1:0];

    //-------------------------------------------------------
    // Local port b
    //-------------------------------------------------------
    reg     [AW-1:0]     dpra_reg;

    ////////////////////////////////////////////////
    // port a
    ////////////////////////////////////////////////
    always @(posedge clk) begin
        a_reg <= a;
        d_reg <= d;
        if (!a_reg[AW-1]) begin
            dpram_0[a_reg[AW-2:0]] <= d_reg;
        end
        else begin
            dpram_1[a_reg[AW-2:0]] <= d_reg;
        end
    end  //always

    ////////////////////////////////////////////////
    // port b
    ////////////////////////////////////////////////
    always @(posedge qdpo_clk) begin
        dpra_reg <= dpra;
        if (!dpra_reg[AW-1]) begin
            qdpo <= dpram_0[dpra_reg[AW-2:0]];
        end
        else begin
            qdpo <= dpram_1[dpra_reg[AW-2:0]];
        end
    end  //always

endmodule // rx_buff

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////