/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        chn.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects rx and tx logic
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

module chn # ( 
    parameter BARHIT = 2,
    // Tx
    parameter TX_BARMP_LBUF1_ADDR = 6'bxxxxxx,
    parameter TX_BARMP_LBUF1_EN = 6'bxxxxxx,
    parameter TX_BARMP_LBUF2_ADDR = 6'bxxxxxx,
    parameter TX_BARMP_LBUF2_EN = 6'bxxxxxx,
    parameter TX_BARMP_CPL_BUFF = 6'bxxxxxx,
    parameter TX_BARMP_WRBCK = 6'bxxxxxx,
    // Rx
    parameter RX_BARMP_LBUF1_ADDR = 6'bxxxxxx,
    parameter RX_BARMP_LBUF1_EN = 6'bxxxxxx,
    parameter RX_BARMP_LBUF2_ADDR = 6'bxxxxxx,
    parameter RX_BARMP_LBUF2_EN = 6'bxxxxxx,
    parameter RX_BARMP_WRBCK = 6'bxxxxxx,
    // IRQ
    parameter IRQ_BARMP_EN = 6'bxxxxxx,
    parameter IRQ_BARMP_DIS = 6'bxxxxxx,
    parameter IRQ_BARMP_THR = 6'bxxxxxx
    ) (

    input                    mac_clk,
    input                    mac_rst,

    input                    pcie_clk,
    input                    pcie_rst,

    // MAC tx
    output                   mac_tx_underrun,
    output       [63:0]      mac_tx_data,
    output       [7:0]       mac_tx_data_valid,
    output                   mac_tx_start,
    input                    mac_tx_ack,

    // MAC rx
    input        [63:0]      mac_rx_data,
    input        [7:0]       mac_rx_data_valid,
    input                    mac_rx_good_frame,
    input                    mac_rx_bad_frame,

    // TRN tx
    output       [63:0]      trn_td,
    output       [7:0]       trn_trem_n,
    output                   trn_tsof_n,
    output                   trn_teof_n,
    output                   trn_tsrc_rdy_n,
    input                    trn_tdst_rdy_n,
    input        [3:0]       trn_tbuf_av,

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
    input        [7:0]       cfg_bus_number,
    input        [4:0]       cfg_device_number,
    input        [2:0]       cfg_function_number,
    input        [15:0]      cfg_dcommand,

    // EP arb
    input        [4:0]       tag_trn,
    output                   tag_inc,
    input                    chn_trn,
    output                   chn_drvn,
    output                   chn_reqep
    );

    //-------------------------------------------------------
    // Local PCIe trn protocol
    //-------------------------------------------------------
    wire         [15:0]      cfg_completer_id;
    wire         [2:0]       cfg_max_rd_req_size;
    wire         [2:0]       cfg_max_payload_size;

    //-------------------------------------------------------
    // Tx
    //-------------------------------------------------------
    wire         [63:0]      tx_trn_td;
    wire         [7:0]       tx_trn_trem_n;
    wire                     tx_trn_tsof_n;
    wire                     tx_trn_teof_n;
    wire                     tx_trn_tsrc_rdy_n;
    wire                     tx_send_irq;

    //-------------------------------------------------------
    // Rx
    //-------------------------------------------------------
    wire         [63:0]      rx_trn_td;
    wire         [7:0]       rx_trn_trem_n;
    wire                     rx_trn_tsof_n;
    wire                     rx_trn_teof_n;
    wire                     rx_trn_tsrc_rdy_n;
    wire                     rx_send_irq;

    //-------------------------------------------------------
    // IRQ
    //-------------------------------------------------------
    wire                     send_irq;

    //-------------------------------------------------------
    // EP arb
    //-------------------------------------------------------
    wire                     tx_trn;
    wire                     tx_drvn;
    wire                     tx_reqep;
    wire                     rx_trn;
    wire                     rx_drvn;
    wire                     irq_trn;
    wire                     irq_drvn;
    wire                     irq_reqep;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign cfg_completer_id = {cfg_bus_number, cfg_device_number, cfg_function_number};
    assign cfg_max_rd_req_size = cfg_dcommand[14:12];
    assign cfg_max_payload_size = cfg_dcommand[7:5];

    assign trn_td = tx_trn_td | rx_trn_td;
    assign trn_trem_n = tx_trn_trem_n & rx_trn_trem_n;
    assign trn_tsof_n = tx_trn_tsof_n & rx_trn_tsof_n;
    assign trn_teof_n = tx_trn_teof_n & rx_trn_teof_n;
    assign trn_tsrc_rdy_n = tx_trn_tsrc_rdy_n & rx_trn_tsrc_rdy_n;

    assign send_irq = tx_send_irq | rx_send_irq;

    //-------------------------------------------------------
    // Tx
    //-------------------------------------------------------
    tx #(
        // BAR MAPPING
        .BARHIT(BARHIT),
        .BARMP_LBUF1_ADDR(TX_BARMP_LBUF1_ADDR),
        .BARMP_LBUF1_EN(TX_BARMP_LBUF1_EN),
        .BARMP_LBUF2_ADDR(TX_BARMP_LBUF2_ADDR),
        .BARMP_LBUF2_EN(TX_BARMP_LBUF2_EN),
        .BARMP_CPL_BUFF(TX_BARMP_CPL_BUFF),
        .BARMP_WRBCK(TX_BARMP_WRBCK),
        // MISC
        .BW(9)
    ) tx_mod (
        .mac_clk(mac_clk),                                     // I
        .mac_rst(mac_rst),                                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // MAC tx
        .mac_tx_underrun(mac_tx_underrun),                     // I
        .mac_tx_data(mac_tx_data),                             // I [63:0]
        .mac_tx_data_valid(mac_tx_data_valid),                 // I [7:0]
        .mac_tx_start(mac_tx_start),                           // I
        .mac_tx_ack(mac_tx_ack),                               // O
        // TRN tx
        .trn_td(tx_trn_td),                                    // O [63:0]
        .trn_trem_n(tx_trn_trem_n),                            // O [7:0]
        .trn_tsof_n(tx_trn_tsof_n),                            // O
        .trn_teof_n(tx_trn_teof_n),                            // O
        .trn_tsrc_rdy_n(tx_trn_tsrc_rdy_n),                    // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n),                       // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rerrfwd_n(trn_rerrfwd_n),                         // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // CFG
        .cfg_completer_id(cfg_completer_id),                   // I [15:0]
        .cfg_max_rd_req_size(cfg_max_rd_req_size),             // I [2:0]
        .send_irq(tx_send_irq),                                // O
        // EP arb
        .tag_trn(tag_trn),                                     // I [4:0]
        .tag_inc(tag_inc),                                     // O
        .my_trn(tx_trn),                                       // I
        .drv_ep(tx_drvn),                                      // O
        .req_ep(tx_reqep)                                      // O
        );

    //-------------------------------------------------------
    // Rx
    //-------------------------------------------------------
    rx #(
        // BAR MAPPING
        .BARHIT(BARHIT),
        .BARMP_LBUF1_ADDR(RX_BARMP_LBUF1_ADDR),
        .BARMP_LBUF1_EN(RX_BARMP_LBUF1_EN),
        .BARMP_LBUF2_ADDR(RX_BARMP_LBUF2_ADDR),
        .BARMP_LBUF2_EN(RX_BARMP_LBUF2_EN),
        .BARMP_WRBCK(RX_BARMP_WRBCK),
        // MISC
        .BW(10)
    ) rx_mod (
        .mac_clk(mac_clk),                                     // I
        .mac_rst(mac_rst),                                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // MAC rx
        .mac_rx_data(mac_rx_data),                             // O [63:0]
        .mac_rx_data_valid(mac_rx_data_valid),                 // O [7:0]
        .mac_rx_good_frame(mac_rx_good_frame),                 // O
        .mac_rx_bad_frame(mac_rx_bad_frame),                   // O
        // TRN tx
        .trn_td(rx_trn_td),                                    // O [63:0]
        .trn_trem_n(rx_trn_trem_n),                            // O [7:0]
        .trn_tsof_n(rx_trn_tsof_n),                            // O
        .trn_teof_n(rx_trn_teof_n),                            // O
        .trn_tsrc_rdy_n(rx_trn_tsrc_rdy_n),                    // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n),                       // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rerrfwd_n(trn_rerrfwd_n),                         // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // CFG
        .cfg_completer_id(cfg_completer_id),                   // I [15:0]
        .cfg_max_payload_size(cfg_max_payload_size),           // I [2:0]
        .send_irq(rx_send_irq),                                // O
        // EP arb
        .my_trn(rx_trn),                                       // I
        .drv_ep(rx_drvn)                                       // O
        );

    //-------------------------------------------------------
    // IRQ
    //-------------------------------------------------------
    irq #(
        .BARHIT(BARHIT),
        .BARMP_EN(IRQ_BARMP_EN),
        .BARMP_DIS(IRQ_BARMP_DIS),
        .BARMP_THR(IRQ_BARMP_THR)
    ) irq_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // CFG
        .cfg_interrupt_n(cfg_interrupt_n),                     // O
        .cfg_interrupt_rdy_n(cfg_interrupt_rdy_n),             // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        .send_irq(send_irq),                                   // I
        // EP arb
        .my_trn(irq_trn),                                      // I
        .drv_ep(irq_drvn),                                     // O
        .req_ep(irq_reqep)                                     // O
        );

    //-------------------------------------------------------
    // ARB
    //-------------------------------------------------------
    arb arb_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // CHN trn
        .chn_trn(chn_trn),                                     // I
        .chn_drvn(chn_drvn),                                   // O
        .chn_reqep(chn_reqep),                                 // O
        // ARB
        .tx_trn(tx_trn),                                       // O
        .tx_drvn(tx_drvn),                                     // I
        .tx_reqep(tx_reqep),                                   // I
        .rx_trn(rx_trn),                                       // O
        .rx_drvn(rx_drvn),                                     // I
        .irq_trn(irq_trn),                                     // O
        .irq_drvn(irq_drvn),                                   // I
        .irq_reqep(irq_reqep)                                  // I
        );

endmodule // chn

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////