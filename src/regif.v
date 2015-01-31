/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        regif.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects wrif and rdif logic
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

module regif # ( 
    parameter BARHIT = 0,
    // WRIF
    parameter WR_BARMP_CPL_ADDR = 6'b111111,
    parameter WR_BARMP_OP = 6'b111111,
    // RDIF
    parameter RD_BARMP_CPL_ADDR = 6'b111111,
    parameter RD_BARMP_OP = 6'b111111
    ) (

    input                    reg_int_clk,
    input                    reg_int_reset_n,

    input                    pcie_clk,
    input                    pcie_rst,

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
    input        [7:0]       cfg_bus_number,
    input        [4:0]       cfg_device_number,
    input        [2:0]       cfg_function_number,

    // REGIF
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

    // EP arb
    input                    chn_trn,
    output                   chn_drvn,
    output                   chn_reqep
    );

    //-------------------------------------------------------
    // Local PCIe trn protocol
    //-------------------------------------------------------
    wire         [15:0]      cfg_completer_id;

    //-------------------------------------------------------
    // WRIF
    //-------------------------------------------------------
    wire         [63:0]      wrif_trn_td;
    wire         [7:0]       wrif_trn_trem_n;
    wire                     wrif_trn_tsof_n;
    wire                     wrif_trn_teof_n;
    wire                     wrif_trn_tsrc_rdy_n;
    wire         [31:0]      wrif_IP2Bus_Mst_Addr;

    //-------------------------------------------------------
    // RDIF
    //-------------------------------------------------------
    wire         [63:0]      rdif_trn_td;
    wire         [7:0]       rdif_trn_trem_n;
    wire                     rdif_trn_tsof_n;
    wire                     rdif_trn_teof_n;
    wire                     rdif_trn_tsrc_rdy_n;
    wire         [31:0]      rdif_IP2Bus_Mst_Addr;

    //-------------------------------------------------------
    // REGIF ARB
    //-------------------------------------------------------
    // EP ARB
    wire                     ep_wrif_trn;
    wire                     ep_wrif_drvn;
    wire                     ep_wrif_reqep;
    wire                     ep_rdif_trn;
    wire                     ep_rdif_drvn;
    wire                     ep_rdif_reqep;
    // REGIF ARB
    wire                     wrif_trn;
    wire                     wrif_drvn;
    wire                     rdif_trn;
    wire                     rdif_drvn;

    //-------------------------------------------------------
    // assigns
    //-------------------------------------------------------
    assign cfg_completer_id = {cfg_bus_number, cfg_device_number, cfg_function_number};

    assign trn_td = wrif_trn_td | rdif_trn_td;
    assign trn_trem_n = wrif_trn_trem_n & rdif_trn_trem_n;
    assign trn_tsof_n = wrif_trn_tsof_n & rdif_trn_tsof_n;
    assign trn_teof_n = wrif_trn_teof_n & rdif_trn_teof_n;
    assign trn_tsrc_rdy_n = wrif_trn_tsrc_rdy_n & rdif_trn_tsrc_rdy_n;

    assign IP2Bus_Mst_Lock = 1'b0;
    assign IP2Bus_Mst_Reset = 1'b0;
    assign IP2Bus_Mst_Addr = wrif_IP2Bus_Mst_Addr | rdif_IP2Bus_Mst_Addr;

    //-------------------------------------------------------
    // WRIF
    //-------------------------------------------------------
    wrif #(
        // BAR MAPPING
        .BARHIT(BARHIT),
        .BARMP_CPL_ADDR(WR_BARMP_CPL_ADDR),
        .BARMP_OP(WR_BARMP_OP)
    ) wrif_mod (
        .reg_int_clk(reg_int_clk),                             // I
        .reg_int_reset_n(reg_int_reset_n),                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // TRN tx
        .trn_td(wrif_trn_td),                                  // O [63:0]
        .trn_trem_n(wrif_trn_trem_n),                          // O [7:0]
        .trn_tsof_n(wrif_trn_tsof_n),                          // O
        .trn_teof_n(wrif_trn_teof_n),                          // O
        .trn_tsrc_rdy_n(wrif_trn_tsrc_rdy_n),                  // O
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
        // REGIF
        .IP2Bus_MstWr_Req(IP2Bus_MstWr_Req),                   // O
        .IP2Bus_Mst_Addr(wrif_IP2Bus_Mst_Addr),                // O [31:0]
        .IP2Bus_Mst_BE(IP2Bus_Mst_BE),                         // O [3:0]
        .Bus2IP_Mst_CmdAck(Bus2IP_Mst_CmdAck),                 // I
        .Bus2IP_Mst_Cmplt(Bus2IP_Mst_Cmplt),                   // I
        .Bus2IP_Mst_Error(Bus2IP_Mst_Error),                   // I
        .IP2Bus_MstWr_d(IP2Bus_MstWr_d),                       // O [31:0]
        .Bus2IP_MstWr_dst_rdy_n(Bus2IP_MstWr_dst_rdy_n),       // I
        // EP ARB
        .my_trn(ep_wrif_trn),                                  // I
        .drv_ep(ep_wrif_drvn),                                 // O
        .req_ep(ep_wrif_reqep),                                // O
        // REGIF ARB
        .my_regif(wrif_trn),                                   // I
        .drv_regif(wrif_drvn)                                  // O
        );

    //-------------------------------------------------------
    // RDIF
    //-------------------------------------------------------
    rdif #(
        // BAR MAPPING
        .BARHIT(BARHIT),
        .BARMP_CPL_ADDR(RD_BARMP_CPL_ADDR),
        .BARMP_OP(RD_BARMP_OP)
    ) rdif_mod (
        .reg_int_clk(reg_int_clk),                             // I
        .reg_int_reset_n(reg_int_reset_n),                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // TRN tx
        .trn_td(rdif_trn_td),                                  // O [63:0]
        .trn_trem_n(rdif_trn_trem_n),                          // O [7:0]
        .trn_tsof_n(rdif_trn_tsof_n),                          // O
        .trn_teof_n(rdif_trn_teof_n),                          // O
        .trn_tsrc_rdy_n(rdif_trn_tsrc_rdy_n),                  // O
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
        // REGIF
        .IP2Bus_MstRd_Req(IP2Bus_MstRd_Req),                   // O
        .IP2Bus_Mst_Addr(rdif_IP2Bus_Mst_Addr),                // O [31:0]
        .Bus2IP_Mst_CmdAck(Bus2IP_Mst_CmdAck),                 // I
        .Bus2IP_Mst_Cmplt(Bus2IP_Mst_Cmplt),                   // I
        .Bus2IP_Mst_Error(Bus2IP_Mst_Error),                   // I
        .Bus2IP_MstRd_d(Bus2IP_MstRd_d),                       // I [31:0]
        .Bus2IP_MstRd_src_rdy_n(Bus2IP_MstRd_src_rdy_n),       // I
        // EP ARB
        .my_trn(ep_rdif_trn),                                  // I
        .drv_ep(ep_rdif_drvn),                                 // O
        .req_ep(ep_rdif_reqep),                                // O
        // REGIF ARB
        .my_regif(rdif_trn),                                   // I
        .drv_regif(rdif_drvn)                                  // O
        );

    //-------------------------------------------------------
    // REGIF ARB
    //-------------------------------------------------------
    regif_arb arb_mod (
        .reg_int_clk(reg_int_clk),                             // I
        .reg_int_reset_n(reg_int_reset_n),                     // I
        .pcie_clk(pcie_clk),                                   // I
        .pcie_rst(pcie_rst),                                   // I
        // CHN trn
        .chn_trn(chn_trn),                                     // I
        .chn_drvn(chn_drvn),                                   // O
        .chn_reqep(chn_reqep),                                 // O
        // EP ARB
        .ep_wrif_trn(ep_wrif_trn),                             // O
        .ep_wrif_drvn(ep_wrif_drvn),                           // I
        .ep_wrif_reqep(ep_wrif_reqep),                         // I
        .ep_rdif_trn(ep_rdif_trn),                             // O
        .ep_rdif_drvn(ep_rdif_drvn),                           // I
        .ep_rdif_reqep(ep_rdif_reqep),                         // I
        // REGIF ARB
        .wrif_trn(wrif_trn),                                   // O
        .wrif_drvn(wrif_drvn),                                 // I
        .rdif_trn(rdif_trn),                                   // O
        .rdif_drvn(rdif_drvn)                                  // I
        );

endmodule // regif

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////