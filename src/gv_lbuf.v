/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        gv_lbuf.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Gives lbufs.
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

module gv_lbuf (

    input                    clk,
    input                    rst,

    // hst_ctrl
    input        [63:0]      lbuf1_addr,
    input        [31:0]      lbuf1_len,
    input                    lbuf1_en,
    output reg               lbuf1_dn,

    input        [63:0]      lbuf2_addr,
    input        [31:0]      lbuf2_len,
    input                    lbuf2_en,
    output reg               lbuf2_dn,

    // gv_lbuf
    output reg               rd_lbuf1,
    output reg               rd_lbuf2,
    input                    wt_lbuf1,
    input                    wt_lbuf2,
    output reg   [63:0]      lbuf_addr,
    output reg   [31:0]      lbuf_len,
    output reg               lbuf_en,
    output reg               lbuf64b,
    input                    lbuf_dn
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
    // Local gv_lbuf
    //-------------------------------------------------------
    reg          [7:0]       giv_lbuf_fsm;

    ////////////////////////////////////////////////
    // gv_lbuf
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            giv_lbuf_fsm <= s0;
        end

        else begin  // not rst

            lbuf1_dn <= 1'b0;
            lbuf2_dn <= 1'b0;

            case (giv_lbuf_fsm)

                s0 : begin
                    lbuf_en <= 1'b0;
                    rd_lbuf1 <= 1'b0;
                    rd_lbuf2 <= 1'b0;
                    giv_lbuf_fsm <= s1;
                end

                s1 : begin
                    lbuf_addr <= lbuf1_addr;
                    lbuf_len <= lbuf1_len;
                    lbuf64b <= | lbuf1_addr[63:32];
                    if (lbuf1_en && !wt_lbuf1) begin
                        lbuf_en <= 1'b1;
                        rd_lbuf1 <= 1'b1;
                        giv_lbuf_fsm <= s2;
                    end
                end

                s2 : begin
                    if (lbuf_dn) begin
                        lbuf_en <= 1'b0;
                        rd_lbuf1 <= 1'b0;
                        lbuf1_dn <= 1'b1;
                        giv_lbuf_fsm <= s3;
                    end
                end

                s3 : begin
                    lbuf_addr <= lbuf2_addr;
                    lbuf_len <= lbuf2_len;
                    lbuf64b <= | lbuf2_addr[63:32];
                    if (lbuf2_en && !wt_lbuf2) begin
                        lbuf_en <= 1'b1;
                        rd_lbuf2 <= 1'b1;
                        giv_lbuf_fsm <= s4;
                    end
                end

                s4 : begin
                    if (lbuf_dn) begin
                        lbuf_en <= 1'b0;
                        rd_lbuf2 <= 1'b0;
                        lbuf2_dn <= 1'b1;
                        giv_lbuf_fsm <= s1;
                    end
                end

                default : begin
                    giv_lbuf_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // gv_lbuf

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////