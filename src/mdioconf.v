/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mdioconf.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects mdioconf
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

module mdioconf # (
    parameter BARHIT = 0,
    // BAR MAPPING
    parameter BARMP_WRREG = 6'bxxxxxx
    ) (

    input                    bkd_rst,

    input                    pcie_clk,
    input                    pcie_rst,

    // TRN rx
    input        [63:0]      trn_rd,
    input        [7:0]       trn_rrem_n,
    input                    trn_rsof_n,
    input                    trn_reof_n,
    input                    trn_rsrc_rdy_n,
    input                    trn_rerrfwd_n,
    input        [6:0]       trn_rbar_hit_n,

    // CFG
    output                   cfg_interrupt_n,
    input                    cfg_interrupt_rdy_n,

    // MDIO conf
    input                    host_clk,
    input                    host_reset,
    output       [1:0]       host_opcode,
    output       [9:0]       host_addr,
    output       [31:0]      host_wr_data,
    input        [31:0]      host_rd_data,
    output                   host_miim_sel,
    output                   host_req,
    input                    host_miim_rdy
    );

    //-------------------------------------------------------
    // Local hst_if
    //-------------------------------------------------------
    wire                     send_irq;

    //-------------------------------------------------------
    // Local tlp2mdio
    //-------------------------------------------------------
    wire         [31:0]      acc_data;
    wire                     acc_en;
    wire                     acc_en_ack;

    //-------------------------------------------------------
    // MDIO conf
    //-------------------------------------------------------
    mdioconf_hst_if hst_if_mod (
        .bkd_rst(bkd_rst),                                     // I
        // Host Conf Intf
        .host_clk(host_clk),                                   // I
        .host_reset(host_reset),                               // I
        .host_opcode(host_opcode),                             // O [1:0]
        .host_addr(host_addr),                                 // O [9:0]
        .host_wr_data(host_wr_data),                           // O [31:0]
        .host_rd_data(host_rd_data),                           // I [31:0]
        .host_miim_sel(host_miim_sel),                         // O
        .host_req(host_req),                                   // O
        .host_miim_rdy(host_miim_rdy),                         // I
        // tlp2mdio
        .acc_data(acc_data),                                   // I [31:0]
        .acc_en(acc_en),                                       // I
        .acc_en_ack(acc_en_ack),                               // O
        // irq_gen
        .send_irq(send_irq)                                    // O
        );

    //-------------------------------------------------------
    // tlp2mdio
    //-------------------------------------------------------
    tlp2mdio # (
        .BARHIT(BARHIT),
        .BARMP_WRREG(BARMP_WRREG)
    ) tlp2mdio_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // tlp2mdio
        .acc_data(acc_data),                                   // O [31:0]
        .acc_en(acc_en),                                       // O
        .acc_en_ack(acc_en_ack)                                // I
        );

    //-------------------------------------------------------
    // irq_gen
    //-------------------------------------------------------
    mdioconf_irq_gen irq_gen_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        .send_irq(send_irq),                                   // I
        .cfg_interrupt_n(cfg_interrupt_n),                     // O
        .cfg_interrupt_rdy_n(cfg_interrupt_rdy_n)              // I
        );

endmodule // mdioconf

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////