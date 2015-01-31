/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tlp2regif.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives access to register interface.
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

module tlp2regif # (
    // BAR MAPPING
    parameter BARHIT = 2,
    parameter BARMP_CPL_ADDR = 6'b111111,
    parameter BARMP_OP = 6'b111111,
    parameter WRIF = 0
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

    // tlp2regif
    output reg   [63:0]      cpl_addr,
    output reg   [31:0]      acc_addr,
    output reg   [31:0]      acc_data,
    output reg               acc_en,
    input                    acc_en_ack
    );

    `include "includes.v"
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
    reg          [31:0]      aux_dw;
    reg          [63:0]      cpl_addr_i;
    reg          [31:0]      acc_addr_i;
    reg          [31:0]      acc_data_i;
    reg                      rdy;
    reg                      acc_en_ack_reg0;
    reg                      acc_en_ack_reg1;

    //-------------------------------------------------------
    // Local Output driver
    //-------------------------------------------------------
    reg          [7:0]       odr_fsm;

    ////////////////////////////////////////////////
    // Output driver
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            acc_en <= 1'b0;
            odr_fsm <= s0;
        end
        
        else begin  // not rst

            acc_en_ack_reg0 <= acc_en_ack;
            acc_en_ack_reg1 <= acc_en_ack_reg0;

            case (odr_fsm)

                s0 : begin
                    acc_en_ack_reg0 <= 1'b0;
                    acc_en_ack_reg1 <= 1'b0;
                    acc_addr <= acc_addr_i;
                    acc_data <= acc_data_i;
                    if (rdy) begin
                        odr_fsm <= s1;
                    end
                end

                s1 : begin
                    acc_en <= 1'b1;
                    odr_fsm <= s2;
                end

                s2 : begin
                    if (acc_en_ack_reg1) begin
                        acc_en <= 1'b0;
                        odr_fsm <= s0;
                    end
                end

                default : begin
                    odr_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

    ////////////////////////////////////////////////
    // Rx TLP
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            rdy <= 1'b0;
            tlp_rx_fsm <= s0;
        end
        
        else begin  // not rst

            rdy <= 1'b0;

            cpl_addr <= cpl_addr_i;

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

                            BARMP_OP : begin
                                tlp_rx_fsm <= s2;
                            end

                            BARMP_CPL_ADDR : begin
                                tlp_rx_fsm <= s3;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s2 : begin
                    if (WRIF == 1) begin
                        acc_data_i <= dw_endian_conv(aux_dw);
                        acc_addr_i <= dw_endian_conv(trn_rd[63:32]);
                    end
                    else begin
                        acc_addr_i <= dw_endian_conv(aux_dw);
                        acc_data_i <= dw_endian_conv(trn_rd[63:32]);
                    end
                    if (!trn_rsrc_rdy_n) begin
                        rdy <= 1'b1;
                        tlp_rx_fsm <= s0;
                    end
                end

                s3 : begin
                    cpl_addr_i[31:0] <= dw_endian_conv(aux_dw);
                    cpl_addr_i[63:32] <= dw_endian_conv(trn_rd[63:32]);
                    if (!trn_rsrc_rdy_n) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s4 : begin
                    if (!trn_rsrc_rdy_n) begin
                        case (trn_rd[7:2])

                            BARMP_OP : begin
                                tlp_rx_fsm <= s5;
                            end

                            BARMP_CPL_ADDR : begin
                                tlp_rx_fsm <= s6;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s5 : begin
                    if (WRIF == 1) begin
                        acc_data_i <= dw_endian_conv(trn_rd[63:32]);
                        acc_addr_i <= dw_endian_conv(trn_rd[31:0]);
                    end
                    else begin
                        acc_addr_i <= dw_endian_conv(trn_rd[63:32]);
                        acc_data_i <= dw_endian_conv(trn_rd[31:0]);
                    end
                    if (!trn_rsrc_rdy_n) begin
                        rdy <= 1'b1;
                        tlp_rx_fsm <= s0;
                    end
                end

                s6 : begin
                    cpl_addr_i[31:0] <= dw_endian_conv(trn_rd[63:32]);
                    cpl_addr_i[63:32] <= dw_endian_conv(trn_rd[31:0]);
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

endmodule // tlp2regif

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////