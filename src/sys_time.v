/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        sys_time.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        System time.
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

module sys_time (

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
    output reg  [31:0]      sys_nsecs,
    output reg  [31:0]      sys_secs,
    output reg              rx_timestamp_en
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
    reg     [7:0]   nsecs_fsm;
    reg     [7:0]   secs_fsm;
    reg             nsecs_received;
    reg             secs_received;
    reg     [31:0]  aux_dw;
    reg     [31:0]  aux_nsecs;
    reg     [31:0]  aux_secs;
    reg             rx_timestamp_en_i;
    reg             rx_timestamp_not_en_i;

    ////////////////////////////////////////////////
    // output
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            rx_timestamp_en <= 1'b0;
            nsecs_fsm <= s0;
            secs_fsm <= s0;
        end
        
        else begin  // not reset
            if (rx_timestamp_en_i) begin
                rx_timestamp_en <= 1'b1;
            end
            if (rx_timestamp_not_en_i) begin
                rx_timestamp_en <= 1'b0;
            end

            case (nsecs_fsm)
                s0 : begin
                    aux_nsecs[7:0]   <= aux_dw[31:24];
                    aux_nsecs[15:8]  <= aux_dw[23:16];
                    aux_nsecs[23:16] <= aux_dw[15:8];
                    aux_nsecs[31:24] <= aux_dw[7:0];
                    if (nsecs_received) begin
                        nsecs_fsm <= s1;
                    end
                end
                s1 : begin
                    sys_nsecs <= aux_nsecs;
                    nsecs_fsm <= s0;
                end
            endcase

            case (secs_fsm)
                s0 : begin
                    aux_secs[7:0]   <= aux_dw[31:24];
                    aux_secs[15:8]  <= aux_dw[23:16];
                    aux_secs[23:16] <= aux_dw[15:8];
                    aux_secs[31:24] <= aux_dw[7:0];
                    if (secs_received) begin
                        secs_fsm <= s1;
                    end
                end
                s1 : begin
                    sys_secs <= aux_secs;
                    secs_fsm <= s0;
                end
            endcase

        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // TLP reception
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            nsecs_received <= 1'b0;
            secs_received <= 1'b0;
            rx_timestamp_en_i <= 1'b0;
            rx_timestamp_not_en_i <= 1'b0;
            state <= s0;
        end
        
        else begin  // not reset

            nsecs_received <= 1'b0;
            secs_received <= 1'b0;

            rx_timestamp_en_i <= 1'b0;
            rx_timestamp_not_en_i <= 1'b0;

            case (state)

                s0 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n) && (!trn_rbar_hit_n[0])) begin
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
                        case (trn_rd[37:34])

                            4'b1000 : begin     // nanosecs
                                nsecs_received <= 1'b1;
                                state <= s0;
                            end

                            4'b1001 : begin     // secs
                                secs_received <= 1'b1;
                                state <= s0;
                            end

                            4'b1010 : begin     // timestamp_en
                                rx_timestamp_en_i <= 1'b1;
                                state <= s0;
                            end

                            4'b1011 : begin     // timestamp_disable
                                rx_timestamp_not_en_i <= 1'b1;
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
                        case (trn_rd[5:2])

                            4'b1000 : begin     // nanosecs
                                state <= s3;
                            end

                            4'b1001 : begin     // secs
                                state <= s4;
                            end

                            4'b1010 : begin     // timestamp_en
                                rx_timestamp_en_i <= 1'b1;
                                state <= s0;
                            end

                            4'b1011 : begin     // timestamp_disable
                                rx_timestamp_not_en_i <= 1'b1;
                                state <= s0;
                            end

                            default : begin //other addresses
                                state <= s0;
                            end

                        endcase
                    end
                end

                s3 : begin
                    aux_dw <= trn_rd[63:32];
                    nsecs_received <= 1'b1;
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        state <= s0;
                    end
                end

                s4 : begin
                    aux_dw <= trn_rd[63:32];
                    secs_received <= 1'b1;
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
   

endmodule // sys_time

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////