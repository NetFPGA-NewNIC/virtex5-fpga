/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        axis2ibuf.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives AXI4-Stream and writes to ibuf.
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

module ibuf2axis # (
    parameter BW = 10,
    parameter DST_PORT = 8'h00
    ) (

    input                    s_axis_aclk,
    input                    s_axis_aresetp,

    // AXIS
    input        [63:0]      s_axis_tdata,
    input        [7:0]       s_axis_tstrb,
    input        [127:0]     s_axis_tuser,
    input                    s_axis_tvalid,
    input                    s_axis_tlast,
    output reg               s_axis_tready,

    // ibuf2mac
    output       [BW:0]      committed_prod,
    input        [BW:0]      committed_cons,

    // ibuf
    output       [BW-1:0]    wr_addr,
    output       [63:0]      wr_data
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

    localparam MAX_DIFF = (2**BW) - 10;

    //-------------------------------------------------------
    // Local ibuf2axis
    //-------------------------------------------------------
    reg          [7:0]       rx_fsm;
    reg          [BW:0]      diff;
    reg          [BW:0]      wr_addr_i;
    reg          [63:0]      ax_wr_data;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign wr_addr = wr_addr_i;
    assign committed_prod = wr_addr_i;

    ////////////////////////////////////////////////
    // ibuf2axis
    ////////////////////////////////////////////////
    always @(posedge s_axis_aclk or posedge s_axis_aresetp) begin

        if (s_axis_aresetp) begin  // rst
            s_axis_tready <= 1'b0;
            rx_fsm <= s0;
        end
        
        else begin  // not rst
            
            diff <= wr_addr_i + (~committed_cons) +1;

            case (rx_fsm)

                s0 : begin
                    wr_addr_i <= 'b0;
                    diff <= 'b0;
                    s_axis_tready <= 1'b1;
                    rx_fsm <= s1;
                end

                s1 : begin
                    wr_data <= {1'b0, 15'b0, s_axis_tuser[15:0], 8'b0, 8'b0, 8'b0, 8'b0};
                    ax_wr_data <= s_axis_tdata;
                    if (s_axis_tvalid && !s_axis_tlast) begin
                        if (s_axis_tuser[31:24] == DST_PORT) begin
                            s_axis_tready <= 1'b0;
                            rx_fsm <= s2;
                        end
                        else begin
                            rx_fsm <= s5;
                        end
                    end
                end

                s2 : begin
                    wr_data <= ax_wr_data;
                    wr_addr_i <= wr_addr_i + 1;
                    s_axis_tready <= 1'b1;
                    rx_fsm <= s3;
                end

                s3 : begin
                    wr_data <= s_axis_tdata;
                    if (s_axis_tvalid) begin
                        wr_addr_i <= wr_addr_i + 1;
                    end

                    if (s_axis_tvalid && s_axis_tlast) begin
                        rx_fsm <= s1;
                    end
                    else if (diff > MAX_DIFF) begin           // ibufer is almost full
                        s_axis_tready <= 1'b0;
                        rx_fsm <= s4;
                    end
                end

                s4 : begin
                    if (diff < MAX_DIFF) begin
                        s_axis_tready <= 1'b1;
                        rx_fsm <= s3;
                    end
                end

                s5 : begin
                    if (s_axis_tvalid && s_axis_tlast) begin
                        rx_fsm <= s1;
                    end
                end

                default : begin 
                    rx_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // axis2ibuf

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////