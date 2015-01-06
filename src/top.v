/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        top.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Top module. Instantiates and interconnects blocks.
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
`include "includes.v"

module top ( 
    // PCIe
    input                    sys_clk_p,
    input                    sys_clk_n,
    //input                    sys_reset_n,    // MF: no reset available
    output       [7:0]       pci_exp_txp,
    output       [7:0]       pci_exp_txn,
    input        [7:0]       pci_exp_rxp,
    input        [7:0]       pci_exp_rxn,

    // XAUI D
    input                    refclk_D_p,
    input                    refclk_D_n,
    output       [3:0]       xaui_d_txp,
    output       [3:0]       xaui_d_txn,
    input        [3:0]       xaui_d_rxp,
    input        [3:0]       xaui_d_rxn,

    input                    usr_100MHz,

    output                   ael2005_mdc,
    inout                    ael2005_mdio
    );

    //-------------------------------------------------------
    // Local xge_intf D
    //-------------------------------------------------------
    wire                     mac_clk;
    wire                     mac_rst;
    // MAC tx
    wire                     mac_tx_underrun;
    wire         [63:0]      mac_tx_data;
    wire         [7:0]       mac_tx_data_valid;
    wire                     mac_tx_start;
    wire                     mac_tx_ack;
    // MAC rx
    wire         [63:0]      mac_rx_data;
    wire         [7:0]       mac_rx_data_valid;
    wire                     mac_rx_good_frame;
    wire                     mac_rx_bad_frame;
    // Host conf intf
    wire                     mac_host_clk;
    wire                     mac_host_reset;
    wire         [1:0]       mac_host_opcode;
    wire         [9:0]       mac_host_addr;
    wire         [31:0]      mac_host_wr_data;
    wire         [31:0]      mac_host_rd_data;
    wire                     mac_host_miim_sel;
    wire                     mac_host_req;
    wire                     mac_host_miim_rdy;

    //-------------------------------------------------------
    // Local DMA
    //-------------------------------------------------------
    wire                     pcie_rst;

    //-------------------------------------------------------
    // xge_intf D
    //-------------------------------------------------------
    xge_intf xge_intf_d (
        .refclk_p(refclk_D_p),                                 // I
        .refclk_n(refclk_D_n),                                 // I
        .xaui_txp(xaui_d_txp),                                 // O [3:0]
        .xaui_txn(xaui_d_txn),                                 // O [3:0]
        .xaui_rxp(xaui_d_rxp),                                 // I [3:0]
        .xaui_rxn(xaui_d_rxn),                                 // I [3:0]
        .clk100(usr_100MHz),                                   // I
        .dcm_rst_in(pcie_rst),                                 // I
        .clk156_25(mac_clk),                                   // O
        .reset156_25(mac_rst),                                 // O
        // MAC tx
        .mac_tx_underrun(mac_tx_underrun),                     // I
        .mac_tx_data(mac_tx_data),                             // I [63:0]
        .mac_tx_data_valid(mac_tx_data_valid),                 // I [7:0]
        .mac_tx_start(mac_tx_start),                           // I
        .mac_tx_ack(mac_tx_ack),                               // O
        // MAC rx
        .mac_rx_data(mac_rx_data),                             // O [63:0]
        .mac_rx_data_valid(mac_rx_data_valid),                 // O [7:0]
        .mac_rx_good_frame(mac_rx_good_frame),                 // O
        .mac_rx_bad_frame(mac_rx_bad_frame),                   // O
        // MDIO
        .phy_mdc(ael2005_mdc),                                 // O
        .phy_mdio(ael2005_mdio),                               // IO
        // MDIO conf intf
        .host_clk(mac_host_clk),                               // O
        .host_reset(mac_host_reset),                           // O
        .host_opcode(mac_host_opcode),                         // I [1:0]
        .host_addr(mac_host_addr),                             // I [9:0]
        .host_wr_data(mac_host_wr_data),                       // I [31:0]
        .host_rd_data(mac_host_rd_data),                       // O [31:0]
        .host_miim_sel(mac_host_miim_sel),                     // I
        .host_req(mac_host_req),                               // I
        .host_miim_rdy(mac_host_miim_rdy)                      // O
        );

    //-------------------------------------------------------
    // DMA
    //-------------------------------------------------------
    dma dma_mod (
        // PCIe
        .sys_clk_p(sys_clk_p),                                 // I
        .sys_clk_n(sys_clk_n),                                 // I
        .pci_exp_txp(pci_exp_txp),                             // O [7:0]
        .pci_exp_txn(pci_exp_txn),                             // O [7:0]
        .pci_exp_rxp(pci_exp_rxp),                             // I [7:0]
        .pci_exp_rxn(pci_exp_rxn),                             // I [7:0]
        .pcie_rst(pcie_rst),                                   // O
        // xge_intf
        .mac_clk(mac_clk),                                     // I
        .mac_rst(mac_rst),                                     // I
        // MAC tx
        .mac_tx_underrun(mac_tx_underrun),                     // O
        .mac_tx_data(mac_tx_data),                             // O [63:0]
        .mac_tx_data_valid(mac_tx_data_valid),                 // O [7:0]
        .mac_tx_start(mac_tx_start),                           // O
        .mac_tx_ack(mac_tx_ack),                               // I
        // MAC rx
        .mac_rx_data(mac_rx_data),                             // O [63:0]
        .mac_rx_data_valid(mac_rx_data_valid),                 // O [7:0]
        .mac_rx_good_frame(mac_rx_good_frame),                 // O
        .mac_rx_bad_frame(mac_rx_bad_frame),                   // O
        // MDIO conf intf
        .mac_host_clk(mac_host_clk),                           // I
        .mac_host_reset(mac_host_reset),                       // I
        .mac_host_opcode(mac_host_opcode),                     // O [1:0]
        .mac_host_addr(mac_host_addr),                         // O [9:0]
        .mac_host_wr_data(mac_host_wr_data),                   // O [31:0]
        .mac_host_rd_data(mac_host_rd_data),                   // I [31:0]
        .mac_host_miim_sel(mac_host_miim_sel),                 // O
        .mac_host_req(mac_host_req),                           // O
        .mac_host_miim_rdy(mac_host_miim_rdy)                  // I
        );

endmodule // top

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////