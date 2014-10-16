/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_wr_pkt_to_bram.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives completion TLPs from host with data comprising ethernet frames.
*        This module don't know about ethernet frames or its boundaries.
*        It places the data in the internal tx buffer when it arrives from the
*        PCIe endpoint. It reads more data when it has sufficient space in the
*        internal buffer.
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

`define CPL_W_DATA_FMT_TYPE 7'b10_01010
`define SC 3'b000


module tx_wr_pkt_to_bram (

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

    input       [63:0]      huge_page_addr_1,
    input       [63:0]      huge_page_addr_2,
    input       [31:0]      huge_page_qwords_1,
    input       [31:0]      huge_page_qwords_2,
    input                   huge_page_status_1,
    input                   huge_page_status_2,
    output reg              huge_page_free_1,
    output reg              huge_page_free_2,
    input                   interrupts_enabled,

    output reg   [63:0]     huge_page_addr_read_from,
    output reg              read_chunk,
    input        [3:0]      tlp_tag,
    output       [8:0]      qwords_to_rd,
    input                   read_chunk_ack,
    output reg              send_rd_completed,
    input                   send_rd_completed_ack,

    output reg              notify,
    output reg   [63:0]     notification_message,
    input                   notify_ack,

    output reg              send_interrupt,
    input                   send_interrupt_ack,

    // Internal memory driver
    output reg  [8:0]       wr_addr,
    output reg  [63:0]      wr_data,
    output reg              wr_en,

    input       [9:0]       commited_rd_addr,
    output reg  [9:0]       commited_wr_addr
    );

    // localparam
    localparam s0  = 16'b0000000000000000;
    localparam s1  = 16'b0000000000000001;
    localparam s2  = 16'b0000000000000010;
    localparam s3  = 16'b0000000000000100;
    localparam s4  = 16'b0000000000001000;
    localparam s5  = 16'b0000000000010000;
    localparam s6  = 16'b0000000000100000;
    localparam s7  = 16'b0000000001000000;
    localparam s8  = 16'b0000000010000000;
    localparam s9  = 16'b0000000100000000;
    localparam s10 = 16'b0000001000000000;
    localparam s11 = 16'b0000010000000000;
    localparam s12 = 16'b0000100000000000;
    localparam s13 = 16'b0001000000000000;
    localparam s14 = 16'b0010000000000000;
    localparam s15 = 16'b0100000000000000;
    localparam s16 = 16'b1000000000000000;

    localparam hp1 = 2'b01;
    localparam hp2 = 2'b10;

    //-------------------------------------------------------
    // Local current_huge_page_addr
    //-------------------------------------------------------
    reg     [63:0]  current_huge_page_addr;
    reg     [31:0]  current_huge_page_qwords;
    reg     [14:0]  give_huge_page_fsm;
    reg     [14:0]  free_huge_page_fsm;
    reg             huge_page_available;
    reg             reading_huge_page_1;
    reg             reading_huge_page_2;

    //-------------------------------------------------------
    // Local trigger_rd_tlp
    //-------------------------------------------------------   
    reg             return_huge_page_to_host;
    reg     [15:0]  trigger_rd_tlp_fsm;
    /*(* KEEP = "TRUE" *)*/reg     [9:0] diff;
    reg     [9:0]   next_wr_addr;
    reg     [9:0]   look_ahead_next_wr_addr;
    reg     [31:0]  huge_page_qwords_counter;
    reg     [31:0]  look_ahead_huge_page_qwords_counter;
    reg     [63:0]  look_ahead_huge_page_addr_read_from;
    reg     [31:0]  huge_page_remaining_qwords;
    reg     [1:0]   tag_to_hp[0:3];
    reg     [3:0]   tlp_tag_sent;
    reg     [9:0]   aux_diff_horror;
    reg     [9:0]   current_page_qwords;
    reg     [9:0]   page_qwords_counter;
    reg     [9:0]   look_ahead_page_qwords_counter;
    reg     [9:0]   page_remaining_qwords;
    reg     [9:0]   aux_value;
    reg     [9:0]   init_aux;
    reg     [9:0]   next_aux_value;
    reg     [9:0]   aux_diff;
    reg     [22:0]  current_numb_of_pages;
    reg     [22:0]  consumed_pages;
    reg     [22:0]  page_count;
    reg             remainder_page;
    reg     [9:0]   qwords_to_rd_i;
    reg     [9:0]   request_addr_bram;
    reg     [9:0]   request_size[0:3];
    reg     [2:0]   sent_requests;
    reg     [2:0]   look_ahead_sent_requests;
    reg     [2:0]   outstanding_requests;
    
    //-------------------------------------------------------
    // Local trigger_interrupts
    //-------------------------------------------------------
    reg     [14:0]  trigger_interrupts_fsm;

    //-------------------------------------------------------
    // Local huge_page_1_notifications
    //-------------------------------------------------------
    reg     [14:0]  huge_page_1_notifications_fsm;
    reg     [63:0]  address_to_notify_huge_page_1;
    reg     [31:0]  qwords_to_rd_huge_page_1;
    reg     [32:0]  dwords_received_huge_page_1;
    reg     [32:0]  next_dwords_received_huge_page_1;
    reg             send_notification_huge_page_1;
    reg             send_notification_huge_page_1_ack;
    reg             waiting_data_huge_page_1;
    reg     [3:0]   this_tlp_tag_hp1_copy;

    //-------------------------------------------------------
    // Local huge_page_2_notifications
    //-------------------------------------------------------
    reg     [14:0]  huge_page_2_notifications_fsm;
    reg     [63:0]  address_to_notify_huge_page_2;
    reg     [31:0]  qwords_to_rd_huge_page_2;
    reg     [32:0]  dwords_received_huge_page_2;
    reg     [32:0]  next_dwords_received_huge_page_2;
    reg             send_notification_huge_page_2;
    reg             send_notification_huge_page_2_ack;
    reg             waiting_data_huge_page_2;
    reg     [3:0]   this_tlp_tag_hp2_copy;

    //-------------------------------------------------------
    // Local huge_page_1_notifications & huge_page_2_notifications mixer
    //-------------------------------------------------------
    reg     [14:0]  notification_mixer_fsm;

    //-------------------------------------------------------
    // Local completion_tlp & write to bram (wr_to_bram_fsm)
    //-------------------------------------------------------
    reg     [14:0]  wr_to_bram_fsm;
    reg     [14:0]  commit_wr_addr_fsm;
    reg     [8:0]   qwords_on_tlp;
    reg     [9:0]   dwords_on_tlp;
    reg             completion_received;
    reg     [31:0]  dw_aux;
    reg     [9:0]   look_ahead_wr_addr;
    reg     [3:0]   this_tlp_tag;
    reg     [9:0]   tlp_addr[0:3];
    reg     [9:0]   received_size[0:3];
    reg     [3:0]   target_tlp;
    reg     [3:0]   next_target_tlp;
    reg     [9:0]   look_ahead_received_size;
    reg     [9:0]   look_ahead_tlp_addr;
    reg     [2:0]   completed_requests;
    reg     [2:0]   look_ahead_completed_requests;
    reg             this_tlp_odd;
    reg     [3:0]   saved_dw_en;
    reg     [31:0]  saved_dw[0:3];
    reg     [9:0]   look_ahead_wr_addr_p1;
    reg     [3:0]   data_ready;

    //-------------------------------------------------------
    // Local health_mon
    //-------------------------------------------------------
    reg     [14:0]  health_mon_fsm;
    reg     [9:0]   diff_mon_reg;
    (* KEEP = "TRUE" *)reg     [31:0]   counter_mon;

    ////////////////////////////////////////////////
    // health_mon
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            counter_mon <= 'b0;
            health_mon_fsm <= s0;
        end
        
        else begin  // not reset

            case (health_mon_fsm)

                s0 : begin
                    diff_mon_reg <= diff;
                    counter_mon <= 'b0;
                    if (diff) begin
                        health_mon_fsm <= s1;
                    end
                end

                s1 : begin
                    counter_mon <= counter_mon + 1;
                    if (diff != diff_mon_reg) begin
                        diff_mon_reg <= diff;
                        counter_mon <= 'b0;
                    end
                    if (!diff) begin
                        health_mon_fsm <= s0;
                    end
                end

                default : begin
                    health_mon_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // current_huge_page_addr
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            huge_page_free_1 <= 1'b0;
            huge_page_free_2 <= 1'b0;
            reading_huge_page_1 <= 1'b0;
            reading_huge_page_2 <= 1'b0;
            huge_page_available <= 1'b0;
            give_huge_page_fsm <= s0;
            free_huge_page_fsm <= s0;
        end

        else begin  // not reset

            case (free_huge_page_fsm)
                s0 : begin
                    if (return_huge_page_to_host) begin
                        huge_page_free_1 <= 1'b1;
                        free_huge_page_fsm <= s1;
                    end
                end
                s1 : begin
                    huge_page_free_1 <= 1'b0;
                    free_huge_page_fsm <= s2;
                end
                s2 : begin
                    if (return_huge_page_to_host) begin
                        huge_page_free_2 <= 1'b1;
                        free_huge_page_fsm <= s3;
                    end
                end
                s3 : begin
                    huge_page_free_2 <= 1'b0;
                    free_huge_page_fsm <= s0;
                end
            endcase

            case (give_huge_page_fsm)
                s0 : begin
                    if (huge_page_status_1 && !waiting_data_huge_page_1) begin
                        huge_page_available <= 1'b1;
                        reading_huge_page_1 <= 1'b1;
                        current_huge_page_addr <= huge_page_addr_1;
                        current_huge_page_qwords <= huge_page_qwords_1;
                        give_huge_page_fsm <= s1;
                    end
                end

                s1 : begin
                    if (return_huge_page_to_host) begin
                        reading_huge_page_1 <= 1'b0;
                        huge_page_available <= 1'b0;
                        give_huge_page_fsm <= s2;
                    end
                end

                s2 : begin
                    if (huge_page_status_2 && !waiting_data_huge_page_2) begin
                        huge_page_available <= 1'b1;
                        reading_huge_page_2 <= 1'b1;
                        current_huge_page_addr <= huge_page_addr_2;
                        current_huge_page_qwords <= huge_page_qwords_2;
                        give_huge_page_fsm <= s3;
                    end
                end

                s3 : begin
                    if (return_huge_page_to_host) begin
                        reading_huge_page_2 <= 1'b0;
                        huge_page_available <= 1'b0;
                        give_huge_page_fsm <= s0;
                    end
                end
            endcase

        end     // not reset
    end  //always

    assign qwords_to_rd = qwords_to_rd_i;

    ////////////////////////////////////////////////
    // trigger_rd_tlp
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            return_huge_page_to_host <= 1'b0;
            read_chunk <= 1'b0;
            send_rd_completed <= 1'b0;
            diff <= 'b0;
            next_wr_addr <= 'b0;
            sent_requests <= 'b0;
            trigger_rd_tlp_fsm <= s0;
        end
        
        else begin  // not reset

            return_huge_page_to_host <= 1'b0;
            diff <= next_wr_addr + (~commited_rd_addr) + 1;
            huge_page_remaining_qwords <= current_huge_page_qwords + (~huge_page_qwords_counter) + 1;
            outstanding_requests <= sent_requests + (~completed_requests) + 1;

            aux_diff_horror <= diff + current_huge_page_qwords[9:0];

            page_count <= current_numb_of_pages + (~consumed_pages) + 1;

            page_remaining_qwords <= current_page_qwords + (~page_qwords_counter) + 1;

            aux_diff <= diff + aux_value;
            next_aux_value <= aux_value + (~('h10)) + 1;

            case (trigger_rd_tlp_fsm)

                s0 : begin
                    current_numb_of_pages <= current_huge_page_qwords[31:9];
                    remainder_page <= | (current_huge_page_qwords[8:0]);
                    consumed_pages <= 'b0;
                    page_qwords_counter <= 'b0;

                    huge_page_addr_read_from <= current_huge_page_addr;
                    huge_page_qwords_counter <= 'b0;
                    if (huge_page_available) begin
                        if (current_huge_page_qwords > 'h200) begin
                            trigger_rd_tlp_fsm <= s1;
                        end
                        else begin
                            trigger_rd_tlp_fsm <= s2;
                        end
                    end
                end

                s1 : begin  // Horror vacui
                    current_page_qwords <= 'h200;
                    qwords_to_rd_i <= 'h200;
                    look_ahead_sent_requests <= sent_requests + 1;
                    if (!diff) begin
                        read_chunk <= 1'b1;
                        trigger_rd_tlp_fsm <= s9;
                    end
                    else begin      // take it easy, buffer not empty
                        trigger_rd_tlp_fsm <= s3;     
                    end
                end

                s2 : begin  // Horror vacui
                    current_page_qwords <= current_huge_page_qwords[9:0];
                    qwords_to_rd_i <= current_huge_page_qwords[9:0];
                    look_ahead_sent_requests <= sent_requests + 1;
                    if (aux_diff_horror <= 'h200) begin
                        read_chunk <= 1'b1;
                        trigger_rd_tlp_fsm <= s9;
                    end
                    else begin      // take it easy, buffer not empty
                        trigger_rd_tlp_fsm <= s3;     
                    end
                end

                s3 : begin
                    page_qwords_counter <= 'b0;
                    aux_value <= 'h1F0;
                    init_aux <= 'h1F0;
                    if (page_count) begin
                        current_page_qwords <= 'h200;
                        trigger_rd_tlp_fsm <= s7;
                    end
                    else if (remainder_page) begin
                        current_page_qwords <= current_huge_page_qwords[8:0];
                        trigger_rd_tlp_fsm <= s4;
                    end
                end

                s4 : begin
                    // delay: page_remaining_qwords
                    trigger_rd_tlp_fsm <= s5;
                end

                s5 : begin
                    aux_value <= page_remaining_qwords;
                    init_aux <= page_remaining_qwords;
                    trigger_rd_tlp_fsm <= s7;
                end

                //s6 : begin
                    // delay: aux_diff
                    //trigger_rd_tlp_fsm <= s7;
                //end

                s7 : begin
                    // delay: aux_diff
                    if ((aux_value[8:0]) && (!aux_value[9])) begin
                        trigger_rd_tlp_fsm <= s8;
                    end
                    else begin
                        aux_value <= init_aux;
                    end
                end

                s8 : begin
                    look_ahead_sent_requests <= sent_requests + 1;
                    aux_value <= next_aux_value;
                    if (!aux_diff[9]) begin
                        qwords_to_rd_i <= aux_value;
                        read_chunk <= 1'b1;
                        trigger_rd_tlp_fsm <= s9;
                    end
                    else begin
                        trigger_rd_tlp_fsm <= s7;
                    end
                end

                s9 : begin
                    look_ahead_next_wr_addr <= next_wr_addr + qwords_to_rd_i;
                    look_ahead_huge_page_addr_read_from <= huge_page_addr_read_from + {qwords_to_rd_i, 3'b0};
                    look_ahead_huge_page_qwords_counter <= huge_page_qwords_counter + qwords_to_rd_i;
                    look_ahead_page_qwords_counter <= page_qwords_counter + qwords_to_rd_i;
                    sent_requests <= look_ahead_sent_requests;

                    request_addr_bram <= next_wr_addr;
                    request_size[tlp_tag] <= qwords_to_rd_i;
                    tlp_tag_sent <= tlp_tag;

                    if (read_chunk_ack) begin
                        read_chunk <= 1'b0;
                        trigger_rd_tlp_fsm <= s10;
                    end
                end

                s10 : begin
                    next_wr_addr <= look_ahead_next_wr_addr;
                    huge_page_addr_read_from <= look_ahead_huge_page_addr_read_from;
                    huge_page_qwords_counter <= look_ahead_huge_page_qwords_counter;
                    page_qwords_counter <= look_ahead_page_qwords_counter;

                    if (reading_huge_page_1) begin
                        tag_to_hp[tlp_tag_sent] <= hp1;
                    end
                    else begin
                        tag_to_hp[tlp_tag_sent] <= hp2;
                    end
                    trigger_rd_tlp_fsm <= s11;
                end

                s11 : begin
                    // delay: huge_page_remaining_qwords
                    if (outstanding_requests < 'h4) begin
                        trigger_rd_tlp_fsm <= s12;
                    end
                end

                s12 : begin
                    if (huge_page_remaining_qwords) begin
                        trigger_rd_tlp_fsm <= s13;
                    end
                    else begin
                        return_huge_page_to_host <= 1'b1;
                        send_rd_completed <= 1'b1;
                        trigger_rd_tlp_fsm <= s15;
                    end
                end

                s13 : begin
                    aux_value <= page_remaining_qwords;
                    init_aux <= page_remaining_qwords;
                    if (page_remaining_qwords) begin
                        trigger_rd_tlp_fsm <= s7;
                    end
                    else begin
                        consumed_pages <= consumed_pages + 1;
                        trigger_rd_tlp_fsm <= s14;
                    end
                end

                s14 : begin
                    // delay: page_count
                    trigger_rd_tlp_fsm <= s3;
                end

                s15 : begin
                    if (send_rd_completed_ack) begin
                        send_rd_completed <= 1'b0;
                        trigger_rd_tlp_fsm <= s16;
                    end
                end

                s16 : begin
                    if (outstanding_requests < 'h4) begin
                        trigger_rd_tlp_fsm <= s0;
                    end
                end

                default : begin
                    trigger_rd_tlp_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // trigger_interrupts
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            send_interrupt <= 1'b0;
            trigger_interrupts_fsm <= s0;
        end
        
        else begin  // not reset

            case (trigger_interrupts_fsm)

                s0 : begin
                    if ( waiting_data_huge_page_1 || waiting_data_huge_page_2 ) begin
                        trigger_interrupts_fsm <= s1;
                    end
                end

                s1 : begin
                    if (!waiting_data_huge_page_1 && !waiting_data_huge_page_2) begin
                        trigger_interrupts_fsm <= s2;
                    end
                end

                s2 : begin                                     // added delay to send the interrupt after the notification
                    trigger_interrupts_fsm <= s3;
                    if (!interrupts_enabled) begin
                        trigger_interrupts_fsm <= s0;
                    end
                end

                s3 : begin
                    send_interrupt <= 1'b1;
                    trigger_interrupts_fsm <= s4;
                end

                s4 : begin
                    if (send_interrupt_ack) begin
                        send_interrupt <= 1'b0;
                        trigger_interrupts_fsm <= s0;
                    end
                end

                default : begin
                    trigger_interrupts_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // huge_page_1_notifications
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            waiting_data_huge_page_1 <= 1'b0;
            send_notification_huge_page_1 <= 1'b0;
            huge_page_1_notifications_fsm <= s0;
        end
        
        else begin  // not reset

            case (huge_page_1_notifications_fsm)

                s0 : begin
                    address_to_notify_huge_page_1 <= huge_page_addr_1;
                    qwords_to_rd_huge_page_1 <= huge_page_qwords_1;
                    dwords_received_huge_page_1 <= 'b0;
                    if (reading_huge_page_1) begin
                        huge_page_1_notifications_fsm <= s1;
                    end
                end

                s1 : begin
                    waiting_data_huge_page_1 <= 1'b1;
                    
                    next_dwords_received_huge_page_1 <= dwords_received_huge_page_1 + dwords_on_tlp;
                    this_tlp_tag_hp1_copy <= this_tlp_tag;
                    if (completion_received) begin
                        huge_page_1_notifications_fsm <= s2;
                    end
                end

                s2 : begin
                    if (tag_to_hp[this_tlp_tag_hp1_copy] == hp1) begin
                        dwords_received_huge_page_1 <= next_dwords_received_huge_page_1;
                        huge_page_1_notifications_fsm <= s3;
                    end
                    else begin
                        huge_page_1_notifications_fsm <= s1;
                    end
                end

                s3 : begin
                    if ({qwords_to_rd_huge_page_1, 1'b0} == dwords_received_huge_page_1) begin
                        send_notification_huge_page_1 <= 1'b1;
                        huge_page_1_notifications_fsm <= s4;
                    end
                    else begin
                        huge_page_1_notifications_fsm <= s1;
                    end
                end

                s4 : begin
                    if (send_notification_huge_page_1_ack) begin
                        waiting_data_huge_page_1 <= 1'b0;
                        send_notification_huge_page_1 <= 1'b0;
                        huge_page_1_notifications_fsm <= s0;
                    end
                end

                default : begin
                    huge_page_1_notifications_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // huge_page_2_notifications
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            waiting_data_huge_page_2 <= 1'b0;
            send_notification_huge_page_2 <= 1'b0;
            huge_page_2_notifications_fsm <= s0;
        end
        
        else begin  // not reset

            case (huge_page_2_notifications_fsm)

                s0 : begin
                    address_to_notify_huge_page_2 <= huge_page_addr_2;
                    qwords_to_rd_huge_page_2 <= huge_page_qwords_2;
                    dwords_received_huge_page_2 <= 'b0;
                    if (reading_huge_page_2) begin
                        huge_page_2_notifications_fsm <= s1;
                    end
                end

                s1 : begin
                    waiting_data_huge_page_2 <= 1'b1;
                    
                    next_dwords_received_huge_page_2 <= dwords_received_huge_page_2 + dwords_on_tlp;
                    this_tlp_tag_hp2_copy <= this_tlp_tag;
                    if (completion_received) begin
                        huge_page_2_notifications_fsm <= s2;
                    end
                end

                s2 : begin
                    if (tag_to_hp[this_tlp_tag_hp2_copy] == hp2) begin
                        dwords_received_huge_page_2 <= next_dwords_received_huge_page_2;
                        huge_page_2_notifications_fsm <= s3;
                    end
                    else begin
                        huge_page_2_notifications_fsm <= s1;
                    end
                end

                s3 : begin
                    if ({qwords_to_rd_huge_page_2, 1'b0} == dwords_received_huge_page_2) begin
                        send_notification_huge_page_2 <= 1'b1;
                        huge_page_2_notifications_fsm <= s4;
                    end
                    else begin
                        huge_page_2_notifications_fsm <= s1;
                    end
                end

                s4 : begin
                    if (send_notification_huge_page_2_ack) begin
                        waiting_data_huge_page_2 <= 1'b0;
                        send_notification_huge_page_2 <= 1'b0;
                        huge_page_2_notifications_fsm <= s0;
                    end
                end

                default : begin
                    huge_page_2_notifications_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // huge_page_1_notifications & huge_page_2_notifications mixer
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            send_notification_huge_page_1_ack <= 1'b0;
            send_notification_huge_page_2_ack <= 1'b0;
            notify <= 1'b0;
            notification_mixer_fsm <= s0;
        end
        
        else begin  // not reset

            send_notification_huge_page_1_ack <= 1'b0;
            send_notification_huge_page_2_ack <= 1'b0;

            case (notification_mixer_fsm)

                s0 : begin
                    notification_message <= address_to_notify_huge_page_1;
                    if (send_notification_huge_page_1) begin
                        send_notification_huge_page_1_ack <= 1'b1;
                        notify <= 1'b1;
                        notification_mixer_fsm <= s1;
                    end
                end

                s1 : begin
                    if (notify_ack) begin
                        notify <= 1'b0;
                        notification_mixer_fsm <= s2;
                    end
                end

                s2 : begin
                    notification_message <= address_to_notify_huge_page_2;
                    if (send_notification_huge_page_2) begin
                        send_notification_huge_page_2_ack <= 1'b1;
                        notify <= 1'b1;
                        notification_mixer_fsm <= s3;
                    end
                end

                s3 : begin
                    if (notify_ack) begin
                        notify <= 1'b0;
                        notification_mixer_fsm <= s0;
                    end
                end

                default : begin
                    notification_mixer_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always


    ////////////////////////////////////////////////
    // completion_tlp & write to bram (wr_to_bram_fsm)
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            wr_addr <= 'b0;
            look_ahead_wr_addr <= 'b0;
            wr_en <= 1'b1;
            completion_received <= 1'b0;
            commited_wr_addr <= 'b0;
            this_tlp_tag <= 'b0;
            target_tlp <= 'b0;
            completed_requests <= 'b0;
            data_ready <= 'b0;
            wr_to_bram_fsm <= s0;
            commit_wr_addr_fsm <= s0;
        end
        
        else begin  // not reset

            wr_en <= 1'b1;
            completion_received <= 1'b0;

            if (read_chunk && read_chunk_ack) begin
                tlp_addr[tlp_tag] <= request_addr_bram;
                received_size[tlp_tag] <= 'b0;
                saved_dw_en[tlp_tag] <= 1'b0;
            end
            
            next_target_tlp <= target_tlp +1;
            look_ahead_completed_requests <= completed_requests +1;
            case (commit_wr_addr_fsm)                           // provided that tlps of one single request are received in order

                s0 : begin
                    if (data_ready[target_tlp]) begin
                        commited_wr_addr <= tlp_addr[target_tlp];
                    end
                    if ((received_size[target_tlp] == request_size[target_tlp]) && data_ready[target_tlp]) begin
                        commit_wr_addr_fsm <= s1;
                    end
                end

                s1 : begin
                    target_tlp <= next_target_tlp;
                    completed_requests <= look_ahead_completed_requests;
                    data_ready[target_tlp] <= 1'b0;
                    commit_wr_addr_fsm <= s0;
                end

                default : begin //other TLPs
                    commit_wr_addr_fsm <= s0;
                end

            endcase

            case (wr_to_bram_fsm)

                s0 : begin
                    qwords_on_tlp <= trn_rd[41:33];
                    dwords_on_tlp <= trn_rd[41:32];
                    this_tlp_odd <= trn_rd[32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n)) begin
                        if ( (trn_rd[62:56] == `CPL_W_DATA_FMT_TYPE) && (trn_rd[15:13] == `SC) ) begin
                            wr_to_bram_fsm <= s1;
                        end
                    end
                end

                s1 : begin
                    look_ahead_received_size <= received_size[trn_rd[43:40]] + qwords_on_tlp;
                    look_ahead_tlp_addr <= tlp_addr[trn_rd[43:40]] + qwords_on_tlp;
                    this_tlp_tag <= trn_rd[43:40];

                    data_ready[trn_rd[43:40]] <= 1'b0;

                    look_ahead_wr_addr <= tlp_addr[trn_rd[43:40]];
                    look_ahead_wr_addr_p1 <= tlp_addr[trn_rd[43:40]] + 1;

                    wr_addr <= tlp_addr[trn_rd[43:40]];
                    wr_data <= {trn_rd[7:0], trn_rd[15:8], trn_rd[23:16], trn_rd[31:24], saved_dw[trn_rd[43:40]]};

                    dw_aux <= trn_rd[31:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case ({saved_dw_en[trn_rd[43:40]], this_tlp_odd})                    // my deco
                            2'b00 : begin   // P -> P
                                wr_to_bram_fsm <= s2;
                            end
                            2'b01 : begin   // P -> I
                                wr_to_bram_fsm <= s3;
                            end
                            2'b10 : begin   // I -> P
                                wr_to_bram_fsm <= s4;
                            end
                            2'b11 : begin   // I -> I
                                wr_to_bram_fsm <= s5;
                            end
                        endcase
                    end
                end

                s2 : begin   // P -> P
                    tlp_addr[this_tlp_tag] <= look_ahead_tlp_addr;
                    received_size[this_tlp_tag] <= look_ahead_received_size;
                    saved_dw_en[this_tlp_tag] <= 1'b0;

                    wr_addr <= look_ahead_wr_addr;
                    wr_data <= {trn_rd[39:32], trn_rd[47:40], trn_rd[55:48], trn_rd[63:56], dw_aux[7:0], dw_aux[15:8], dw_aux[23:16], dw_aux[31:24]};
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        look_ahead_wr_addr <= look_ahead_wr_addr +1;
                        dw_aux <= trn_rd[31:0];
                        if (!trn_reof_n) begin
                            completion_received <= 1'b1;
                            data_ready[this_tlp_tag] <= 1'b1;
                            wr_to_bram_fsm <= s0;
                        end
                    end
                end

                s3 : begin   // P -> I
                    tlp_addr[this_tlp_tag] <= look_ahead_tlp_addr;
                    received_size[this_tlp_tag] <= look_ahead_received_size;

                    saved_dw[this_tlp_tag] <= {trn_rd[7:0], trn_rd[15:8], trn_rd[23:16], trn_rd[31:24]};
                    saved_dw_en[this_tlp_tag] <= 1'b1;

                    wr_addr <= look_ahead_wr_addr;
                    wr_data <= {trn_rd[39:32], trn_rd[47:40], trn_rd[55:48], trn_rd[63:56], dw_aux[7:0], dw_aux[15:8], dw_aux[23:16], dw_aux[31:24]};
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        look_ahead_wr_addr <= look_ahead_wr_addr +1;
                        dw_aux <= trn_rd[31:0];
                        if (!trn_reof_n) begin
                            completion_received <= 1'b1;
                            data_ready[this_tlp_tag] <= 1'b1;
                            wr_to_bram_fsm <= s0;
                        end
                    end
                end

                s4 : begin   // I -> P
                    tlp_addr[this_tlp_tag] <= look_ahead_tlp_addr;
                    received_size[this_tlp_tag] <= look_ahead_received_size;

                    saved_dw[this_tlp_tag] <= {trn_rd[39:32], trn_rd[47:40], trn_rd[55:48], trn_rd[63:56]};
                    saved_dw_en[this_tlp_tag] <= 1'b1;

                    wr_addr <= look_ahead_wr_addr_p1;
                    wr_data <= {trn_rd[7:0], trn_rd[15:8], trn_rd[23:16], trn_rd[31:24], trn_rd[39:32], trn_rd[47:40], trn_rd[55:48], trn_rd[63:56]};
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        look_ahead_wr_addr_p1 <= look_ahead_wr_addr_p1 +1;
                        if (!trn_reof_n) begin
                            completion_received <= 1'b1;
                            data_ready[this_tlp_tag] <= 1'b1;
                            wr_to_bram_fsm <= s0;
                        end
                    end
                end

                s5 : begin   // I -> I
                    tlp_addr[this_tlp_tag] <= look_ahead_tlp_addr + 1;
                    received_size[this_tlp_tag] <= look_ahead_received_size + 1;
                    saved_dw_en[this_tlp_tag] <= 1'b0;

                    wr_addr <= look_ahead_wr_addr_p1;
                    wr_data <= {trn_rd[7:0], trn_rd[15:8], trn_rd[23:16], trn_rd[31:24], trn_rd[39:32], trn_rd[47:40], trn_rd[55:48], trn_rd[63:56]};
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        look_ahead_wr_addr_p1 <= look_ahead_wr_addr_p1 +1;
                        if (!trn_reof_n) begin
                            completion_received <= 1'b1;
                            data_ready[this_tlp_tag] <= 1'b1;
                            wr_to_bram_fsm <= s0;
                        end
                    end
                end

                default : begin //other TLPs
                    wr_to_bram_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

endmodule // tx_wr_pkt_to_bram

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////