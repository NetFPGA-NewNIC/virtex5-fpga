/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        core_irq.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Interconnects channel interrupt control.
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

module core_irq # (
    parameter BARHIT = 2,
    parameter BARMP_EN = 6'bxxxxxx,
    parameter BARMP_DIS = 6'bxxxxxx,
    parameter BARMP_THR = 6'bxxxxxx
    ) (

    input                    clk,
    input                    rst,

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
    input        [3:0]       trn_tbuf_av,
    input                    send_irq,

    // EP arb
    input                    my_trn,
    output                   drv_ep,
    output                   req_ep
    );

    //-------------------------------------------------------
    // Local hst_ctrl
    //-------------------------------------------------------
    wire                     irq_en;
    wire                     irq_dis;
    wire         [31:0]      irq_thr;

    //-------------------------------------------------------
    // irq_gen
    //-------------------------------------------------------
    core_irq_gen core_irq_gen_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // hst_ctrl
        .irq_en(irq_en),                                       // I
        .irq_dis(irq_dis),                                     // I
        .irq_thr(irq_thr),                                     // I [31:0]
        // CFG
        .cfg_interrupt_n(cfg_interrupt_n),                     // O
        .cfg_interrupt_rdy_n(cfg_interrupt_rdy_n),             // I
        .trn_tbuf_av(trn_tbuf_av),                             // I [3:0]
        .send_irq(send_irq),                                   // I
        // EP arb
        .my_trn(my_trn),                                       // I
        .drv_ep(drv_ep),                                       // O
        .req_ep(req_ep)                                        // O
        );

    //-------------------------------------------------------
    // hst_ctrl
    //-------------------------------------------------------
    irq_hst_ctrl # (
        .BARHIT(BARHIT),
        .BARMP_EN(BARMP_EN),
        .BARMP_DIS(BARMP_DIS),
        .BARMP_THR(BARMP_THR)
    ) hst_ctrl_mod (
        .clk(clk),                                             // I
        .rst(rst),                                             // I
        // TRN rx
        .trn_rd(trn_rd),                                       // I [63:0]
        .trn_rrem_n(trn_rrem_n),                               // I [7:0]
        .trn_rsof_n(trn_rsof_n),                               // I
        .trn_reof_n(trn_reof_n),                               // I
        .trn_rsrc_rdy_n(trn_rsrc_rdy_n),                       // I
        .trn_rbar_hit_n(trn_rbar_hit_n),                       // I [6:0]
        // hst_ctrl
        .irq_en(irq_en),                                       // O
        .irq_dis(irq_dis),                                     // O
        .irq_thr(irq_thr)                                      // O [31:0]
        );

endmodule // core_irq

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////