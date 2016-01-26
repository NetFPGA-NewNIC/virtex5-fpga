/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        wrif.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects wrif
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

module wrif # (
    // BAR MAPPING
    parameter BARHIT = 2,
    parameter BARMP_CPL_ADDR = 6'b111111,
    parameter BARMP_OP = 6'b111111
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
    input        [15:0]      cfg_completer_id,

    // REGIF
    output                   IP2Bus_MstWr_Req,
    output       [31:0]      IP2Bus_Mst_Addr,
    output       [3:0]       IP2Bus_Mst_BE,
    input                    Bus2IP_Mst_CmdAck,
    input                    Bus2IP_Mst_Cmplt,
    input                    Bus2IP_Mst_Error,
    output       [31:0]      IP2Bus_MstWr_d,
    input                    Bus2IP_MstWr_dst_rdy_n,

    // EP ARB
    input                    my_trn,
    output                   drv_ep,
    output                   req_ep,

    // REGIF ARB
    input                    my_regif,
    output                   drv_regif
    );

    //-------------------------------------------------------
    // Local tlp2regif
    //-------------------------------------------------------
    wire         [63:0]      cpl_addr;
    wire         [31:0]      acc_addr;
    wire         [31:0]      acc_data;
    wire                     acc_en;
    wire                     acc_en_ack;

    //-------------------------------------------------------
    // Local acc
    //-------------------------------------------------------
    wire                     snd_resp;
    wire                     snd_resp_ack;
    wire         [63:0]      resp;
    
    //-------------------------------------------------------
    // tlp2regif
    //-------------------------------------------------------
    tlp2regif # (
        .BARHIT(BARHIT),
        .BARMP_CPL_ADDR(BARMP_CPL_ADDR),
        .BARMP_OP(BARMP_OP),
        .WRIF(1)
    ) tlp2regif_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // tlp2regif
        .cpl_addr(cpl_addr),                                   // O [63:0]
        .acc_addr(acc_addr),                                   // O [31:0]
        .acc_data(acc_data),                                   // O [31:0]
        .acc_en(acc_en),                                       // O
        .acc_en_ack(acc_en_ack)                                // I
        );

    //-------------------------------------------------------
    // acc
    //-------------------------------------------------------
    wr_acc # (
        .ACK_CODE(32'h1),
        .NACK_CODE(32'h2)
    ) acc_mod (
        .clk(reg_int_clk),                                     // I
        .rst_n(reg_int_reset_n),                               // I
        // tlp2regif
        .acc_addr(acc_addr),                                   // I [31:0]
        .acc_data(acc_data),                                   // I [31:0]
        .acc_en(acc_en),                                       // I
        .acc_en_ack(acc_en_ack),                               // O
        // REGIF
        .IP2Bus_MstWr_Req(IP2Bus_MstWr_Req),                   // O
        .IP2Bus_Mst_Addr(IP2Bus_Mst_Addr),                     // O [31:0]
        .IP2Bus_Mst_BE(IP2Bus_Mst_BE),                         // O [3:0]
        .Bus2IP_Mst_CmdAck(Bus2IP_Mst_CmdAck),                 // I
        .Bus2IP_Mst_Cmplt(Bus2IP_Mst_Cmplt),                   // I
        .Bus2IP_Mst_Error(Bus2IP_Mst_Error),                   // I
        .IP2Bus_MstWr_d(IP2Bus_MstWr_d),                       // O [31:0]
        .Bus2IP_MstWr_dst_rdy_n(Bus2IP_MstWr_dst_rdy_n),       // I
        // regif2tlp
        .snd_resp(snd_resp),                                   // O
        .snd_resp_ack(snd_resp_ack),                           // I
        .resp(resp),                                           // O [63:0]
        // REGIF ARB
        .my_regif(my_regif),                                   // I
        .drv_regif(drv_regif)                                  // O
        );

    //-------------------------------------------------------
    // regif2tlp
    //-------------------------------------------------------
    regif2tlp regif2tlp_mod (
        .clk(pcie_clk),                                        // I
        .rst(pcie_rst),                                        // I
        // TRN tx
        .trn_td(trn_td),                                       // O [63:0]
        .trn_trem_n(trn_trem_n),                               // O [7:0]
        .trn_tsof_n(trn_tsof_n),                               // O
        .trn_teof_n(trn_teof_n),                               // O
        .trn_tsrc_rdy_n(trn_tsrc_rdy_n),                       // O
        .trn_tdst_rdy_n(trn_tdst_rdy_n),                       // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        // CFG
        .cfg_completer_id(cfg_completer_id),                   // I [15:0]
        // tlp2regif
        .cpl_addr(cpl_addr),                                   // I [63:0]
        // regif2tlp
        .snd_resp(snd_resp),                                   // I
        .snd_resp_ack(snd_resp_ack),                           // O
        .resp(resp),                                           // I [63:0]
        // EP ARB
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep),                                       // O
        .req_ep(req_ep)                                        // O
        );

endmodule // wrif

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////