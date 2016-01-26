/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        gc.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Monitors pulled data reception.
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

module gc (

    input                    clk,
    input                    rst,

    // lbuf_mgmt
    input                    rd_lbuf,
    output reg               wt_lbuf,
    input        [63:0]      lbuf_addr,
    input        [31:0]      lbuf_len,

    // rcv_cpl
    input                    cpl_rcved,
    input        [9:0]       cpl_dws,

    // gc updt
    output reg   [63:0]      gc_addr,
    output reg               gc_updt,
    input                    gc_updt_ack
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
    // Local gc
    //-------------------------------------------------------   
    reg          [7:0]       mon_fsm;
    reg          [63:0]      lbuf_addr_reg;
    reg          [31:0]      lbuf_len_reg;
    reg          [31:0]      dw_cnt;
    reg          [31:0]      nxt_dw_cnt;

    ////////////////////////////////////////////////
    // gc
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            wt_lbuf <= 1'b0;
            mon_fsm <= s0;
        end
        
        else begin  // not rst

            gc_addr <= lbuf_addr_reg + {lbuf_len_reg, 3'b0};

            case (mon_fsm)

                s0 : begin
                    gc_updt <= 1'b0;
                    mon_fsm <= s1;
                end

                s1 : begin
                    lbuf_addr_reg <= lbuf_addr;
                    lbuf_len_reg <= lbuf_len;
                    dw_cnt <= 'b0;
                    if (rd_lbuf) begin
                        mon_fsm <= s2;
                    end
                end

                s2 : begin
                    wt_lbuf <= 1'b1;
                    nxt_dw_cnt <= dw_cnt + cpl_dws;
                    if (cpl_rcved) begin
                        mon_fsm <= s3;
                    end
                end

                s3 : begin
                    dw_cnt <= nxt_dw_cnt;
                    mon_fsm <= s4;
                end

                s4 : begin
                    if ({lbuf_len_reg, 1'b0} == dw_cnt) begin
                        gc_updt <= 1'b1;
                        mon_fsm <= s5;
                    end
                    else begin
                        mon_fsm <= s2;
                    end
                end

                s5 : begin
                    if (gc_updt_ack) begin
                        wt_lbuf <= 1'b0;
                        gc_updt <= 1'b0;
                        if (!rd_lbuf) begin
                            mon_fsm <= s1;
                        end
                        else begin
                            mon_fsm <= s6;
                        end
                    end
                end

                s6 : begin
                    if (!rd_lbuf) begin
                        mon_fsm <= s1;
                    end
                end

                default : begin 
                    mon_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // gc

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////