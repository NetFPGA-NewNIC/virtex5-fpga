/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_wr_pkt_to_hugepages.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Sends TLP when a trigger is received. TLPs with maximum payload size
*        are normally sent. Ethernet frames boundaries are not taken in
*        consideration.
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

`define TX_MEM_WR64_FMT_TYPE 7'b11_00000

module rx_wr_pkt_to_hugepages (

    input                  trn_clk,
    input                  trn_lnk_up_n,

    // Rx Local-Link  //
    output reg  [63:0]     trn_td,
    output reg  [7:0]      trn_trem_n,
    output reg             trn_tsof_n,
    output reg             trn_teof_n,
    output reg             trn_tsrc_rdy_n,
    input                  trn_tdst_rdy_n,
    input       [3:0]      trn_tbuf_av,
    input       [15:0]     cfg_completer_id,
    output reg             cfg_interrupt_n,
    input                  cfg_interrupt_rdy_n,

    // Internal logic  //
    input       [63:0]     huge_page_addr_1,
    input       [63:0]     huge_page_addr_2,
    input                  huge_page_status_1,
    input                  huge_page_status_2,
    output reg             huge_page_free_1,
    output reg             huge_page_free_2,
    input                  interrupts_enabled,

    input                  trigger_tlp,
    output reg             trigger_tlp_ack,
    input                  change_huge_page,
    output reg             change_huge_page_ack,
    input                  send_last_tlp,
    input       [4:0]      qwords_to_send,

    output reg  [`BF:0]    commited_rd_address,
    output reg  [`BF:0]    rd_addr,
    input       [63:0]     rd_data,

    // Arbitrations handshake  //
    input                  my_turn,
    output reg             driving_interface
    );

    wire            reset_n;
    
    // localparam
    localparam s0  = 15'b000000000000000;
    localparam s1  = 15'b000000000000001;
    localparam s2  = 15'b000000000000010;
    localparam s3  = 15'b000000000000100;
    localparam s4  = 15'b000000000001000;
    localparam s5  = 15'b000000000010000;
    localparam s6  = 15'b000000000100000;
    localparam s7  = 15'b000000001000000;
    localparam s8  = 15'b000000010000000;
    localparam s9  = 15'b000000100000000;
    localparam s10 = 15'b000001000000000;
    localparam s11 = 15'b000010000000000;
    localparam s12 = 15'b000100000000000;
    localparam s13 = 15'b001000000000000;
    localparam s14 = 15'b010000000000000;
    localparam s15 = 15'b100000000000000;

    //-------------------------------------------------------
    // Local current_huge_page_addr
    //-------------------------------------------------------
    reg     [63:0]      current_huge_page_addr;
    reg     [14:0]      give_huge_page_fsm;
    reg     [14:0]      free_huge_page_fsm;
    reg                 huge_page_available;

    //-------------------------------------------------------
    // Local send_tlps_machine
    //-------------------------------------------------------   
    reg     [14:0]      send_fsm;
    reg                 return_huge_page_to_host;
    reg     [8:0]       tlp_qword_counter;
    reg     [31:0]      tlp_number;
    reg     [31:0]      look_ahead_tlp_number;
    reg     [8:0]       qwords_in_tlp;
    reg     [63:0]      host_mem_addr;
    reg     [63:0]      look_ahead_host_mem_addr;
    reg     [31:0]      huge_page_qword_counter;
    reg     [31:0]      look_ahead_huge_page_qword_counter;
    reg                 endpoint_not_ready;
    reg                 remember_to_change_huge_page;
    reg     [`BF:0]     rd_addr_prev1;
    reg     [`BF:0]     rd_addr_prev2;
    
    assign reset_n = ~trn_lnk_up_n;

    ////////////////////////////////////////////////
    // current_huge_page_addr
    ////////////////////////////////////////////////
    always @( posedge trn_clk or negedge reset_n ) begin

        if (!reset_n ) begin  // reset
            huge_page_free_1 <= 1'b0;
            huge_page_free_2 <= 1'b0;
            huge_page_available <= 1'b0;
            current_huge_page_addr <= 64'b0;
            give_huge_page_fsm <= s0;
            free_huge_page_fsm <= s0;
        end

        else begin  // not reset

            // this state machine listens to return_huge_page_to_host from the
            // core state machine that communicates with host via PCIe and 
            // based on this signal change huge_page_free_*, which interact with 
            // rx_huge_pages_addr module.
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

            // this state machine sets huge_page_available and
            // current_huge_page_addr appropriately, which are used by the
            // core state machine.
            case (give_huge_page_fsm)
                s0 : begin
                    if (huge_page_status_1) begin
                        huge_page_available <= 1'b1;
                        current_huge_page_addr <= huge_page_addr_1;
                        give_huge_page_fsm <= s1;
                    end
                end

                s1 : begin
                    if (return_huge_page_to_host) begin
                        huge_page_available <= 1'b0;
                        give_huge_page_fsm <= s2;
                    end
                end

                s2 : begin
                    if (huge_page_status_2) begin
                        huge_page_available <= 1'b1;
                        current_huge_page_addr <= huge_page_addr_2;
                        give_huge_page_fsm <= s3;
                    end
                end

                s3 : begin
                    if (return_huge_page_to_host) begin
                        huge_page_available <= 1'b0;
                        give_huge_page_fsm <= s0;
                    end
                end
            endcase

        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // write request TLP generation to huge_page
    ////////////////////////////////////////////////
    always @( posedge trn_clk or negedge reset_n ) begin

        if (!reset_n ) begin  // reset
            trn_td <= 'b0;
            trn_trem_n <= 'hFF;
            trn_tsof_n <= 1'b1;
            trn_teof_n <= 1'b1;
            trn_tsrc_rdy_n <= 1'b1;
            cfg_interrupt_n <= 1'b1;

            endpoint_not_ready <= 1'b0;
            remember_to_change_huge_page <= 1'b0;
            return_huge_page_to_host <= 1'b0;
            driving_interface <= 1'b0;

            trigger_tlp_ack <= 1'b0;
            change_huge_page_ack <= 1'b0;

            commited_rd_address <= 'b0;
            rd_addr <= 'b0;

            tlp_qword_counter <= 'b0;
            tlp_number <= 'b0;

            send_fsm <= s0;
        end
        
        else begin  // not reset

            rd_addr_prev1 <= rd_addr;
            rd_addr_prev2 <= rd_addr_prev1;

            case (send_fsm)

                s0 : begin
                    // [Initialization] s0 -> s1 if huge_page_available
                    driving_interface <= 1'b0;
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;

                    // Huge page layout:
                    // One important thing is each packet should be stored
                    // with 128B alignment, which ensures no TLP crosses 4KB boundary.
                    //
                    //      DWORDS
                    // +---------------+ <-- 0
                    // |   nr_qwords   |
                    // |---------------|
                    // |               | 
                    // |    reserved   | 
                    // |               | 
                    // |---------------| <-- 32DW (128B) <- host_mem_addr
                    // |   packet len  | 
                    // |---------------|
                    // |               | 
                    // |  packet data  | 
                    // |               | 
                    // |---------------|
                    // |   packet len  | 
                    // |---------------|
                    // |      ...      | 
                    //
                    // +'h80 means skipping 128B reserved area 
                    host_mem_addr <= current_huge_page_addr + 'h80;
                    huge_page_qword_counter <= 'b0;
                    if (huge_page_available) begin
                        send_fsm <= s1;
                    end
                end

                s1 : begin
                    // [Huge page available]
                    // qwords_to_send is set by rx_tlp_trigger whenever a TLP is
                    // ready to send. qwords_to_send is 4bit, with which 8B x 16 = 128B
                    // the size of maximum TLP for RX.
                    qwords_in_tlp <= {4'b0, qwords_to_send};
                    endpoint_not_ready <= 1'b0;

                    driving_interface <= 1'b0;                                              // we're taking the risk of starving the tx process
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;
                    if ( (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (my_turn || driving_interface) ) begin
                        // change_huge_page is a signal set by rx_tlp_trigger
                        // and remember_to_change_huge_page is set when
                        // send_last_tlp is set. Either of those two signal
                        // lets the status go to s8 to end and switch huge page.
                        if (change_huge_page || remember_to_change_huge_page) begin
                            remember_to_change_huge_page <= 1'b0;
                            change_huge_page_ack <= 1'b1;
                            driving_interface <= 1'b1;
                            send_fsm <= s8;
                        end
                        else if (send_last_tlp) begin
                            remember_to_change_huge_page <= 1'b1;
                            driving_interface <= 1'b1;
                            send_fsm <= s2;
                        end
                        else if (trigger_tlp) begin
                            driving_interface <= 1'b1;
                            trigger_tlp_ack <= 1'b1;
                            send_fsm <= s2;
                        end
                    end
                end

                s2 : begin
                    // [Start of frame]
                    // # of dwords is the key metadata in the header
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                `TX_MEM_WR64_FMT_TYPE, //memory write request 64bit addressing
                                1'b0,   //reserved
                                3'b0,   //TC (traffic class)
                                4'b0,   //reserved
                                1'b0,   //TD (TLP digest present)
                                1'b0,   //EP (poisoned data)
                                2'b00,  //Relaxed ordering, No snoop in processor cache
                                2'b0,   //reserved
                                {qwords_in_tlp, 1'b0}  //lenght in DWs. 10-bit field    // QWs x2 equals DWs
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id,   //Requester ID
                                {4'b0, tlp_number[3:0] },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    rd_addr <= rd_addr +1;
                    trigger_tlp_ack <= 1'b0;

                    // look_ahead_* keep the next metadata including address
                    // and counter. this bookeeping is for s5 when TLP is
                    // entirely sent.
                    look_ahead_host_mem_addr <= host_mem_addr + {qwords_in_tlp, 3'b0};
                    look_ahead_huge_page_qword_counter <= huge_page_qword_counter + qwords_in_tlp;
                    look_ahead_tlp_number <= tlp_number +1;

                    send_fsm <= s3;
                end

                s3 : begin
                    // [Host address xmit]
                    // if the endpoint is ready, the next part is
                    // host_mem_addr, which is host-side destination address.
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= host_mem_addr;

                        if (!endpoint_not_ready) begin
                            rd_addr <= rd_addr +1;
                            send_fsm <= s4;
                        end
                        else begin
                            send_fsm <= s6;
                        end
                    end
                    else begin
                        endpoint_not_ready <= 1'b1;
                        rd_addr <= rd_addr_prev1;
                    end
                    tlp_qword_counter <= 9'b1;
                end

                s4 : begin
                    // [Packet fill]
                    // if the endpoint is ready, start sending data (rd_data)
                    // by incrementing rd_addr until the entire TLP is sent.
                    // Once the sentire TLP is sent, goto s5.
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= {rd_data[7:0], rd_data[15:8], rd_data[23:16], rd_data[31:24], rd_data[39:32], rd_data[47:40], rd_data[55:48] ,rd_data[63:56]};

                        rd_addr <= rd_addr +1;

                        tlp_qword_counter <= tlp_qword_counter +1;
                        if (tlp_qword_counter == qwords_in_tlp) begin
                            trn_teof_n <= 1'b0;
                            send_fsm <= s5;
                        end
                    end
                    else begin
                        rd_addr <= rd_addr_prev2;
                        send_fsm <= s6;
                    end
                end

                s5 : begin
                    // [Commit read address]
                    // Once a TLP is entirely drained from internal buffer, it
                    // updates commited_rd_address, which let the MAC-side
                    // producer know here is more available space in the buffer.
                    commited_rd_address <= rd_addr_prev2;
                    rd_addr <= rd_addr_prev2;
                    host_mem_addr <= look_ahead_host_mem_addr;
                    huge_page_qword_counter <= look_ahead_huge_page_qword_counter;
                    tlp_number <= look_ahead_tlp_number;
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        send_fsm <= s1;
                    end
                end

                s6 : begin
                    // [Endpoint not ready]
                    if (!trn_tdst_rdy_n) begin
                        rd_addr <= rd_addr +1;
                        trn_tsrc_rdy_n <= 1'b1;
                        send_fsm <= s7;
                    end
                end

                s7 : begin
                    // [Endpoint ready and resume packet fill]
                    trn_tsrc_rdy_n <= 1'b1;
                    rd_addr <= rd_addr +1;
                    send_fsm <= s4;
                end
                
                s8 : begin
                    // [Preparation for huge page switch]
                    // Once all TLPs are sent for a huge page and finalize it,
                    // it sends the last TLP to update "nr_qwords" at the
                    // header space of the huge page, by which driver knows
                    // how many qwords are valid in the huge page. The driver
                    // uses LBUF_NR_DWORDS macro to extract this information.
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                `TX_MEM_WR64_FMT_TYPE, //memory write request 64bit addressing
                                1'b0,   //reserved
                                3'b0,   //TC (traffic class)
                                4'b0,   //reserved
                                1'b0,   //TD (TLP digest present)
                                1'b0,   //EP (poisoned data)
                                2'b00,  //Relaxed ordering, No snoop in processor cache
                                2'b0,   //reserved
                                10'h02  //lenght equal 2 DW 
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id,   //Requester ID
                                {4'b0, 4'b0 },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    change_huge_page_ack <= 1'b0;
                    send_fsm <= s9;
                end

                s9 : begin
                    // [Host address xmit for nr_qwords location]
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        return_huge_page_to_host <= 1'b1;
                        trn_td <= current_huge_page_addr;
                        send_fsm <= s10;
                    end
                end

                s10 : begin
                    // [nr_qwords xmit]
                    return_huge_page_to_host <= 1'b0;
                    if (!trn_tdst_rdy_n) begin
                        trn_td <= {huge_page_qword_counter[7:0], huge_page_qword_counter[15:8], huge_page_qword_counter[23:16], huge_page_qword_counter[31:24], 32'b0};
                        trn_teof_n <= 1'b0;
                        send_fsm <= s11;
                    end
                end

                s11 : begin
                    // [Interrupt generation]
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        if (interrupts_enabled) begin
                            cfg_interrupt_n <= 1'b0;
                            send_fsm <= s12;
                        end
                        else begin
                            send_fsm <= s0;
                        end
                    end
                end

                s12 : begin
                    // [Clear interrupt back to beginning]
                    if (!cfg_interrupt_rdy_n) begin
                        cfg_interrupt_n <= 1'b1;
                        send_fsm <= s0;
                    end
                end

                default : begin 
                    send_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // rx_wr_pkt_to_hugepages

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
