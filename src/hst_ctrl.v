/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        hst_ctrl.v
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
//`default_nettype none

module hst_ctrl # (
    parameter BARHIT = 2,
    parameter BARMP_CPL_ADDR = 6'b111111,
    parameter BARMP_LBUF1_ADDR = 6'b111111,
    parameter BARMP_LBUF1_EN = 6'b111111,
    parameter BARMP_LBUF2_ADDR = 6'b111111,
    parameter BARMP_LBUF2_EN = 6'b111111
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

    // hst_ctrl
    output reg   [63:0]      cpl_addr,

    output reg   [63:0]      lbuf1_addr,
    output reg   [31:0]      lbuf1_len,
    output reg               lbuf1_en,
    input                    lbuf1_dn,

    output reg   [63:0]      lbuf2_addr,
    output reg   [31:0]      lbuf2_len,
    output reg               lbuf2_en,
    input                    lbuf2_dn
    );

    `include "includes.v"
    // localparam
    localparam s0  = 10'b0000000000;
    localparam s1  = 10'b0000000001;
    localparam s2  = 10'b0000000010;
    localparam s3  = 10'b0000000100;
    localparam s4  = 10'b0000001000;
    localparam s5  = 10'b0000010000;
    localparam s6  = 10'b0000100000;
    localparam s7  = 10'b0001000000;
    localparam s8  = 10'b0010000000;
    localparam s9  = 10'b0100000000;
    localparam s10 = 10'b1000000000;

    //-------------------------------------------------------
    // Local Rx TLP
    //-------------------------------------------------------
    reg          [9:0]       tlp_rx_fsm;
    reg                      lbuf1_en_i;
    reg                      lbuf2_en_i;
    reg          [31:0]      aux_dw;
    reg          [63:0]      lbuf1_addr_i;
    reg          [63:0]      lbuf2_addr_i;
    reg          [63:0]      cpl_addr_i;

    ////////////////////////////////////////////////
    // Output driver
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            lbuf1_en <= 1'b0;
            lbuf2_en <= 1'b0;
        end
        
        else begin  // not rst
            if (lbuf1_en_i) begin
                lbuf1_en <= 1'b1;
                lbuf1_len <= dw_endian_conv(aux_dw);
            end
            else if (lbuf1_dn) begin
                lbuf1_en <= 1'b0;
            end

            if (lbuf2_en_i) begin
                lbuf2_en <= 1'b1;
                lbuf2_len <= dw_endian_conv(aux_dw);
            end
            else if (lbuf2_dn) begin
                lbuf2_en <= 1'b0;
            end
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

            cpl_addr <= cpl_addr_i;

            case (tlp_rx_fsm)

                s0 : begin
                    if ((!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rbar_hit_n[BARHIT])) begin
                        if (trn_rd[62:56] == `MEM_WR32_FMT_TYPE) begin
                            tlp_rx_fsm <= s1;
                        end
                        else if (trn_rd[62:56] == `MEM_WR64_FMT_TYPE) begin
                            tlp_rx_fsm <= s5;
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

                            BARMP_CPL_ADDR : begin
                                tlp_rx_fsm <= s4;
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
                    cpl_addr_i[31:0] <= dw_endian_conv(aux_dw);
                    cpl_addr_i[63:32] <= dw_endian_conv(trn_rd[63:32]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s5 : begin
                    if (!trn_rsrc_rdy_n) begin
                        case (trn_rd[7:2])

                            BARMP_LBUF1_ADDR : begin
                                tlp_rx_fsm <= s6;
                            end

                            BARMP_LBUF2_ADDR : begin
                                tlp_rx_fsm <= s7;
                            end

                            BARMP_LBUF1_EN : begin
                                tlp_rx_fsm <= s9;
                            end

                            BARMP_LBUF2_EN : begin
                                tlp_rx_fsm <= s10;
                            end

                            BARMP_CPL_ADDR : begin
                                tlp_rx_fsm <= s8;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s6 : begin
                    lbuf1_addr_i[31:0] <= dw_endian_conv(trn_rd[63:32]);
                    lbuf1_addr_i[63:32] <= dw_endian_conv(trn_rd[31:0]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s7 : begin
                    lbuf2_addr_i[31:0] <= dw_endian_conv(trn_rd[63:32]);
                    lbuf2_addr_i[63:32] <= dw_endian_conv(trn_rd[31:0]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s8 : begin
                    cpl_addr_i[31:0] <= dw_endian_conv(trn_rd[63:32]);
                    cpl_addr_i[63:32] <= dw_endian_conv(trn_rd[31:0]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s9 : begin
                    aux_dw <= trn_rd[63:32];
                    if (!trn_rsrc_rdy_n) begin
                        lbuf1_en_i <= 1'b1;
                        tlp_rx_fsm <= s0;
                    end
                end

                s10 : begin
                    aux_dw <= trn_rd[63:32];
                    if (!trn_rsrc_rdy_n) begin
                        lbuf2_en_i <= 1'b1;
                        tlp_rx_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    tlp_rx_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // hst_ctrl

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////