/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_hst_ctrl.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives lbuf addr and enable.
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
`default_nettype none
`include "includes.v"

module rx_hst_ctrl # (
    parameter BARHIT = 2,
    parameter BARMP_LBUF1_ADDR = 6'bxxxxxx,
    parameter BARMP_LBUF1_EN = 6'bxxxxxx,
    parameter BARMP_LBUF2_ADDR = 6'bxxxxxx,
    parameter BARMP_LBUF2_EN = 6'bxxxxxx
    ) (

    input                    clk,
    input                    rst,

    // TRN rx
    input        [63:0]      trn_rd,
    input        [7:0]       trn_rrem_n,
    input                    trn_rsof_n,
    input                    trn_reof_n,
    input                    trn_rsrc_rdy_n,
    input        [6:0]       trn_rbar_hit_n,

    // lbuf_mgmt
    output reg   [63:0]      lbuf1_addr,
    output reg               lbuf1_en,
    input                    lbuf1_dn,

    output reg   [63:0]      lbuf2_addr,
    output reg               lbuf2_en,
    input                    lbuf2_dn
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
    // Local Rx TLP
    //-------------------------------------------------------
    reg          [7:0]       tlp_rx_fsm;
    reg                      lbuf1_en_i;
    reg                      lbuf2_en_i;
    reg          [31:0]      aux_dw;
    reg          [63:0]      lbuf1_addr_i;
    reg          [63:0]      lbuf2_addr_i;

    ////////////////////////////////////////////////
    // Output driver
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            lbuf1_en <= 1'b0;
            lbuf2_en <= 1'b0;
        end
        
        else begin  // not rst
            if (lbuf1_en_i) 
                lbuf1_en <= 1'b1;
            else if (lbuf1_dn) 
                lbuf1_en <= 1'b0;

            if (lbuf2_en_i) 
                lbuf2_en <= 1'b1;
            else if (lbuf2_dn) 
                lbuf2_en <= 1'b0;

        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // Rx TLP
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            lbuf1_en_i <= 1'b0;
            lbuf2_en_i <= 1'b0;
            tlp_rx_fsm <= s0;
        end
        
        else begin  // not rst

            lbuf1_en_i <= 1'b0;
            lbuf2_en_i <= 1'b0;

            lbuf1_addr <= lbuf1_addr_i;
            lbuf2_addr <= lbuf2_addr_i;

            case (tlp_rx_fsm)

                s0 : begin
                    if ((!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rbar_hit_n[BARHIT])) begin
                        if (trn_rd[62:56] == `MEM_WR32_FMT_TYPE) begin
                            tlp_rx_fsm <= s1;
                        end
                        else if (trn_rd[62:56] == `MEM_WR64_FMT_TYPE) begin
                            tlp_rx_fsm <= s4;
                        end
                    end
                end

                s1 : begin
                    aux_dw <= trn_rd[31:0];
                    if (!trn_rsrc_rdy_n) begin
                        case (trn_rd[39:34])

                            BARMP_LBUF1_ADDR : begin
                                tlp_rx_fsm <= s2;
                            end

                            BARMP_LBUF2_ADDR : begin
                                tlp_rx_fsm <= s3;
                            end

                            BARMP_LBUF1_EN : begin
                                lbuf1_en_i <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            BARMP_LBUF2_EN : begin
                                lbuf2_en_i <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s2 : begin
                    lbuf1_addr_i[31:0] <= dw_endian_conv(aux_dw);
                    lbuf1_addr_i[63:32] <= dw_endian_conv(trn_rd[63:32]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s3 : begin
                    lbuf2_addr_i[31:0] <= dw_endian_conv(aux_dw);
                    lbuf2_addr_i[63:32] <= dw_endian_conv(trn_rd[63:32]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s4 : begin
                    if (!trn_rsrc_rdy_n) begin
                        case (trn_rd[7:2])

                            BARMP_LBUF1_ADDR : begin
                                tlp_rx_fsm <= s5;
                            end

                            BARMP_LBUF2_ADDR : begin
                                tlp_rx_fsm <= s6;
                            end

                            BARMP_LBUF1_EN : begin
                                lbuf1_en_i <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            BARMP_LBUF2_EN : begin
                                lbuf2_en_i <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s5 : begin
                    lbuf1_addr_i[31:0] <= dw_endian_conv(trn_rd[63:32]);
                    lbuf1_addr_i[63:32] <= dw_endian_conv(trn_rd[31:0]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s6 : begin
                    lbuf2_addr_i[31:0] <= dw_endian_conv(trn_rd[63:32]);
                    lbuf2_addr_i[63:32] <= dw_endian_conv(trn_rd[31:0]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    tlp_rx_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // rx_hst_ctrl

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////