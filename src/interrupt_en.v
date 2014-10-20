/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        interrupt_en.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Global interrupt control.
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

`define MEM_WR64_FMT_TYPE 7'b11_00000
`define MEM_WR32_FMT_TYPE 7'b10_00000
`define MEM_RD64_FMT_TYPE 7'b01_00000
`define MEM_RD32_FMT_TYPE 7'b00_00000

module interrupt_en (

    input                   trn_clk,
    input                   reset,

    input       [63:0]      trn_rd,
    input       [7:0]       trn_rrem_n,
    input                   trn_rsof_n,
    input                   trn_reof_n,
    input                   trn_rsrc_rdy_n,
    input                   trn_rsrc_dsc_n,
    input       [6:0]       trn_rbar_hit_n,
    input                   trn_rdst_rdy_n,
    output reg              interrupts_enabled,
    output reg  [31:0]      interrupt_period
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

    // Local wires and reg

    reg     [7:0]   state;
    reg     [7:0]   period_fsm;
    reg             interrupts_enabled_i;
    reg             interrupts_not_enabled_i;
    reg             period_received;
    reg     [31:0]  aux_dw;
    reg     [31:0]  aux_period;

    ////////////////////////////////////////////////
    // output
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            interrupts_enabled <= 1'b1;
            interrupt_period <= 'h3D090;
            period_fsm <= s0;
        end
        
        else begin  // not reset
            if (interrupts_enabled_i) begin
                interrupts_enabled <= 1'b1;
            end
            else if (interrupts_not_enabled_i) begin
                interrupts_enabled <= 1'b0;
            end

            case (period_fsm)
                s0 : begin
                    aux_period[7:0]   <= aux_dw[31:24];
                    aux_period[15:8]  <= aux_dw[23:16];
                    aux_period[23:16] <= aux_dw[15:8];
                    aux_period[31:24] <= aux_dw[7:0];
                    if (period_received) begin
                        period_fsm <= s1;
                    end
                end
                s1 : begin
                    interrupt_period[29:0] <= aux_period[31:2];
                    period_fsm <= s0;
                end
            endcase

        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // interrupts_enabled & TLP reception
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            interrupts_enabled_i <= 1'b0;
            interrupts_not_enabled_i <= 1'b0;
            period_received <= 1'b0;
            state <= s0;
        end
        
        else begin  // not reset

            interrupts_enabled_i <= 1'b0;
            interrupts_not_enabled_i <= 1'b0;
            period_received <= 1'b0;

            case (state)

                s0 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n) && (!trn_rbar_hit_n[2])) begin
                        if (trn_rd[62:56] == `MEM_WR32_FMT_TYPE) begin
                            state <= s1;
                        end
                        else if (trn_rd[62:56] == `MEM_WR64_FMT_TYPE) begin
                            state <= s2;
                        end
                    end
                end

                s1 : begin
                    aux_dw <= trn_rd[31:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[39:34])

                            6'b001000 : begin     // interrupts eneable
                                interrupts_enabled_i <= 1'b1;
                                state <= s0;
                            end

                            6'b001001 : begin     // interrupts disable
                                interrupts_not_enabled_i <= 1'b1;
                                state <= s0;
                            end

                            6'b001010 : begin     // interrupts period
                                period_received <= 1'b1;
                                state <= s0;
                            end

                            default : begin //other addresses
                                state <= s0;
                            end

                        endcase
                    end
                end

                s2 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[7:2])

                            6'b001000 : begin     // interrupts eneable
                                interrupts_enabled_i <= 1'b1;
                                state <= s0;
                            end

                            6'b001001 : begin     // interrupts disable
                                interrupts_not_enabled_i <= 1'b1;
                                state <= s0;
                            end

                            6'b001010 : begin     // interrupts period
                                state <= s3;
                            end

                            default : begin //other addresses
                                state <= s0;
                            end

                        endcase
                    end
                end

                s3 : begin
                    aux_dw <= trn_rd[63:32];
                    period_received <= 1'b1;
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        state <= s0;
                    end
                end

                default : begin //other TLPs
                    state <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // interrupt_en

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////