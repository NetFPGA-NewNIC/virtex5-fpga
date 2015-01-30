//---------------------------------------------------------------------------
// Title      : Verilog top level for XAUI
// Project    : 10 Gigabit Ethernet XAUI Core
// File       : xaui_example_design.v
// Author     : Xilinx Inc.
// Description: This module holds the top level design for the
//              10Gb/E XAUI core.
//---------------------------------------------------------------------------
// 
// (c) Copyright 2002 - 2010 Xilinx, Inc. All rights reserved. 
//
// This file contains confidential and proprietary information
// of Xilinx, Inc. and is protected under U.S. and
// international copyright and other intellectual property
// laws.
//
// DISCLAIMER
// This disclaimer is not a license and does not grant any
// rights to the materials distributed herewith. Except as
// otherwise provided in a valid license issued to you by
// Xilinx, and to the maximum extent permitted by applicable
// law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
// WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
// AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
// BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
// INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
// (2) Xilinx shall not be liable (whether in contract or tort,
// including negligence, or under any other theory of
// liability) for any loss or damage of any kind or nature
// related to, arising under or in connection with these
// materials, including for any direct, or any indirect,
// special, incidental, or consequential loss or damage
// (including loss of data, profits, goodwill, or any type of
// loss or damage suffered as a result of any action brought
// by a third party) even if such damage or loss was
// reasonably foreseeable or Xilinx had been advised of the
// possibility of the same.
//
// CRITICAL APPLICATIONS
// Xilinx products are not designed or intended to be fail-
// safe, or for use in any application requiring fail-safe
// performance, such as life-support or safety devices or
// systems, Class III medical devices, nuclear facilities,
// applications related to the deployment of airbags, or any
// other applications that could lead to death, personal
// injury, or severe property or environmental damage
// (individually and collectively, "Critical
// Applications"). Customer assumes the sole risk and
// liability of any use of Xilinx products in Critical
// Applications, subject only to applicable laws and
// regulations governing limitations on product liability.
//
// THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
// PART OF THIS FILE AT ALL TIMES.

module xaui_example_design # (
   parameter   REVERSE_LANES = 0
   )
  (
   dclk,
   reset,
   clk156_out,
   xgmii_txd,
   xgmii_txc,
   xgmii_rxd,
   xgmii_rxc,
   refclk_p,
   refclk_n,
   xaui_tx_l0_p,
   xaui_tx_l0_n,
   xaui_tx_l1_p,
   xaui_tx_l1_n,
   xaui_tx_l2_p,
   xaui_tx_l2_n,
   xaui_tx_l3_p,
   xaui_tx_l3_n,
   xaui_rx_l0_p,
   xaui_rx_l0_n,
   xaui_rx_l1_p,
   xaui_rx_l1_n,
   xaui_rx_l2_p,
   xaui_rx_l2_n,
   xaui_rx_l3_p,
   xaui_rx_l3_n,
   signal_detect,
   align_status,
   sync_status,
   mgt_tx_ready,
   configuration_vector,
   status_vector);

   // Port declarations
   input           dclk;
   input           reset;
   input  [63 : 0] xgmii_txd;
   input  [7 : 0]  xgmii_txc;
   output [63 : 0] xgmii_rxd;
   output [7 : 0]  xgmii_rxc;
   output          clk156_out;
   input           refclk_p;
   input           refclk_n;
   output          xaui_tx_l0_p;
   output          xaui_tx_l0_n;
   output          xaui_tx_l1_p;
   output          xaui_tx_l1_n;
   output          xaui_tx_l2_p;
   output          xaui_tx_l2_n;
   output          xaui_tx_l3_p;
   output          xaui_tx_l3_n;
   input           xaui_rx_l0_p;
   input           xaui_rx_l0_n;
   input           xaui_rx_l1_p;
   input           xaui_rx_l1_n;
   input           xaui_rx_l2_p;
   input           xaui_rx_l2_n;
   input           xaui_rx_l3_p;
   input           xaui_rx_l3_n;
   input [3 : 0]   signal_detect;
   output          align_status;
   output [3 : 0]  sync_status;
   output          mgt_tx_ready;
   input  [6 : 0]  configuration_vector;
   output [7 : 0]  status_vector;

   // Signal declarations
   wire          txoutclk;
   wire          clk156;
   wire          refclk;
   wire          mgt_tx_ready;
   wire[7:0]     xgmii_rxc_int;
   wire[63:0]    xgmii_rxd_int;

   // Register declarations
   reg           reset156;
   reg           reset156_r1;
   reg           reset156_r2;
   reg[7:0]      xgmii_txc_int = 'h0;
   reg[63:0]     xgmii_txd_int = 'h0;
   reg  [63 : 0] xgmii_rxd     = 'h0;
   reg  [7 : 0]  xgmii_rxc     = 'h0;
   // Start of logic

   // Instantiate the XAUI Block Level

   xaui_block # (
       .WRAPPER_SIM_GTXRESET_SPEEDUP(1),
       .REVERSE_LANES(REVERSE_LANES)
        ) //Does not affect hardware
   xaui_block
     (
       .reset(reset),
       .reset156(reset156),
       .clk156(clk156),
       .dclk(dclk),
       .refclk(refclk),
       .txoutclk(txoutclk),
       .xgmii_txd(xgmii_txd_int),
       .xgmii_txc(xgmii_txc_int),
       .xgmii_rxd(xgmii_rxd_int),
       .xgmii_rxc(xgmii_rxc_int),
       .xaui_tx_l0_p(xaui_tx_l0_p),
       .xaui_tx_l0_n(xaui_tx_l0_n),
       .xaui_tx_l1_p(xaui_tx_l1_p),
       .xaui_tx_l1_n(xaui_tx_l1_n),
       .xaui_tx_l2_p(xaui_tx_l2_p),
       .xaui_tx_l2_n(xaui_tx_l2_n),
       .xaui_tx_l3_p(xaui_tx_l3_p),
       .xaui_tx_l3_n(xaui_tx_l3_n),
       .xaui_rx_l0_p(xaui_rx_l0_p),
       .xaui_rx_l0_n(xaui_rx_l0_n),
       .xaui_rx_l1_p(xaui_rx_l1_p),
       .xaui_rx_l1_n(xaui_rx_l1_n),
       .xaui_rx_l2_p(xaui_rx_l2_p),
       .xaui_rx_l2_n(xaui_rx_l2_n),
       .xaui_rx_l3_p(xaui_rx_l3_p),
       .xaui_rx_l3_n(xaui_rx_l3_n),
       .txlock(txlock),
       .signal_detect(signal_detect),
       .align_status(align_status),
       .sync_status(sync_status),
       .mgt_tx_ready(mgt_tx_ready),
       .drp_i(16'h0000),
       .drp_addr(7'b000000),
       .drp_en(2'b00),
       .drp_we(2'b00),
       .drp_o(),
       .drp_rdy(),
       .configuration_vector(configuration_vector),
       .status_vector(status_vector));

   // Differential Clock Module
   IBUFDS refclk_ibufds(
      .I(refclk_p),
      .IB(refclk_n),
      .O(refclk));

//---------------------------------------------------------------------------------------------------------------------
// Clock management logic

   // Put system clocks on global routing
   BUFG txoutclk_bufg_i (
     .I(txoutclk),
     .O(clk156));


  // reset logic
  always @(posedge clk156 or posedge reset)
  begin
    if (reset)
      begin
        reset156_r1 <= 1'b1;
        reset156_r2 <= 1'b1;
        reset156    <= 1'b1;
      end
    else
      begin
        reset156_r1 <= 1'b0;
        reset156_r2 <= reset156_r1;
        reset156    <= reset156_r2;
      end
  end


   // Synthesise input and output registers
   always @(posedge clk156)
   begin
     xgmii_txd_int <= xgmii_txd;
     xgmii_txc_int <= xgmii_txc;
   end

   always @(posedge clk156)
   begin
     xgmii_rxd <= xgmii_rxd_int;
     xgmii_rxc <= xgmii_rxc_int;
   end

// MF: clk will be used internally
  assign clk156_out = clk156;

// MF: clk will be used internally
//      ODDR 
//    clk156out_ddr (
//      .Q(clk156_out),
//      .D1(1'b0),
//      .D2(1'b1),
//      .C(clk156),
//      .CE(1'b1),
//      .R(1'b0),
//      .S(1'b0));  
endmodule
