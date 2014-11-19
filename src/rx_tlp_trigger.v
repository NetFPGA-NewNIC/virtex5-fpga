/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_tlp_trigger.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        When enough (good) data is in the internal buffer, a TLP is sent.
*        Ethernet frame boundaries are not taken in consideration.
*
*        TODO: 
*        Fast timeout has to be implemented when sw is ready for it.
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

module rx_tlp_trigger (

    input    clk,
    input    reset,

    input      [2:0]        cfg_max_payload_size,

    // Internal logic
    input      [`BF:0]      commited_wr_addr,
    output reg              trigger_tlp,
    input                   trigger_tlp_ack,
    output reg              change_huge_page,
    input                   change_huge_page_ack,
    output reg              send_numb_qws,
    input                   send_numb_qws_ack,
    output reg [5:0]        qwords_to_send
    );

    // localparam
    localparam s0  = 18'b000000000000000000;
    localparam s1  = 18'b000000000000000001;
    localparam s2  = 18'b000000000000000010;
    localparam s3  = 18'b000000000000000100;
    localparam s4  = 18'b000000000000001000;
    localparam s5  = 18'b000000000000010000;
    localparam s6  = 18'b000000000000100000;
    localparam s7  = 18'b000000000001000000;
    localparam s8  = 18'b000000000010000000;
    localparam s9  = 18'b000000000100000000;
    localparam s10 = 18'b000000001000000000;
    localparam s11 = 18'b000000010000000000;
    localparam s12 = 18'b000000100000000000;
    localparam s13 = 18'b000001000000000000;
    localparam s14 = 18'b000010000000000000;
    localparam s15 = 18'b000100000000000000;
    localparam s16 = 18'b001000000000000000;
    localparam s17 = 18'b010000000000000000;
    localparam s18 = 18'b100000000000000000;

    //-------------------------------------------------------
    // Local timeout-generation
    //-------------------------------------------------------
    reg     [5:0]        free_running;
    reg                  timeout;

    //-------------------------------------------------------
    // Local trigger-logic
    //-------------------------------------------------------
    reg     [17:0]       trigger_fsm;
    reg     [`BF:0]      diff;
    reg     [`BF:0]      diff_reg;
    reg     [`BF:0]      commited_rd_addr;
    reg     [`BF:0]      aux_commited_rd_addr;
    reg                  huge_page_dirty;
    reg     [18:0]       huge_page_qw_offset;
    reg     [18:0]       aux0_huge_page_qw_offset;
    reg     [18:0]       aux1_huge_page_qw_offset;
    reg     [18:0]       aux_ethframe_endaddr;
    reg     [18:0]       aux_256offset;
    reg     [3:0]        qwords_remaining;
    reg     [`BF-4:0]    number_of_tlp_sent;
    reg     [`BF-4:0]    aux0_number_of_tlp_sent;
    reg     [`BF-4:0]    aux1_number_of_tlp_sent;
    reg     [`BF-4:0]    number_of_tlp_to_send;
    reg     [`BF-3:0]    diff_tlp;
    reg                  rx_idle;
    reg                  double_inc;
    reg                  max_tlp_size256;
    reg                  aux_max_tlp_size256;

    ////////////////////////////////////////////////
    // timeout logic
    ////////////////////////////////////////////////
    always @(posedge clk) begin
        if (reset) begin  // reset
            timeout <= 1'b0;
            free_running <= 'b0;
        end
        
        else begin  // not reset

            timeout <= 1'b0;
            free_running <= 'b0;

            if (rx_idle) begin
                free_running <= free_running +1;
                if (free_running == 'h3F) begin
                    timeout <= 1'b1;
                end
            end

        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // trigger-logic
    ////////////////////////////////////////////////
    always @(posedge clk) begin
        
        if (reset) begin  // reset
            trigger_tlp <= 1'b0;
            change_huge_page <= 1'b0;
            send_numb_qws <= 1'b0;

            rx_idle <= 1'b0;
            trigger_fsm <= s18;
        end

        else begin  // not reset

            rx_idle <= 1'b0;

            diff <= commited_wr_addr + (~commited_rd_addr) +1;
            diff_tlp <= number_of_tlp_to_send + (~number_of_tlp_sent) +1;

            aux_max_tlp_size256 <= | cfg_max_payload_size;
            max_tlp_size256 <= aux_max_tlp_size256;
            
            case (trigger_fsm)

                s0 : begin
                    rx_idle <= 1'b1;
                    aux_ethframe_endaddr <= huge_page_qw_offset + diff;
                    diff_reg <= diff;
                    number_of_tlp_to_send <= diff[`BF:4];
                    double_inc <= 1'b0;

                    if (diff >= 'h10) begin
                        trigger_fsm <= s1;
                    end
                    else if ( (huge_page_dirty) && (timeout) ) begin
                        trigger_fsm <= s12;
                    end
                    else if ( (diff) && (timeout) ) begin
                        trigger_fsm <= s17;
                    end
                end

                s1 : begin
                    huge_page_dirty <= 1'b1;
                    number_of_tlp_sent <= 'b0;
                    qwords_to_send <= 'h10;
                    if (aux_ethframe_endaddr[18]) begin       // 2MB
                        trigger_fsm <= s7;
                    end
                    else begin
                        trigger_tlp <= 1'b1;
                        qwords_remaining <= diff_reg[3:0];
                        trigger_fsm <= s2;
                    end
                end

                s2 : begin
                    aux_commited_rd_addr <= commited_rd_addr + qwords_to_send;
                    aux0_number_of_tlp_sent <= number_of_tlp_sent +1;
                    aux1_number_of_tlp_sent <= number_of_tlp_sent +2;
                    aux0_huge_page_qw_offset <= huge_page_qw_offset + qwords_to_send;
                    if (trigger_tlp_ack) begin
                        trigger_tlp <= 1'b0;
                        trigger_fsm <= s3;
                    end
                end

                s3 : begin
                    commited_rd_addr <= aux_commited_rd_addr;
                    number_of_tlp_sent <= double_inc ? aux1_number_of_tlp_sent : aux0_number_of_tlp_sent;
                    huge_page_qw_offset <= aux0_huge_page_qw_offset;
                    aux_256offset <= aux0_huge_page_qw_offset + 'h20;
                    trigger_fsm <= s4;
                end

                s4 : begin
                    //delay: diff_tlp
                    if (max_tlp_size256 && (aux_256offset[9] == huge_page_qw_offset[9])) begin
                        trigger_fsm <= s5;
                    end
                    else begin
                        trigger_fsm <= s6;
                    end
                end

                s5 : begin
                    qwords_to_send <= 'h20;
                    double_inc <= 1'b1;
                    if (diff_tlp > 'h1) begin
                        trigger_tlp <= 1'b1;
                        trigger_fsm <= s2;
                    end
                    else begin
                        trigger_fsm <= s6;
                    end
                end

                s6 : begin
                    double_inc <= 1'b0;
                    qwords_to_send <= 'h10;
                    if (diff_tlp) begin
                        trigger_tlp <= 1'b1;
                        trigger_fsm <= s2;
                    end
                    else begin
                        trigger_fsm <= s0;
                    end
                end

                s7 : begin
                    if (!qwords_remaining) begin
                        change_huge_page <= 1'b1;
                        trigger_fsm <= s8;
                    end
                    else begin
                        qwords_to_send <= {2'b0, qwords_remaining};
                        trigger_tlp <= 1'b1;
                        trigger_fsm <= s9;
                    end
                end

                s8 : begin
                    huge_page_dirty <= 1'b0;
                    huge_page_qw_offset <= 'h10;
                    if (change_huge_page_ack) begin
                        change_huge_page <= 1'b0;
                        trigger_fsm <= s0;
                    end
                end

                s9 : begin
                    aux_commited_rd_addr <= commited_rd_addr + qwords_to_send;
                    if (trigger_tlp_ack) begin
                        trigger_tlp <= 1'b0;
                        change_huge_page <= 1'b1;
                        trigger_fsm <= s10;
                    end
                end

                s10 : begin
                    commited_rd_addr <= aux_commited_rd_addr;
                    huge_page_qw_offset <= 'h10;
                    qwords_remaining <= 'b0;
                    huge_page_dirty <= 1'b0;
                    if (change_huge_page_ack) begin
                        change_huge_page <= 1'b0;
                        trigger_fsm <= s11;
                    end
                end

                s11 : begin
                    // delay: diff
                    trigger_fsm <= s0;
                end

                s12 : begin
                    if (!qwords_remaining) begin
                        send_numb_qws <= 1'b1;
                        trigger_fsm <= s13;
                    end
                    else begin
                        trigger_fsm <= s14;
                    end
                end

                s13 : begin
                    huge_page_dirty <= 1'b0;
                    if (send_numb_qws_ack) begin
                        send_numb_qws <= 1'b0;
                        trigger_fsm <= s0;
                    end
                end

                s14 : begin
                    aux1_huge_page_qw_offset <= huge_page_qw_offset + 'h10;
                    qwords_to_send <= {2'b0, qwords_remaining};
                    trigger_tlp <= 1'b1;
                    if (huge_page_qw_offset == 'h3FFF0) begin
                        trigger_fsm <= s9;
                    end
                    else begin
                        trigger_fsm <= s15;
                    end
                end

                s15 : begin
                    aux_commited_rd_addr <= commited_rd_addr + qwords_to_send;
                    if (trigger_tlp_ack) begin
                        trigger_tlp <= 1'b0;
                        send_numb_qws <= 1'b1;
                        trigger_fsm <= s16;
                    end
                end

                s16 : begin
                    commited_rd_addr <= aux_commited_rd_addr;
                    huge_page_qw_offset <= aux1_huge_page_qw_offset;
                    qwords_remaining <= 'b0;
                    huge_page_dirty <= 1'b0;
                    if (send_numb_qws_ack) begin
                        send_numb_qws <= 1'b0;
                        trigger_fsm <= s11;
                    end
                end

                s17 : begin
                    aux1_huge_page_qw_offset <= huge_page_qw_offset + 'h10;
                    qwords_to_send <= diff_reg;
                    trigger_tlp <= 1'b1;
                    if (huge_page_qw_offset == 'h3FFF0) begin
                        trigger_fsm <= s9;
                    end
                    else begin
                        trigger_fsm <= s15;
                    end
                end

                s18 : begin      // simplify reset logic
                    diff <= 'b0;
                    commited_rd_addr <= 'b0;
                    huge_page_qw_offset <= 'h10;
                    huge_page_dirty <= 1'b0;
                    qwords_remaining <= 'b0;
                    trigger_fsm <= s0;
                end
                
                default : begin
                    trigger_fsm <= s0;
                end

            endcase

        end     // not reset
    end  //always

endmodule // rx_tlp_trigger

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////