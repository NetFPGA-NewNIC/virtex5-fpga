/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        naas_dma_v5.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects dma logic
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

module naas_dma_v5 # (
    parameter CHN0_RX_CONFIG_TIMESTAMP = 0,
    parameter CONFIG_MDIO_IF = 1,
    parameter CONFIG_REGIF = 0
    ) (

    // PCIe
    input                    sys_clk_p,
    input                    sys_clk_n,
    output       [7:0]       pci_exp_txp,
    output       [7:0]       pci_exp_txn,
    input        [7:0]       pci_exp_rxp,
    input        [7:0]       pci_exp_rxn,
    output                   pcie_clk,
    output                   pcie_rst,

    // BKD
    input                    bkd_clk,
    input                    bkd_rst,

    // BKD tx
    output       [63:0]      m_axis_tdata,
    output       [7:0]       m_axis_tstrb,
    output       [127:0]     m_axis_tuser,
    output                   m_axis_tvalid,
    output                   m_axis_tlast,
    input                    m_axis_tready,

    // BKD rx
    input        [63:0]      s_axis_tdata,
    input        [7:0]       s_axis_tstrb,
    input        [127:0]     s_axis_tuser,
    input                    s_axis_tvalid,
    input                    s_axis_tlast,
    output                   s_axis_tready,

    // REGIF
    input                    reg_int_clk,
    input                    reg_int_reset_n,
    output                   IP2Bus_MstRd_Req,
    output                   IP2Bus_MstWr_Req,
    output       [31:0]      IP2Bus_Mst_Addr,
    output       [3:0]       IP2Bus_Mst_BE,
    output                   IP2Bus_Mst_Lock,
    output                   IP2Bus_Mst_Reset,
    input                    Bus2IP_Mst_CmdAck,
    input                    Bus2IP_Mst_Cmplt,
    input                    Bus2IP_Mst_Error,
    input                    Bus2IP_Mst_Rearbitrate,
    input                    Bus2IP_Mst_Timeout,
    input        [31:0]      Bus2IP_MstRd_d,
    input                    Bus2IP_MstRd_src_rdy_n,
    output       [31:0]      IP2Bus_MstWr_d,
    input                    Bus2IP_MstWr_dst_rdy_n,

    // MDIO conf
    input                    mac_host_clk,
    input                    mac_host_reset,
    output       [1:0]       mac_host_opcode,
    output       [9:0]       mac_host_addr,
    output       [31:0]      mac_host_wr_data,
    input        [31:0]      mac_host_rd_data,
    output                   mac_host_miim_sel,
    output                   mac_host_req,
    input                    mac_host_miim_rdy
    );

    //-------------------------------------------------------
    // Local PCIe ep
    //-------------------------------------------------------
    wire                     sys_clk_c;
    wire                     sys_reset_n_c;
    wire                     refclkout;
    // TRN intf
    wire                     trn_clk_c;
    wire                     trn_reset_n_c;
    wire                     trn_lnk_up_n_c;
    // Tx Local-Link
    wire         [63:0]      trn_td_c;
    wire         [7:0]       trn_trem_n_c;
    wire                     trn_tsof_n_c;
    wire                     trn_teof_n_c;
    wire                     trn_tsrc_rdy_n_c;
    wire                     trn_tsrc_dsc_n_c;
    wire                     trn_tdst_rdy_n_c;
    wire                     trn_tdst_dsc_n_c;
    wire                     trn_terrfwd_n_c;
    wire         [3:0]       trn_tbuf_av_c;
    // Rx Local-Link
    wire         [63:0]      trn_rd_c;
    wire         [7:0]       trn_rrem_n_c;
    wire                     trn_rsof_n_c;
    wire                     trn_reof_n_c;
    wire                     trn_rsrc_rdy_n_c;
    wire                     trn_rsrc_dsc_n_c;
    wire                     trn_rdst_rdy_n_c;
    wire                     trn_rerrfwd_n_c;
    wire                     trn_rnp_ok_n_c;
    wire         [6:0]       trn_rbar_hit_n_c;
    wire         [7:0]       trn_rfc_nph_av_c;
    wire         [11:0]      trn_rfc_npd_av_c;
    wire         [7:0]       trn_rfc_ph_av_c;
    wire         [11:0]      trn_rfc_pd_av_c;
    wire                     trn_rcpl_streaming_n_c;
    // CFG intf
    wire         [31:0]      cfg_do_c;
    wire                     cfg_rd_wr_done_n_c;
    wire         [31:0]      cfg_di_c;
    wire         [3:0]       cfg_byte_en_n_c;
    wire         [9:0]       cfg_dwaddr_c;
    wire                     cfg_wr_en_n_c;
    wire                     cfg_rd_en_n_c;
    wire                     cfg_err_cor_n_c;
    wire                     cfg_err_ur_n_c;
    wire                     cfg_err_cpl_rdy_n_c;
    wire                     cfg_err_ecrc_n_c;
    wire                     cfg_err_cpl_timeout_n_c;
    wire                     cfg_err_cpl_abort_n_c;
    wire                     cfg_err_cpl_unexpect_n_c;
    wire                     cfg_err_posted_n_c;
    wire         [47:0]      cfg_err_tlp_cpl_header_c;
    wire                     cfg_err_locked_n_c = 1'b1;
    wire                     cfg_interrupt_n_c;
    wire                     cfg_interrupt_rdy_n_c;
    wire                     cfg_interrupt_assert_n_c;
    wire         [7:0]       cfg_interrupt_di_c;
    wire         [7:0]       cfg_interrupt_do_c;
    wire         [2:0]       cfg_interrupt_mmenable_c;
    wire                     cfg_interrupt_msienable_c;
    wire                     cfg_to_turnoff_n_c;
    wire                     cfg_pm_wake_n_c;
    wire         [2:0]       cfg_pcie_link_state_n_c;
    wire                     cfg_trn_pending_n_c;
    wire         [7:0]       cfg_bus_number_c;
    wire         [4:0]       cfg_device_number_c;
    wire         [2:0]       cfg_function_number_c;
    wire         [15:0]      cfg_status_c;
    wire         [15:0]      cfg_command_c;
    wire         [15:0]      cfg_dstatus_c;
    wire         [15:0]      cfg_dcommand_c;
    wire         [15:0]      cfg_lstatus_c;
    wire         [15:0]      cfg_lcommand_c;
    wire         [63:0]      cfg_dsn_n_c;

    //-------------------------------------------------------
    // Local CHN ARB
    //-------------------------------------------------------
    // CHN0 trn
    wire                     chn0_trn;
    wire                     chn0_drvn;
    wire                     chn0_reqep;
    // REGIF trn
    wire                     regif_trn;
    wire                     regif_drvn;
    wire                     regif_reqep;

    //-------------------------------------------------------
    // Local CHN0
    //-------------------------------------------------------
    wire         [63:0]      chn0_trn_td;
    wire         [7:0]       chn0_trn_trem_n;
    wire                     chn0_trn_tsof_n;
    wire                     chn0_trn_teof_n;
    wire                     chn0_trn_tsrc_rdy_n;
    wire                     chn0_cfg_interrupt_n;

    //-------------------------------------------------------
    // Local MDIO conf
    //-------------------------------------------------------
    wire                     mdio_cfg_interrupt_n;

    //-------------------------------------------------------
    // Local REGIF
    //-------------------------------------------------------
    wire         [63:0]      regif_trn_td;
    wire         [7:0]       regif_trn_trem_n;
    wire                     regif_trn_tsof_n;
    wire                     regif_trn_teof_n;
    wire                     regif_trn_tsrc_rdy_n;

    //-------------------------------------------------------
    // Virtex5-FX Global Clock Buffer
    //-------------------------------------------------------
    IBUFDS refclk_ibuf (.O(sys_clk_c), .I(sys_clk_p), .IB(sys_clk_n));  // 100 MHz

    //-------------------------------------------------------
    // ep_rst
    //-------------------------------------------------------
    ep_rst ep_rst_mod (
        .clk250(pcie_clk),                                     // I
        .trn_reset_n(trn_reset_n_c),                           // I
        .trn_lnk_up_n(trn_lnk_up_n_c),                         // I
        .rst250(pcie_rst)                                      // O
        );

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign sys_reset_n_c = 1'b1;         // MF: no reset available
    assign trn_tsrc_dsc_n_c = 1'b1;      // MF: !discontinue
    assign trn_terrfwd_n_c = 1'b1;       // MF: !terrfwd
    assign trn_rdst_rdy_n_c = 1'b0;      // MF: always listen
    assign trn_rnp_ok_n_c = 1'b0;        // MF: rnp_ok
    assign trn_rcpl_streaming_n_c = 1'b0;   // MF: streaming
    assign cfg_interrupt_assert_n_c = 1'b1; // MF: not used with MSI
    assign cfg_interrupt_di_c = 8'b0;    // MF
    assign cfg_trn_pending_n_c = 1'b1;   // MF: needs implementation
    assign cfg_dsn_n_c = {32'h00000001,  {{8'h1},24'h000A35}};
    assign cfg_err_cor_n_c = 1'b1;
    assign cfg_err_ur_n_c = 1'b1;
    assign cfg_err_ecrc_n_c = 1'b1;
    assign cfg_err_cpl_timeout_n_c = 1'b1;
    assign cfg_err_cpl_abort_n_c = 1'b1;
    assign cfg_err_cpl_unexpect_n_c = 1'b1;
    assign cfg_err_posted_n_c = 1'b0;
    assign cfg_pm_wake_n_c = 1'b1;
    assign cfg_dwaddr_c = 'b0;
    assign cfg_rd_en_n_c = 1'b1;
    assign cfg_err_tlp_cpl_header_c = 'b0;
    assign cfg_di_c = 'b0;
    assign cfg_byte_en_n_c = 'hF;
    assign cfg_wr_en_n_c = 1'b1;
    assign pcie_clk = trn_clk_c;

    assign trn_td_c = chn0_trn_td | regif_trn_td;
    assign trn_trem_n_c = chn0_trn_trem_n & regif_trn_trem_n;
    assign trn_tsof_n_c = chn0_trn_tsof_n & regif_trn_tsof_n;
    assign trn_teof_n_c = chn0_trn_teof_n & regif_trn_teof_n;
    assign trn_tsrc_rdy_n_c = chn0_trn_tsrc_rdy_n & regif_trn_tsrc_rdy_n;
    assign cfg_interrupt_n_c = chn0_cfg_interrupt_n & mdio_cfg_interrupt_n;

    //-------------------------------------------------------
    // PCIe ep
    //-------------------------------------------------------
    endpoint_blk_plus_v1_15 #(
        .XROM_BAR(32'h00000000)     // MF: disable f*k rom
    ) ep (
        // PCIe //
        .pci_exp_txp(pci_exp_txp),                             // O [7:0]
        .pci_exp_txn(pci_exp_txn),                             // O [7:0]
        .pci_exp_rxp(pci_exp_rxp),                             // O [7:0]
        .pci_exp_rxn(pci_exp_rxn),                             // O [7:0]
        .sys_clk(sys_clk_c),                                   // I
        .sys_reset_n(sys_reset_n_c),                           // I
        .refclkout(refclkout),                                 // O
        // TRN Intf
        .trn_clk(trn_clk_c),                                   // O
        .trn_reset_n(trn_reset_n_c),                           // O
        .trn_lnk_up_n(trn_lnk_up_n_c),                         // O
        // Tx Local-Link
        .trn_td(trn_td_c),                                     // I [63:0]
        .trn_trem_n(trn_trem_n_c),                             // I [7:0]
        .trn_tsof_n(trn_tsof_n_c),                             // I
        .trn_teof_n(trn_teof_n_c),                             // I
        .trn_tsrc_rdy_n(trn_tsrc_rdy_n_c),                     // I
        .trn_tsrc_dsc_n(trn_tsrc_dsc_n_c),                     // I
        .trn_tdst_rdy_n(trn_tdst_rdy_n_c),                     // O
        .trn_tdst_dsc_n(trn_tdst_dsc_n_c),                     // O
        .trn_terrfwd_n(trn_terrfwd_n_c),                       // I
        .trn_tbuf_av(trn_tbuf_av_c),                           // O [3:0]
        // Rx Local-Link
        .trn_rd(trn_rd_c),                                     // O [63:0]
        .trn_rrem_n(trn_rrem_n_c),                             // O [7:0]
        .trn_rsof_n(trn_rsof_n_c),                             // O
        .trn_reof_n(trn_reof_n_c),                             // O
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n_c),                     // O
        .trn_rsrc_dsc_n(trn_rsrc_dsc_n_c),                     // O
        .trn_rdst_rdy_n(trn_rdst_rdy_n_c),                     // I
        .trn_rerrfwd_n(trn_rerrfwd_n_c),                       // O
        .trn_rnp_ok_n(trn_rnp_ok_n_c),                         // I
        .trn_rbar_hit_n(trn_rbar_hit_n_c),                     // O [6:0]
        .trn_rfc_nph_av(trn_rfc_nph_av_c),                     // O [11:0]
        .trn_rfc_npd_av(trn_rfc_npd_av_c),                     // O [7:0]
        .trn_rfc_ph_av(trn_rfc_ph_av_c),                       // O [11:0]
        .trn_rfc_pd_av(trn_rfc_pd_av_c),                       // O [7:0]
        .trn_rcpl_streaming_n(trn_rcpl_streaming_n_c),         // I
        // CFG Intf
        .cfg_do(cfg_do_c),                                     // O [31:0]
        .cfg_rd_wr_done_n(cfg_rd_wr_done_n_c),                 // O
        .cfg_di(cfg_di_c),                                     // I [31:0]
        .cfg_byte_en_n(cfg_byte_en_n_c),                       // I [3:0]
        .cfg_dwaddr(cfg_dwaddr_c),                             // I [9:0]
        .cfg_wr_en_n(cfg_wr_en_n_c),                           // I
        .cfg_rd_en_n(cfg_rd_en_n_c),                           // I
        .cfg_err_cor_n(cfg_err_cor_n_c),                       // I
        .cfg_err_ur_n(cfg_err_ur_n_c),                         // I
        .cfg_err_cpl_rdy_n(cfg_err_cpl_rdy_n_c),               // O
        .cfg_err_ecrc_n(cfg_err_ecrc_n_c),                     // I
        .cfg_err_cpl_timeout_n(cfg_err_cpl_timeout_n_c),       // I
        .cfg_err_cpl_abort_n(cfg_err_cpl_abort_n_c),           // I
        .cfg_err_cpl_unexpect_n(cfg_err_cpl_unexpect_n_c),     // I
        .cfg_err_posted_n(cfg_err_posted_n_c),                 // I
        .cfg_err_tlp_cpl_header(cfg_err_tlp_cpl_header_c),     // I [47:0]
        .cfg_err_locked_n(cfg_err_locked_n_c),                 // I
        .cfg_interrupt_n(cfg_interrupt_n_c),                   // I
        .cfg_interrupt_rdy_n(cfg_interrupt_rdy_n_c),           // O
        .cfg_interrupt_assert_n(cfg_interrupt_assert_n_c),     // I
        .cfg_interrupt_di(cfg_interrupt_di_c),                 // I [7:0]
        .cfg_interrupt_do(cfg_interrupt_do_c),                 // O [7:0]
        .cfg_interrupt_mmenable(cfg_interrupt_mmenable_c),     // O [2:0]
        .cfg_interrupt_msienable(cfg_interrupt_msienable_c),   // O
        .cfg_to_turnoff_n(cfg_to_turnoff_n_c),                 // O
        .cfg_pm_wake_n(cfg_pm_wake_n_c),                       // I
        .cfg_pcie_link_state_n(cfg_pcie_link_state_n_c),       // O [2:0]
        .cfg_trn_pending_n(cfg_trn_pending_n_c),               // I
        .cfg_bus_number(cfg_bus_number_c),                     // O [7:0]
        .cfg_device_number(cfg_device_number_c),               // O [4:0]
        .cfg_function_number(cfg_function_number_c),           // O [2:0]
        .cfg_status(cfg_status_c),                             // O [15:0]
        .cfg_command(cfg_command_c),                           // O [15:0]
        .cfg_dstatus(cfg_dstatus_c),                           // O [15:0]
        .cfg_dcommand(cfg_dcommand_c),                         // O [15:0]
        .cfg_lstatus(cfg_lstatus_c),                           // O [15:0]
        .cfg_lcommand(cfg_lcommand_c),                         // O [15:0]
        .cfg_dsn(cfg_dsn_n_c),                                 // I [63:0]
        `ifdef SIMULATION
        .fast_train_simulation_only(1'b1)
        `else
        .fast_train_simulation_only(1'b0)
        `endif
        );

    //-------------------------------------------------------
    // CHN ARB
    //-------------------------------------------------------
    chn_arb chn_arb_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // CHN0 trn
        .chn0_trn(chn0_trn),                                   // O
        .chn0_drvn(chn0_drvn),                                 // I
        .chn0_reqep(chn0_reqep),                               // I
        // REGIF trn
        .regif_trn(regif_trn),                                 // O
        .regif_drvn(regif_drvn),                               // I
        .regif_reqep(regif_reqep)                              // I
        );

    //-------------------------------------------------------
    // CHN0
    //-------------------------------------------------------
    chn #(
        .BARHIT(2),
        // Tx
        .TX_BARMP_CPL_ADDR  (6'b101100),
        .TX_BARMP_LBUF1_ADDR(6'b100000),
        .TX_BARMP_LBUF1_EN  (6'b101000),
        .TX_BARMP_LBUF2_ADDR(6'b100010),
        .TX_BARMP_LBUF2_EN  (6'b101001),
        .TX_BARMP_WRBCK     (6'b101110),
        // Rx
        .RX_BARMP_LBUF1_ADDR(6'b010000),
        .RX_BARMP_LBUF1_EN  (6'b011000),
        .RX_BARMP_LBUF2_ADDR(6'b010010),
        .RX_BARMP_LBUF2_EN  (6'b011001),
        .RX_BARMP_WRBCK     (6'b011110),
        // IRQ
        .IRQ_BARMP_EN (6'b001000),
        .IRQ_BARMP_DIS(6'b001001),
        .IRQ_BARMP_THR(6'b001010),
        // RQ_TAG_BASE
        .RQTB(5'b11100),
        // Outstanding request width
        .OSRW(2),
        .RX_CONFIG_TIMESTAMP(CHN0_RX_CONFIG_TIMESTAMP)
    ) chn0 (
        .bkd_clk(bkd_clk),                                     // I
        .bkd_rst(bkd_rst),                                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // BKD tx
        .m_axis_tdata(m_axis_tdata),                           // O [63:0]
        .m_axis_tstrb(m_axis_tstrb),                           // O [7:0]
        .m_axis_tuser(m_axis_tuser),                           // O [127:0]
        .m_axis_tvalid(m_axis_tvalid),                         // O
        .m_axis_tlast(m_axis_tlast),                           // O
        .m_axis_tready(m_axis_tready),                         // I
        // BKD rx
        .s_axis_tdata(s_axis_tdata),                           // I [63:0]
        .s_axis_tstrb(s_axis_tstrb),                           // I [7:0]
        .s_axis_tuser(s_axis_tuser),                           // I [127:0]
        .s_axis_tvalid(s_axis_tvalid),                         // I
        .s_axis_tlast(s_axis_tlast),                           // I
        .s_axis_tready(s_axis_tready),                         // O
        // TRN tx
        .trn_td(chn0_trn_td),                                  // O [63:0]
        .trn_trem_n(chn0_trn_trem_n),                          // O [7:0]
        .trn_tsof_n(chn0_trn_tsof_n),                          // O
        .trn_teof_n(chn0_trn_teof_n),                          // O
        .trn_tsrc_rdy_n(chn0_trn_tsrc_rdy_n),                  // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n_c),                     // I
        .trn_tbuf_av(trn_tbuf_av_c),                           // I [3:0]
        // TRN rx
        .trn_rd(trn_rd_c),                                     // I [63:0]
        .trn_rrem_n(trn_rrem_n_c),                             // I [7:0]
        .trn_rsof_n(trn_rsof_n_c),                             // I
        .trn_reof_n(trn_reof_n_c),                             // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n_c),                     // I
        .trn_rerrfwd_n(trn_rerrfwd_n_c),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n_c),                     // I [6:0]
        // CFG
        .cfg_interrupt_n(chn0_cfg_interrupt_n),                // O
        .cfg_interrupt_rdy_n(cfg_interrupt_rdy_n_c),           // I
        .cfg_bus_number(cfg_bus_number_c),                     // I [7:0]
        .cfg_device_number(cfg_device_number_c),               // I [4:0]
        .cfg_function_number(cfg_function_number_c),           // I [2:0]
        .cfg_dcommand(cfg_dcommand_c),                         // I [15:0]
        // EP arb
        .chn_trn(chn0_trn),                                    // I
        .chn_drvn(chn0_drvn),                                  // O
        .chn_reqep(chn0_reqep)                                 // O
        );

    //-------------------------------------------------------
    // MDIO conf
    //-------------------------------------------------------
    generate if (CONFIG_MDIO_IF) begin
    mdioconf #(
        .BARHIT(0),
        .BARMP_WRREG(6'b000100)
    ) mdioconf_mod (
        .bkd_rst(bkd_rst),                                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // TRN rx
        .trn_rd(trn_rd_c),                                     // I [63:0]
        .trn_rrem_n(trn_rrem_n_c),                             // I [7:0]
        .trn_rsof_n(trn_rsof_n_c),                             // I
        .trn_reof_n(trn_reof_n_c),                             // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n_c),                     // I
        .trn_rerrfwd_n(trn_rerrfwd_n_c),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n_c),                     // I [6:0]
        // CFG
        .cfg_interrupt_n(mdio_cfg_interrupt_n),                // O
        .cfg_interrupt_rdy_n(cfg_interrupt_rdy_n_c),           // I
        // Host Conf Intf
        .host_clk(mac_host_clk),                               // I
        .host_reset(mac_host_reset),                           // I
        .host_opcode(mac_host_opcode),                         // O [1:0]
        .host_addr(mac_host_addr),                             // O [9:0]
        .host_wr_data(mac_host_wr_data),                       // O [31:0]
        .host_rd_data(mac_host_rd_data),                       // I [31:0]
        .host_miim_sel(mac_host_miim_sel),                     // O
        .host_req(mac_host_req),                               // O
        .host_miim_rdy(mac_host_miim_rdy)                      // I
        );
    end
    else begin
        assign mdio_cfg_interrupt_n = 1'b1; 
    end endgenerate

    //-------------------------------------------------------
    // REGIF
    //-------------------------------------------------------
    generate if (CONFIG_REGIF) begin
    regif #(
        .BARHIT(0),
        // WRIF
        .WR_BARMP_CPL_ADDR(6'b101100),
        .WR_BARMP_OP      (6'b100000),
        // RDIF
        .RD_BARMP_CPL_ADDR(6'b011100),
        .RD_BARMP_OP      (6'b010000)
    ) regif_mod (
        .reg_int_clk(reg_int_clk),                             // I
        .reg_int_reset_n(reg_int_reset_n),                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // TRN tx
        .trn_td(regif_trn_td),                                 // O [63:0]
        .trn_trem_n(regif_trn_trem_n),                         // O [7:0]
        .trn_tsof_n(regif_trn_tsof_n),                         // O
        .trn_teof_n(regif_trn_teof_n),                         // O
        .trn_tsrc_rdy_n(regif_trn_tsrc_rdy_n),                 // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n_c),                     // I
        .trn_tbuf_av(trn_tbuf_av_c),                           // I [3:0]
        // TRN rx
        .trn_rd(trn_rd_c),                                     // I [63:0]
        .trn_rrem_n(trn_rrem_n_c),                             // I [7:0]
        .trn_rsof_n(trn_rsof_n_c),                             // I
        .trn_reof_n(trn_reof_n_c),                             // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n_c),                     // I
        .trn_rerrfwd_n(trn_rerrfwd_n_c),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n_c),                     // I [6:0]
        // CFG
        .cfg_bus_number(cfg_bus_number_c),                     // I [7:0]
        .cfg_device_number(cfg_device_number_c),               // I [4:0]
        .cfg_function_number(cfg_function_number_c),           // I [2:0]
        // REGIF
        .IP2Bus_MstRd_Req(IP2Bus_MstRd_Req),                   // O
        .IP2Bus_MstWr_Req(IP2Bus_MstWr_Req),                   // O
        .IP2Bus_Mst_Addr(IP2Bus_Mst_Addr),                     // O [31:0]
        .IP2Bus_Mst_BE(IP2Bus_Mst_BE),                         // O [3:0]
        .IP2Bus_Mst_Lock(IP2Bus_Mst_Lock),                     // O
        .IP2Bus_Mst_Reset(IP2Bus_Mst_Reset),                   // O
        .Bus2IP_Mst_CmdAck(Bus2IP_Mst_CmdAck),                 // I
        .Bus2IP_Mst_Cmplt(Bus2IP_Mst_Cmplt),                   // I
        .Bus2IP_Mst_Error(Bus2IP_Mst_Error),                   // I
        .Bus2IP_Mst_Rearbitrate(Bus2IP_Mst_Rearbitrate),       // I
        .Bus2IP_Mst_Timeout(Bus2IP_Mst_Timeout),               // I
        .Bus2IP_MstRd_d(Bus2IP_MstRd_d),                       // I [31:0]
        .Bus2IP_MstRd_src_rdy_n(Bus2IP_MstRd_src_rdy_n),       // I
        .IP2Bus_MstWr_d(IP2Bus_MstWr_d),                       // O [31:0]
        .Bus2IP_MstWr_dst_rdy_n(Bus2IP_MstWr_dst_rdy_n),       // I
        // EP arb
        .chn_trn(regif_trn),                                   // I
        .chn_drvn(regif_drvn),                                 // O
        .chn_reqep(regif_reqep)                                // O
        );
    end
    else begin
        assign regif_drvn = 1'b0;
        assign regif_reqep = 1'b0;
        assign regif_trn_td = 'b0;
        assign regif_trn_trem_n = 'hFF;
        assign regif_trn_tsof_n = 1'b1;
        assign regif_trn_teof_n = 1'b1;
        assign regif_trn_tsrc_rdy_n = 1'b1;
    end endgenerate

endmodule // naas_dma_v5

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////