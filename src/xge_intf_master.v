/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        xge_intf_master.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects MAC and XAUI blocks. Configures MDIO.
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

module xge_intf_master # ( 
    parameter XAUI_REVERSE_LANES = 0,
    parameter DST_PORT = 8'h00
    ) (

    // XAUI
    input                    refclk_p,
    input                    refclk_n,
    output       [3:0]       xaui_txp,
    output       [3:0]       xaui_txn,
    input        [3:0]       xaui_rxp,
    input        [3:0]       xaui_rxn,

    input                    clk100,
    input                    dcm_rst_in,
    output                   dcm_for_xaui_locked,
    output                   clk50,
    input                    clk250,
    output                   reset156_25,

    // MAC tx
    input        [63:0]      s_axis_tdata,
    input        [7:0]       s_axis_tstrb,
    input        [127:0]     s_axis_tuser,
    input                    s_axis_tvalid,
    input                    s_axis_tlast,
    output                   s_axis_tready,

    // MAC rx
    output       [63:0]      m_axis_tdata,
    output       [7:0]       m_axis_tstrb,
    output       [127:0]     m_axis_tuser,
    output                   m_axis_tvalid,
    output                   m_axis_tlast,
    input                    m_axis_tready,

    // MDIO
    output                   phy_mdc,
    inout                    phy_mdio,

    // MDIO conf intf
    output                   host_clk,
    output                   host_reset,
    input        [1:0]       host_opcode,
    input        [9:0]       host_addr,
    input        [31:0]      host_wr_data,
    output       [31:0]      host_rd_data,
    input                    host_miim_sel,
    input                    host_req,
    output                   host_miim_rdy
    );

    //-------------------------------------------------------
    // Local DCM for XAUI
    //-------------------------------------------------------
    //wire                     clk50;
    //wire                     dcm_for_xaui_locked;
    //wire                     dcm_rst_in;
    wire                     clk156_25;
    //wire                     reset156_25;

    //-------------------------------------------------------
    // Local XAUI
    //-------------------------------------------------------
    wire                     xaui_reset;
    wire         [63:0]      xgmii_txd;
    wire         [7:0]       xgmii_txc;
    wire         [63:0]      xgmii_rxd;
    wire         [7:0]       xgmii_rxc;
    wire         [3:0]       xaui_signal_detect;
    wire                     xaui_align_status;
    wire         [3:0]       xaui_sync_status;
    wire                     xaui_mgt_tx_ready;
    wire         [6:0]       xaui_configuration_vector;
    wire         [7:0]       xaui_status_vector;
    wire                     xaui_tx_l0_p;
    wire                     xaui_tx_l0_n;
    wire                     xaui_tx_l1_p;
    wire                     xaui_tx_l1_n;
    wire                     xaui_tx_l2_p;
    wire                     xaui_tx_l2_n;
    wire                     xaui_tx_l3_p;
    wire                     xaui_tx_l3_n;
    wire                     xaui_rx_l0_p;
    wire                     xaui_rx_l0_n;
    wire                     xaui_rx_l1_p;
    wire                     xaui_rx_l1_n;
    wire                     xaui_rx_l2_p;
    wire                     xaui_rx_l2_n;
    wire                     xaui_rx_l3_p;
    wire                     xaui_rx_l3_n;
    
    //-------------------------------------------------------
    // Local MAC
    //-------------------------------------------------------
    wire         [7:0]       mac_tx_ifg_delay;
    wire         [24:0]      mac_tx_statistics_vector;
    wire                     mac_tx_statistics_valid;
    wire         [15:0]      mac_pause_val;
    wire                     mac_pause_req;
    wire         [28:0]      mac_rx_statistics_vector;
    wire                     mac_rx_statistics_valid;
    // When using The Management Interface the configuration vector interface doesn't exists
    //wire         [68:0]      mac_configuration_vector;
    //wire         [1:0]       mac_status_vector;
    // When using The Management Interface the configuration vector interface doesn't exists
    wire                     mac_mdio_in;
    wire                     mac_mdio_out;
    wire                     mac_mdio_tri;
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

    //-------------------------------------------------------
    // assigns - for testing only
    //-------------------------------------------------------
    // Clocking
    //assign dcm_rst_in = 1'b0;
    assign xaui_reset = ~dcm_for_xaui_locked;

    // XAUI
    assign xaui_txp = {xaui_tx_l3_p, xaui_tx_l2_p, xaui_tx_l1_p, xaui_tx_l0_p};
    assign xaui_txn = {xaui_tx_l3_n, xaui_tx_l2_n, xaui_tx_l1_n, xaui_tx_l0_n};

    assign {xaui_rx_l3_p, xaui_rx_l2_p, xaui_rx_l1_p, xaui_rx_l0_p} = xaui_rxp;
    assign {xaui_rx_l3_n, xaui_rx_l2_n, xaui_rx_l1_n, xaui_rx_l0_n} = xaui_rxn;

    // XAUI Loopback
    //always @(posedge clk156_25) begin
        //xgmii_txd <= xgmii_rxd;
        //xgmii_txc <= xgmii_rxc;
    //end

    // XAUI Configuration
    assign  xaui_signal_detect = 4'b1111;      //according to pg053
    assign  xaui_configuration_vector = 7'b0;  //see pg053

    // MDIO conf
    assign host_clk = clk50;
    assign host_reset = xaui_reset;
    // MDIO interface
    assign phy_mdio = mac_mdio_tri ? 1'bZ : mac_mdio_out;
    assign mac_mdio_in = mac_mdio_out;

    // MAC Configuration
    assign mac_tx_ifg_delay = 8'b0;
    assign mac_pause_val = 16'b0;
    assign mac_pause_req = 1'b0;
    
    // When using The Management Interface the configuration vector interface doesn't exists
    // -------------------------------------------------------------------------------------
    // // Configuration vector ug148
    // // -------------------------------------------------------------------------------------
    // // Rx
    // assign mac_configuration_vector[47:0] = 48'b0;  //Pause frame MAC Source Address
    // assign mac_configuration_vector[48] = 1'b1;     //Receive VLAN Enable
    // assign mac_configuration_vector[49] = 1'b1;     //Receive Enable
    // assign mac_configuration_vector[50] = 1'b0;     //Receive In-Band FCS
    // assign mac_configuration_vector[51] = 1'b0;     //Receive Jumbo Frame Enable
    // assign mac_configuration_vector[52] = 1'b0;     //Receiver Reset
    // assign mac_configuration_vector[60] = 1'b0;     //Receive Flow Control Enable
    // assign mac_configuration_vector[66] = 1'b1;     //Receiver Preserve Preamble Enable
    // assign mac_configuration_vector[67] = 1'b1;     //Receiver Length/Type Error Disable
    // assign mac_configuration_vector[68] = 1'b0;     //Control Frame Length Check Disable
    // // Tx
    // assign mac_configuration_vector[53] = 1'b0;     //Transmitter LAN/WAN Mode
    // assign mac_configuration_vector[54] = 1'b0;     //Transmitter Interframe Gap Adjust Enable
    // assign mac_configuration_vector[55] = 1'b0;     //Transmitter VLAN Enable
    // assign mac_configuration_vector[56] = 1'b1;     //Transmitter Enable
    // assign mac_configuration_vector[57] = 1'b0;     //Transmitter In-Band FCS Enable
    // assign mac_configuration_vector[58] = 1'b0;     //Transmitter Jumbo Frame Enable
    // assign mac_configuration_vector[59] = 1'b0;     //Transmitter Reset
    // assign mac_configuration_vector[61] = 1'b0;     //Transmit Flow Control Enable
    // assign mac_configuration_vector[62] = 1'b1;     //Deficit Idle Count Enable
    // assign mac_configuration_vector[63] = 1'b0;     //Reserved. Tie to ‘0.’
    // assign mac_configuration_vector[64] = 1'b0;     //Reconciliation Sublayer Fault Inhibit
    // assign mac_configuration_vector[65] = 1'b0;     //Transmitter Preserve Preamble Enable
    // // -------------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------
    // When using The Management Interface the configuration vector interface doesn't exists

    //-------------------------------------------------------
    // Virtex5-FX DCM for XAUI
    //-------------------------------------------------------
    xaui_dcm dcm_for_xaui (
        .CLKIN_IN(clk100),                                     // I
        .RST_IN(dcm_rst_in),                                   // I
        .CLKIN_IBUFG_OUT(),                                    // O
        .CLK0_OUT(clk50),                                      // O
        .LOCKED_OUT(dcm_for_xaui_locked)                       // O
        );

    //-------------------------------------------------------
    // XAUI D
    //-------------------------------------------------------
    xaui_example_design # (
        .REVERSE_LANES(XAUI_REVERSE_LANES)
    ) xaui_mod (
        .dclk(clk50),                                          // I
        .reset(xaui_reset),                                    // I
        .clk156_out(clk156_25),                                // O
        .xgmii_txd(xgmii_txd),                                 // I [63:0]
        .xgmii_txc(xgmii_txc),                                 // I [7:0]
        .xgmii_rxd(xgmii_rxd),                                 // O [63:0]
        .xgmii_rxc(xgmii_rxc),                                 // O [7:0]
        .refclk_p(refclk_p),                                   // I
        .refclk_n(refclk_n),                                   // I
        .xaui_tx_l0_p(xaui_tx_l0_p),                           // O
        .xaui_tx_l0_n(xaui_tx_l0_n),                           // O
        .xaui_tx_l1_p(xaui_tx_l1_p),                           // O
        .xaui_tx_l1_n(xaui_tx_l1_n),                           // O
        .xaui_tx_l2_p(xaui_tx_l2_p),                           // O
        .xaui_tx_l2_n(xaui_tx_l2_n),                           // O
        .xaui_tx_l3_p(xaui_tx_l3_p),                           // O
        .xaui_tx_l3_n(xaui_tx_l3_n),                           // O
        .xaui_rx_l0_p(xaui_rx_l0_p),                           // I
        .xaui_rx_l0_n(xaui_rx_l0_n),                           // I
        .xaui_rx_l1_p(xaui_rx_l1_p),                           // I
        .xaui_rx_l1_n(xaui_rx_l1_n),                           // I
        .xaui_rx_l2_p(xaui_rx_l2_p),                           // I
        .xaui_rx_l2_n(xaui_rx_l2_n),                           // I
        .xaui_rx_l3_p(xaui_rx_l3_p),                           // I
        .xaui_rx_l3_n(xaui_rx_l3_n),                           // I
        .signal_detect(xaui_signal_detect),                    // I [3:0]
        .align_status(xaui_align_status),                      // O
        .sync_status(xaui_sync_status),                        // O [3:0]
        .mgt_tx_ready(xaui_mgt_tx_ready),                      // O
        .configuration_vector(xaui_configuration_vector),      // I [6:0]
        .status_vector(xaui_status_vector)                     // O [7:0]
        );

    //-------------------------------------------------------
    // MAC
    //-------------------------------------------------------
    xgmac_mdio mac_mod (
        .reset(reset156_25),                                   // I
        
        .tx_underrun(mac_tx_underrun),                         // I 
        .tx_data(mac_tx_data),                                 // I [63:0] 
        .tx_data_valid(mac_tx_data_valid),                     // I [7:0] 
        .tx_start(mac_tx_start),                               // I 
        .tx_ack(mac_tx_ack),                                   // O 
        .tx_ifg_delay(mac_tx_ifg_delay),                       // I [7:0] 
        .tx_statistics_vector(mac_tx_statistics_vector),       // O [24:0] 
        .tx_statistics_valid(mac_tx_statistics_valid),         // O 
        .pause_val(mac_pause_val),                             // I [15:0] 
        .pause_req(mac_pause_req),                             // I

        .rx_data(mac_rx_data),                                 // O [63:0]
        .rx_data_valid(mac_rx_data_valid),                     // O [7:0]
        .rx_good_frame(mac_rx_good_frame),                     // O
        .rx_bad_frame(mac_rx_bad_frame),                       // O
        .rx_statistics_vector(mac_rx_statistics_vector),       // O [28:0]
        .rx_statistics_valid(mac_rx_statistics_valid),         // O 

        //.configuration_vector(mac_configuration_vector),       // I [68:0]
        //.status_vector(mac_status_vector),                     // O [1:0]

        .host_clk(host_clk),                                   // I 
        .host_opcode(host_opcode),                             // I [1:0] 
        .host_addr(host_addr),                                 // I [9:0] 
        .host_wr_data(host_wr_data),                           // I [31:0] 
        .host_rd_data(host_rd_data),                           // O [31:0] 
        .host_miim_sel(host_miim_sel),                         // I 
        .host_req(host_req),                                   // I 
        .host_miim_rdy(host_miim_rdy),                         // O 

        .tx_clk0(clk156_25),                                   // I 
        .tx_dcm_lock(xaui_mgt_tx_ready),                       // I 
        .xgmii_txd(xgmii_txd),                                 // O [63:0]
        .xgmii_txc(xgmii_txc),                                 // O [7:0]

        .rx_clk0(clk156_25),                                   // I 
        .rx_dcm_lock(xaui_align_status),                       // I pg053: '1' when the XAUI receiver is aligned across all four lanes, '0' otherwise.
        .xgmii_rxd(xgmii_rxd),                                 // I [63:0]
        .xgmii_rxc(xgmii_rxc),                                 // I [7:0]
        
        .mdc(phy_mdc),                                         // O 
        .mdio_in(mac_mdio_in),                                 // I
        .mdio_out(mac_mdio_out),                               // O 
        .mdio_tri(mac_mdio_tri)                                // O
        );

    //-------------------------------------------------------
    // mac_reset
    //-------------------------------------------------------
    mac_reset mac_reset_mod (
        .clk156_25(clk156_25),                                 // I
        .xaui_reset(xaui_reset),                               // I
        .reset156_25(reset156_25)                              // O
        );

    //-------------------------------------------------------
    // mac2axis
    //-------------------------------------------------------
    mac2axis #(
        .BW(9),
        .DST_PORT(DST_PORT)
    ) mac2axis_mod (
        // MAC rx
        .mac_clk(clk156_25),                                   // I
        .mac_rst(reset156_25),                                 // I
        .mac_rx_data(mac_rx_data),                             // I [63:0]
        .mac_rx_data_valid(mac_rx_data_valid),                 // I [7:0]
        .mac_rx_good_frame(mac_rx_good_frame),                 // I
        .mac_rx_bad_frame(mac_rx_bad_frame),                   // I
        // AXIS
        .m_axis_aclk(clk250),                                  // I
        .m_axis_aresetp(reset156_25),                          // I
        .m_axis_tdata(m_axis_tdata),                           // O [63:0]
        .m_axis_tstrb(m_axis_tstrb),                           // O [7:0]
        .m_axis_tuser(m_axis_tuser),                           // O [127:0]
        .m_axis_tvalid(m_axis_tvalid),                         // O
        .m_axis_tlast(m_axis_tlast),                           // O
        .m_axis_tready(m_axis_tready)                          // I
        );

    //-------------------------------------------------------
    // axis2mac
    //-------------------------------------------------------
    axis2mac #(
        .BW(9),
        .DST_PORT(DST_PORT)
    ) axis2mac_mod (
        // MAC tx
        .mac_clk(clk156_25),                                   // I
        .mac_rst(reset156_25),                                 // I
        .mac_tx_underrun(mac_tx_underrun),                     // O
        .mac_tx_data(mac_tx_data),                             // O [63:0]
        .mac_tx_data_valid(mac_tx_data_valid),                 // O [7:0]
        .mac_tx_start(mac_tx_start),                           // O
        .mac_tx_ack(mac_tx_ack),                               // I
        // AXIS
        .s_axis_aclk(clk250),                                  // I
        .s_axis_aresetp(reset156_25),                          // I
        .s_axis_tdata(s_axis_tdata),                           // I [63:0]
        .s_axis_tstrb(s_axis_tstrb),                           // I [7:0]
        .s_axis_tuser(s_axis_tuser),                           // I [127:0]
        .s_axis_tvalid(s_axis_tvalid),                         // I
        .s_axis_tlast(s_axis_tlast),                           // I
        .s_axis_tready(s_axis_tready)                          // O
        );

endmodule // xge_intf_master

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////