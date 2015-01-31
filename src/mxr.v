/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mxr.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Arbitrates access to PCIe endpoint between subsystems. For testing only.
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

module mxr (

    input                    clk,
    input                    arst,

    // MAC A
    input        [63:0]      s_axis_A_tdata,
    input        [7:0]       s_axis_A_tstrb,
    input        [127:0]     s_axis_A_tuser,
    input                    s_axis_A_tvalid,
    input                    s_axis_A_tlast,
    output reg               s_axis_A_tready,

    // MAC D
    input        [63:0]      s_axis_D_tdata,
    input        [7:0]       s_axis_D_tstrb,
    input        [127:0]     s_axis_D_tuser,
    input                    s_axis_D_tvalid,
    input                    s_axis_D_tlast,
    output reg               s_axis_D_tready,

    // 2DMA
    output reg   [63:0]      m_axis_tdata,
    output reg   [7:0]       m_axis_tstrb,
    output reg   [127:0]     m_axis_tuser,
    output reg               m_axis_tvalid,
    output reg               m_axis_tlast,
    input                    m_axis_tready
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
    always @(posedge clk or posedge arst) begin

        if (arst) begin  // rst
            s_axis_A_tready <= 1'b0;
            s_axis_D_tready <= 1'b0;
            m_axis_tvalid <= 1'b0;
            arb_fsm <= s0;
        end
        
        else begin  // not rst

            case (arb_fsm)

                s0 : begin
                    arb_fsm <= s1;
                end

                s1 : begin
                    if (s_axis_A_tvalid) begin
                        m_axis_tdata <= s_axis_A_tdata;
                        m_axis_tstrb <= s_axis_A_tstrb;
                        m_axis_tuser <= s_axis_A_tuser;
                        m_axis_tvalid <= s_axis_A_tvalid;
                        m_axis_tlast <= s_axis_A_tlast;
                        s_axis_A_tready <= m_axis_tready;
                        arb_fsm <= s2;
                    end
                    else if (s_axis_D_tvalid) begin
                        m_axis_tdata <= s_axis_D_tdata;
                        m_axis_tstrb <= s_axis_D_tstrb;
                        m_axis_tuser <= s_axis_D_tuser;
                        m_axis_tvalid <= s_axis_D_tvalid;
                        m_axis_tlast <= s_axis_D_tlast;
                        s_axis_D_tready <= m_axis_tready;
                        arb_fsm <= s2;
                    end
                    else begin
                        s_axis_A_tready <= 1'b0;
                        s_axis_D_tready <= 1'b0;
                        m_axis_tvalid <= 1'b0;
                    end
                end

                s2 : begin
                    if (m_axis_tvalid && m_axis_tready && m_axis_tlast) begin
                        s_axis_A_tready <= 1'b0;
                        s_axis_D_tready <= 1'b0;
                        m_axis_tvalid <= 1'b0;
                        arb_fsm <= s1;
                    end
                end

                default : begin 
                    arb_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // mxr

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////