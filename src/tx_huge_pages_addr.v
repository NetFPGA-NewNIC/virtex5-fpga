/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_huge_pages_addr.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives huge page addresses, huge page size and huge page ready.
*
*        TODO: 
*        The module will inform the advetised the size of the huge page given by
*        the driver.
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

module tx_huge_pages_addr (

    input                   trn_clk,
    input                   reset,

    input       [63:0]      trn_rd,
    input       [7:0]       trn_rrem_n,
    input                   trn_rsof_n,
    input                   trn_reof_n,
    input                   trn_rsrc_rdy_n,
    input                   trn_rsrc_dsc_n,
    input       [6:0]       trn_rbar_hit_n,
    input                   trn_rdst_rdy_n,
    output reg  [63:0]      huge_page_addr_1,
    output reg  [63:0]      huge_page_addr_2,
    output reg  [31:0]      huge_page_qwords_1,
    output reg  [31:0]      huge_page_qwords_2,
    output reg              huge_page_status_1,
    output reg              huge_page_status_2,
    input                   huge_page_free_1,
    input                   huge_page_free_2,
    output reg  [63:0]      completed_buffer_address
    );

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
    // Local TLP reception
    //-------------------------------------------------------
    reg     [9:0]   tlp_rx_fsm;
    reg             huge_page_unlock_1;
    reg             huge_page_unlock_2;
    reg     [31:0]  aux_dw;
    reg     [63:0]  huge_page_addr_1_i;
    reg     [63:0]  huge_page_addr_2_i;
    reg     [63:0]  completed_buffer_address_i;

    ////////////////////////////////////////////////
    // huge_page_status
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            huge_page_status_1 <= 1'b0;
            huge_page_status_2 <= 1'b0;
        end
        
        else begin  // not reset
            if (huge_page_unlock_1) begin
                huge_page_status_1 <= 1'b1;
                huge_page_qwords_1[7:0] <= aux_dw[31:24];
                huge_page_qwords_1[15:8] <= aux_dw[23:16];
                huge_page_qwords_1[23:16] <= aux_dw[15:8];
                huge_page_qwords_1[31:24] <= aux_dw[7:0];
            end
            else if (huge_page_free_1) begin
                huge_page_status_1 <= 1'b0;
            end

            if (huge_page_unlock_2) begin
                huge_page_status_2 <= 1'b1;
                huge_page_qwords_2[7:0] <= aux_dw[31:24];
                huge_page_qwords_2[15:8] <= aux_dw[23:16];
                huge_page_qwords_2[23:16] <= aux_dw[15:8];
                huge_page_qwords_2[31:24] <= aux_dw[7:0];
            end
            else if (huge_page_free_2) begin
                huge_page_status_2 <= 1'b0;
            end

        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // huge_page_address and unlock TLP reception
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            huge_page_unlock_1 <= 1'b0;
            huge_page_unlock_2 <= 1'b0;
            tlp_rx_fsm <= s0;
        end
        
        else begin  // not reset

            huge_page_unlock_1 <= 1'b0;
            huge_page_unlock_2 <= 1'b0;

            huge_page_addr_1 <= huge_page_addr_1_i;
            huge_page_addr_2 <= huge_page_addr_2_i;
            completed_buffer_address <= completed_buffer_address_i;

            case (tlp_rx_fsm)

                s0 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n) && (!trn_rbar_hit_n[2])) begin
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
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[39:34])

                            6'b100000 : begin     // huge page address
                                tlp_rx_fsm <= s2;
                            end

                            6'b100010 : begin     // huge page address
                                tlp_rx_fsm <= s3;
                            end

                            6'b101000 : begin     // huge page un-lock
                                huge_page_unlock_1 <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            6'b101001 : begin     // huge page un-lock
                                huge_page_unlock_2 <= 1'b1;
                                tlp_rx_fsm <= s0;
                            end

                            6'b101100 : begin     // completion buffer address
                                tlp_rx_fsm <= s4;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end

                        endcase
                    end
                end

                s2 : begin
                    huge_page_addr_1_i[7:0] <= aux_dw[31:24];
                    huge_page_addr_1_i[15:8] <= aux_dw[23:16];
                    huge_page_addr_1_i[23:16] <= aux_dw[15:8];
                    huge_page_addr_1_i[31:24] <= aux_dw[7:0];

                    huge_page_addr_1_i[39:32] <= trn_rd[63:56];
                    huge_page_addr_1_i[47:40] <= trn_rd[55:48];
                    huge_page_addr_1_i[55:48] <= trn_rd[47:40];
                    huge_page_addr_1_i[63:56] <= trn_rd[39:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s3 : begin
                    huge_page_addr_2_i[7:0] <= aux_dw[31:24];
                    huge_page_addr_2_i[15:8] <= aux_dw[23:16];
                    huge_page_addr_2_i[23:16] <= aux_dw[15:8];
                    huge_page_addr_2_i[31:24] <= aux_dw[7:0];

                    huge_page_addr_2_i[39:32] <= trn_rd[63:56];
                    huge_page_addr_2_i[47:40] <= trn_rd[55:48];
                    huge_page_addr_2_i[55:48] <= trn_rd[47:40];
                    huge_page_addr_2_i[63:56] <= trn_rd[39:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s4 : begin
                    completed_buffer_address_i[7:0] <= aux_dw[31:24];
                    completed_buffer_address_i[15:8] <= aux_dw[23:16];
                    completed_buffer_address_i[23:16] <= aux_dw[15:8];
                    completed_buffer_address_i[31:24] <= aux_dw[7:0];
                    
                    completed_buffer_address_i[39:32] <= trn_rd[63:56];
                    completed_buffer_address_i[47:40] <= trn_rd[55:48];
                    completed_buffer_address_i[55:48] <= trn_rd[47:40];
                    completed_buffer_address_i[63:56] <= trn_rd[39:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s5 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[7:2])

                            6'b100000 : begin     // huge page address
                                tlp_rx_fsm <= s6;
                            end

                            6'b100010 : begin     // huge page address
                                tlp_rx_fsm <= s7;
                            end

                            6'b101000 : begin     // huge page un-lock
                                tlp_rx_fsm <= s8;
                            end

                            6'b101001 : begin     // huge page un-lock
                                tlp_rx_fsm <= s9;
                            end

                            6'b101100 : begin     // completion buffer address
                                tlp_rx_fsm <= s10;
                            end

                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end

                        endcase
                    end
                end

                s6 : begin
                    huge_page_addr_1_i[7:0]   <= trn_rd[63:56];
                    huge_page_addr_1_i[15:8]  <= trn_rd[55:48];
                    huge_page_addr_1_i[23:16] <= trn_rd[47:40];
                    huge_page_addr_1_i[31:24] <= trn_rd[39:32];

                    huge_page_addr_1_i[39:32] <= trn_rd[31:24];
                    huge_page_addr_1_i[47:40] <= trn_rd[23:16];
                    huge_page_addr_1_i[55:48] <= trn_rd[15:8];
                    huge_page_addr_1_i[63:56] <= trn_rd[7:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s7 : begin
                    huge_page_addr_2_i[7:0]   <= trn_rd[63:56];
                    huge_page_addr_2_i[15:8]  <= trn_rd[55:48];
                    huge_page_addr_2_i[23:16] <= trn_rd[47:40];
                    huge_page_addr_2_i[31:24] <= trn_rd[39:32];

                    huge_page_addr_2_i[39:32] <= trn_rd[31:24];
                    huge_page_addr_2_i[47:40] <= trn_rd[23:16];
                    huge_page_addr_2_i[55:48] <= trn_rd[15:8];
                    huge_page_addr_2_i[63:56] <= trn_rd[7:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                s8 : begin
                    aux_dw <= trn_rd[63:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        huge_page_unlock_1 <= 1'b1;
                        tlp_rx_fsm <= s0;
                    end
                end

                s9 : begin
                    aux_dw <= trn_rd[63:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        huge_page_unlock_2 <= 1'b1;
                        tlp_rx_fsm <= s0;
                    end
                end

                s10 : begin
                    completed_buffer_address_i[7:0]   <= trn_rd[63:56];
                    completed_buffer_address_i[15:8]  <= trn_rd[55:48];
                    completed_buffer_address_i[23:16] <= trn_rd[47:40];
                    completed_buffer_address_i[31:24] <= trn_rd[39:32];

                    completed_buffer_address_i[39:32] <= trn_rd[31:24];
                    completed_buffer_address_i[47:40] <= trn_rd[23:16];
                    completed_buffer_address_i[55:48] <= trn_rd[15:8];
                    completed_buffer_address_i[63:56] <= trn_rd[7:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    tlp_rx_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // tx_huge_pages_addr

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////