/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        ibuf2axis.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Reads ibuf and send through AXI4-Stream.
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
    parameter BW = 10
    ) (

    input                    m_axis_aclk,
    input                    m_axis_aresetp,

    // AXIS
    output reg   [63:0]      m_axis_tdata,
    output reg   [7:0]       m_axis_tstrb,
    output reg   [127:0]     m_axis_tuser,
    output reg               m_axis_tvalid,
    output reg               m_axis_tlast,
    input                    m_axis_tready,

    // mac2ibuf
    input        [BW:0]      committed_prod,
    output       [BW:0]      committed_cons,

    // ibuf
    output       [BW-1:0]    rd_addr,
    input        [63:0]      rd_data
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
    // Local snd_fsm
    //-------------------------------------------------------   
    reg          [7:0]       snd_fsm;
    reg          [15:0]      len;
    reg          [BW:0]      rd_addr_i;
    reg          [BW:0]      diff;
    reg          [7:0]       last_tstrb;
    reg          [12:0]      qw_len;
    reg          [12:0]      qw_snt;
    reg          [63:0]      ax_rd_data;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign rd_addr = rd_addr_i;
    assign committed_cons = rd_addr_i;

    ////////////////////////////////////////////////
    // snd_fsm
    ////////////////////////////////////////////////
    always @(posedge m_axis_aclk or posedge m_axis_aresetp) begin

        if (m_axis_aresetp) begin  // rst
            m_axis_tvalid <= 1'b0;
            snd_fsm <= s0;
        end
        
        else begin  // not rst

            diff <= committed_prod + (~rd_addr_i) +1;

            case (snd_fsm)

                s0 : begin
                    diff <= 'b0;
                    rd_addr_i <= 'b0;
                    snd_fsm <= s1;
                end

                s1 : begin
                    len <= rd_data[47:32];
                    qw_len <= rd_data[47:35];
                    if (diff) begin
                        rd_addr_i <= rd_addr_i + 1;
                        snd_fsm <= s2;
                    end
                end

                s2 : begin
                    if (len[2:0]) begin
                        qw_len <= len[15:3] + 1;
                    end

                    (* parallel_case *)
                    case (len[2:0])                    // my deco
                        3'b000 : begin
                            last_tstrb <= 8'b11111111;
                        end
                        3'b001 : begin
                            last_tstrb <= 8'b00000001;
                        end
                        3'b010 : begin
                            last_tstrb <= 8'b00000011;
                        end
                        3'b011 : begin
                            last_tstrb <= 8'b00000111;
                        end
                        3'b100 : begin
                            last_tstrb <= 8'b00001111;
                        end
                        3'b101 : begin
                            last_tstrb <= 8'b00011111;
                        end
                        3'b110 : begin
                            last_tstrb <= 8'b00111111;
                        end
                        3'b111 : begin
                            last_tstrb <= 8'b01111111;
                        end
                    endcase
                    rd_addr_i <= rd_addr_i + 1;
                    snd_fsm <= s3;
                end

                s3 : begin
                    m_axis_tdata <= rd_data;
                    m_axis_tstrb <= 8'hFF;
                    m_axis_tuser[15:0] <= len;
                    m_axis_tvalid <= 1'b1;
                    m_axis_tlast <= 1'b0;
                    rd_addr_i <= rd_addr_i + 1;
                    qw_snt <= 'h2;
                    snd_fsm <= s4;
                end

                s4 : begin
                    ax_rd_data <= rd_data;
                    if (m_axis_tready) begin
                        rd_addr_i <= rd_addr_i + 1;
                        m_axis_tdata <= rd_data;
                        qw_snt <= qw_snt + 1;
                        if (qw_len == qw_snt) begin
                            rd_addr_i <= rd_addr_i;
                            m_axis_tstrb <= last_tstrb;
                            m_axis_tlast <= 1'b1;
                            snd_fsm <= s6;
                        end
                    end
                    else begin
                        snd_fsm <= s5;
                    end
                end

                s5 : begin
                    if (m_axis_tready) begin
                        rd_addr_i <= rd_addr_i + 1;
                        m_axis_tdata <= ax_rd_data;
                        qw_snt <= qw_snt + 1;
                        if (qw_len == qw_snt) begin
                            rd_addr_i <= rd_addr_i;
                            m_axis_tstrb <= last_tstrb;
                            m_axis_tlast <= 1'b1;
                            snd_fsm <= s6;
                        end
                        else begin
                            snd_fsm <= s4;
                        end
                    end
                end

                s6 : begin
                    len <= rd_data[47:32];
                    qw_len <= rd_data[47:35];
                    if (m_axis_tready) begin
                        m_axis_tlast <= 1'b0;
                        m_axis_tvalid <= 1'b0;
                        if (diff) begin
                            rd_addr_i <= rd_addr_i + 1;
                            snd_fsm <= s2;
                        end
                        else begin
                            snd_fsm <= s1;
                        end
                    end
                end

                default : begin 
                    snd_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // ibuf2axis

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////