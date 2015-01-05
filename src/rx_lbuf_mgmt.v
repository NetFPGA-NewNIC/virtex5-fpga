/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_lbuf_mgmt.v
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

module rx_lbuf_mgmt # (
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
    output       [63:0]      lbuf_addr,
    output                   lbuf_en,
    output                   lbuf64b,
    input                    lbuf_dn
    );

    //-------------------------------------------------------
    // Local hst_ctrl
    //-------------------------------------------------------
    wire         [63:0]      lbuf1_addr;
    wire                     lbuf1_en;
    wire                     lbuf1_dn;
    wire         [63:0]      lbuf2_addr;
    wire                     lbuf2_en;
    wire                     lbuf2_dn;

    //-------------------------------------------------------
    // gv_lbuf
    //-------------------------------------------------------
    rx_gv_lbuf gv_lbuf_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // hst_ctrl
        .lbuf1_addr(lbuf1_addr),                               // O [63:0]
        .lbuf1_en(lbuf1_en),                                   // O
        .lbuf1_dn(lbuf1_dn),                                   // I
        .lbuf2_addr(lbuf2_addr),                               // O [63:0]
        .lbuf2_en(lbuf2_en),                                   // O
        .lbuf2_dn(lbuf2_dn),                                   // I
        // gv_lbuf
        .lbuf_addr(lbuf2_addr),                                // O [63:0]
        .lbuf_en(lbuf2_en),                                    // O
        .lbuf64b(lbuf64b),                                     // O
        .lbuf_dn(lbuf2_dn)                                     // I
        );

    //-------------------------------------------------------
    // hst_ctrl
    //-------------------------------------------------------
    rx_hst_ctrl # (
        .BARHIT(BARHIT),
        .BARMP_LBUF1_ADDR(BARMP_LBUF1_ADDR),
        .BARMP_LBUF1_EN(BARMP_LBUF1_EN),
        .BARMP_LBUF2_ADDR(BARMP_LBUF2_ADDR),
        .BARMP_LBUF2_EN(BARMP_LBUF2_EN)
    ) hst_ctrl_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem),                                 // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // lbuf_mgmt
        .lbuf1_addr(lbuf1_addr),                               // O [63:0]
        .lbuf1_en(lbuf1_en),                                   // O
        .lbuf1_dn(lbuf1_dn),                                   // I
        .lbuf2_addr(lbuf2_addr),                               // O [63:0]
        .lbuf2_en(lbuf2_en),                                   // O
        .lbuf2_dn(lbuf2_dn)                                    // I
        );

endmodule // rx_lbuf_mgmt

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////