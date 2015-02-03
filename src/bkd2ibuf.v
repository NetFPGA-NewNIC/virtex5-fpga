/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        bkd2ibuf.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Backend packets 2 internal buff
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

module bkd2ibuf # (
    parameter BW = 10,
    parameter CONFIG_TIMESTAMP = 0
    ) (

    input                    clk,
    input                    rst,

    // BKD rx
    input        [63:0]      s_axis_tdata,
    input        [7:0]       s_axis_tstrb,
    input        [127:0]     s_axis_tuser,
    input                    s_axis_tvalid,
    input                    s_axis_tlast,
    output reg               s_axis_tready,

    // ibuf
    output reg   [BW-1:0]    wr_addr,
    output reg   [63:0]      wr_data,

    // fwd logic
    input                    hst_rdy,
    output reg               activity,
    output reg   [BW:0]      committed_prod,
    input        [BW:0]      committed_cons
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
    // Local bkd2ibuf
    //-------------------------------------------------------
    reg          [7:0]       rx_fsm;
    reg          [15:0]      len;
    reg          [7:0]       src_port;
    reg          [7:0]       des_port;
    reg          [63:0]      timestamp;
    reg          [BW:0]      ax_wr_addr;
    reg          [BW:0]      ax_ts_wr_addr;
    reg          [BW:0]      diff;
    reg          [BW:0]      nxt_committed_prod;
    reg                      hst_rdy_reg0;
    reg                      hst_rdy_reg1;

    ////////////////////////////////////////////////
    // Inbound ethernet frame to ibuf
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            s_axis_tready <= 1'b0;
            rx_fsm <= s0;
        end
        
        else begin  // not rst
            
            diff <= ax_wr_addr + (~committed_cons) +1;
            activity <= 1'b0;

            hst_rdy_reg0 <= hst_rdy;
            hst_rdy_reg1 <= hst_rdy_reg0;

            case (rx_fsm)

                s0 : begin
                    committed_prod <= 'b0;
                    hst_rdy_reg0 <= 1'b0;
                    if (CONFIG_TIMESTAMP) begin
                        ax_wr_addr <= 'h2;
                    end
                    else begin
                        ax_wr_addr <= 'h1;
                    end
                    rx_fsm <= s1;
                end

                s1 : begin
                    if (hst_rdy_reg1) begin
                        s_axis_tready <= 1'b1;
                        rx_fsm <= s2;
                    end
                end

                s2 : begin
                    if (s_axis_tlast && s_axis_tvalid) begin
                        rx_fsm <= s4;
                    end
                    else if (s_axis_tvalid) begin
                        rx_fsm <= s3;
                    end
                    else begin
                        rx_fsm <= s4;
                    end
                end

                s3 : begin
                    if (s_axis_tlast && s_axis_tvalid) begin
                        rx_fsm <= s4;
                    end
                end

                s4 : begin
                    len <= s_axis_tuser[15:0];
                    src_port <= s_axis_tuser[23:16];
                    des_port <= s_axis_tuser[31:24];
                    timestamp <= s_axis_tuser[95:32];
                    
                    wr_data <= s_axis_tdata;
                    wr_addr <= ax_wr_addr;
                    if (s_axis_tvalid) begin
                        ax_wr_addr <= ax_wr_addr +1;
                        rx_fsm <= s5;
                    end
                end

                s5 : begin
                    activity <= 1'b1;
                    wr_data <= s_axis_tdata;
                    wr_addr <= ax_wr_addr;
                    if (s_axis_tvalid) begin
                        ax_wr_addr <= ax_wr_addr +1;
                    end

                    if (s_axis_tlast && s_axis_tvalid) begin
                        s_axis_tready <= 1'b0;
                        rx_fsm <= s6;
                    end
                    else if (diff > MAX_DIFF) begin           // ibufer is almost full
                        s_axis_tready <= 1'b0;
                        rx_fsm <= s8;
                    end
                end

                s6 : begin
                    activity <= 1'b1;
                    wr_data <= {1'b0, 15'b0, len, 8'b0, des_port, 8'b0, src_port};
                    wr_addr <= committed_prod;

                    if (CONFIG_TIMESTAMP) begin
                        nxt_committed_prod <= ax_wr_addr;
                        ax_wr_addr <= ax_wr_addr +1;
                        ax_ts_wr_addr <= committed_prod +1;
                        rx_fsm <= s7;
                    end
                    else begin
                        committed_prod <= ax_wr_addr;            // commit the packet
                        ax_wr_addr <= ax_wr_addr +1;
                        s_axis_tready <= 1'b1;
                        rx_fsm <= s4;
                    end
                end

                s7 : begin
                    activity <= 1'b1;
                    committed_prod <= nxt_committed_prod;        // commit the packet
                    wr_data <= timestamp;
                    wr_addr <= ax_ts_wr_addr;
                    ax_wr_addr <= ax_wr_addr +1;
                    s_axis_tready <= 1'b1;
                    rx_fsm <= s4;
                end

                s8 : begin
                    if (diff < MAX_DIFF) begin
                        s_axis_tready <= 1'b1;
                        rx_fsm <= s5;
                    end
                end

                default : begin 
                    rx_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // bkd2ibuf

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////