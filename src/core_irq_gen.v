/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        core_irq_gen.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Gen IRQs.
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

module core_irq_gen (

    input                    clk,
    input                    rst,

    // hst_ctrl
    input                    irq_en,
    input                    irq_dis,
    input        [31:0]      irq_thr,

    // CFG
    output reg               cfg_interrupt_n,
    input                    cfg_interrupt_rdy_n,
    input        [3:0]       trn_tbuf_av,
    input                    send_irq,

    // EP arb
    input                    my_trn,
    output reg               drv_ep,
    output reg               req_ep
    );

    // localparam
    localparam s0 = 8'b00000000;
    localparam s1 = 8'b00000001;
    localparam s2 = 8'b00000010;
    localparam s3 = 8'b00000100;
    localparam s4 = 8'b00001000;
    localparam s5 = 8'b00010000;
    localparam s6 = 8'b00100000;
    localparam s7 = 8'b01000000;
    localparam s8 = 8'b10000000;

    //-------------------------------------------------------
    // Local IRQ gen
    //-------------------------------------------------------
    reg          [7:0]       irq_gen_fsm;
    reg          [29:0]      counter;

    ////////////////////////////////////////////////
    // IRQ gen
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            req_ep <= 1'b0;
            drv_ep <= 1'b0;
            cfg_interrupt_n <= 1'b1;
            irq_gen_fsm <= s0;
        end
        
        else begin  // not rst

            case (irq_gen_fsm)

                s0 : begin
                    if (send_irq && !irq_dis) begin
                        req_ep <= 1'b1;
                        irq_gen_fsm <= s1;
                    end
                end

                s1 : begin
                    if (my_trn) begin
                        req_ep <= 1'b0;
                        drv_ep <= 1'b1;
                        irq_gen_fsm <= s2;
                    end
                end

                s2 : begin
                    if (trn_tbuf_av[1]) begin
                        cfg_interrupt_n <= 1'b0;
                        irq_gen_fsm <= s3;
                    end
                    else begin
                        drv_ep <= 1'b0;
                        irq_gen_fsm <= s5;
                    end
                end

                s3 : begin
                    if (!cfg_interrupt_rdy_n) begin
                        cfg_interrupt_n <= 1'b1;
                        drv_ep <= 1'b0;
                        irq_gen_fsm <= s4;
                    end
                end

                s4 : begin
                    counter <= 'b0;
                    if (irq_en) begin
                        irq_gen_fsm <= s6;
                    end
                end

                s5 : begin
                    if (trn_tbuf_av[1]) begin
                        req_ep <= 1'b1;
                        irq_gen_fsm <= s1;
                    end
                end

                s6 : begin
                    counter <= counter + 1;
                    if (irq_thr == counter) begin
                        irq_gen_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    irq_gen_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // core_irq_gen

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////