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

`define MEM_WR64_FMT_TYPE 7'b11_00000
`define MEM_WR32_FMT_TYPE 7'b10_00000
`define MEM_RD64_FMT_TYPE 7'b01_00000
`define MEM_RD32_FMT_TYPE 7'b00_00000

module rx_wr_pkt_to_hugepages (

    input                  trn_clk,
    input                  reset,

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

    output reg  [`BF:0]    commited_rd_addr,
    output reg  [`BF:0]    rd_addr,
    input       [63:0]     rd_data,

    // Arbitrations handshake  //
    input                  my_turn,
    output reg             driving_interface
    );

    // localparam
    localparam s0  = 28'b0000000000000000000000000000;
    localparam s1  = 28'b0000000000000000000000000001;
    localparam s2  = 28'b0000000000000000000000000010;
    localparam s3  = 28'b0000000000000000000000000100;
    localparam s4  = 28'b0000000000000000000000001000;
    localparam s5  = 28'b0000000000000000000000010000;
    localparam s6  = 28'b0000000000000000000000100000;
    localparam s7  = 28'b0000000000000000000001000000;
    localparam s8  = 28'b0000000000000000000010000000;
    localparam s9  = 28'b0000000000000000000100000000;
    localparam s10 = 28'b0000000000000000001000000000;
    localparam s11 = 28'b0000000000000000010000000000;
    localparam s12 = 28'b0000000000000000100000000000;
    localparam s13 = 28'b0000000000000001000000000000;
    localparam s14 = 28'b0000000000000010000000000000;
    localparam s15 = 28'b0000000000000100000000000000;
    localparam s16 = 28'b0000000000001000000000000000;
    localparam s17 = 28'b0000000000010000000000000000;
    localparam s18 = 28'b0000000000100000000000000000;
    localparam s19 = 28'b0000000001000000000000000000;
    localparam s20 = 28'b0000000010000000000000000000;
    localparam s21 = 28'b0000000100000000000000000000;
    localparam s22 = 28'b0000001000000000000000000000;
    localparam s23 = 28'b0000010000000000000000000000;
    localparam s24 = 28'b0000100000000000000000000000;
    localparam s25 = 28'b0001000000000000000000000000;
    localparam s26 = 28'b0010000000000000000000000000;
    localparam s27 = 28'b0100000000000000000000000000;
    localparam s28 = 28'b1000000000000000000000000000;

    //-------------------------------------------------------
    // Local current_huge_page_addr
    //-------------------------------------------------------
    reg     [63:0]      current_huge_page_addr;
    reg     [27:0]      give_huge_page_fsm;
    reg     [27:0]      free_huge_page_fsm;
    reg                 huge_page_available;
    reg                 aux_high_mem;

    //-------------------------------------------------------
    // Local send_tlps_machine
    //-------------------------------------------------------   
    reg     [27:0]      send_fsm;
    reg                 return_huge_page_to_host;
    reg     [8:0]       tlp_qword_counter;
    reg     [31:0]      tlp_number;
    reg     [31:0]      look_ahead_tlp_number;
    reg     [8:0]       qwords_in_tlp;
    reg     [63:0]      host_mem_addr;
    reg     [63:0]      look_ahead_host_mem_addr;
    reg     [31:0]      huge_page_qword_counter;
    reg     [31:0]      look_ahead_huge_page_qword_counter;
    reg                 remember_to_change_huge_page;
    reg     [`BF:0]     rd_addr_prev1;
    reg     [`BF:0]     rd_addr_prev2;
    reg     [`BF:0]     look_ahead_commited_rd_addr;
    reg     [31:0]      aux_rd_data;
    
    ////////////////////////////////////////////////
    // current_huge_page_addr
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            huge_page_free_1 <= 1'b0;
            huge_page_free_2 <= 1'b0;
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
                    if (huge_page_status_1) begin
                        huge_page_available <= 1'b1;
                        current_huge_page_addr <= huge_page_addr_1;
                        aux_high_mem <= | huge_page_addr_1[63:32];
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
                        aux_high_mem <= | huge_page_addr_2[63:32];
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
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            trn_td <= 'b0;
            trn_trem_n <= 'hFF;
            trn_tsof_n <= 1'b1;
            trn_teof_n <= 1'b1;
            trn_tsrc_rdy_n <= 1'b1;
            cfg_interrupt_n <= 1'b1;

            remember_to_change_huge_page <= 1'b0;
            return_huge_page_to_host <= 1'b0;
            driving_interface <= 1'b0;

            trigger_tlp_ack <= 1'b0;
            change_huge_page_ack <= 1'b0;

            commited_rd_addr <= 'b0;
            rd_addr <= 'b0;

            tlp_number <= 'b0;

            send_fsm <= s0;
        end
        
        else begin  // not reset

            trigger_tlp_ack <= 1'b0;
            change_huge_page_ack <= 1'b0;
            return_huge_page_to_host <= 1'b0;

            rd_addr_prev1 <= rd_addr;
            rd_addr_prev2 <= rd_addr_prev1;

            case (send_fsm)

                s0 : begin
                    driving_interface <= 1'b0;
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;

                    host_mem_addr <= current_huge_page_addr + 'h80;
                    huge_page_qword_counter <= 'b0;
                    if (huge_page_available) begin
                        if (aux_high_mem) begin
                            send_fsm <= s1;
                        end
                        else begin
                            send_fsm <= s14;
                        end
                    end
                end

                s1 : begin
                    qwords_in_tlp <= {4'b0, qwords_to_send};

                    driving_interface <= 1'b0;                                              // we're taking the risk of starving the tx process
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;
                    if ( (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (my_turn || driving_interface) ) begin
                        if (change_huge_page || remember_to_change_huge_page) begin
                            remember_to_change_huge_page <= 1'b0;
                            change_huge_page_ack <= 1'b1;
                            driving_interface <= 1'b1;
                            send_fsm <= s10;
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
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                `MEM_WR64_FMT_TYPE, //memory write request 64bit addressing
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

                    look_ahead_host_mem_addr <= host_mem_addr + {qwords_in_tlp, 3'b0};
                    look_ahead_huge_page_qword_counter <= huge_page_qword_counter + qwords_in_tlp;
                    look_ahead_tlp_number <= tlp_number +1;
                    look_ahead_commited_rd_addr <= commited_rd_addr + qwords_in_tlp;

                    send_fsm <= s3;
                end

                s3 : begin
                    tlp_qword_counter <= 9'b1;
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= host_mem_addr;
                        rd_addr <= rd_addr +1;
                        send_fsm <= s6;
                    end
                    else begin
                        rd_addr <= rd_addr_prev2;
                        send_fsm <= s4;
                    end
                end

                s4 : begin
                    if (!trn_tdst_rdy_n) begin
                        rd_addr <= rd_addr +1;
                        trn_tsrc_rdy_n <= 1'b1;
                        trn_tsof_n <= 1'b1;
                        send_fsm <= s5;
                    end
                end

                s5 : begin
                    trn_tsrc_rdy_n <= 1'b1;
                    rd_addr <= rd_addr +1;
                    send_fsm <= s3;
                end

                s6 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= {rd_data[7:0], rd_data[15:8], rd_data[23:16], rd_data[31:24], rd_data[39:32], rd_data[47:40], rd_data[55:48] ,rd_data[63:56]};

                        rd_addr <= rd_addr +1;

                        tlp_qword_counter <= tlp_qword_counter +1;
                        if (tlp_qword_counter == qwords_in_tlp) begin
                            trn_teof_n <= 1'b0;
                            send_fsm <= s9;
                        end
                    end
                    else begin
                        rd_addr <= rd_addr_prev2;
                        send_fsm <= s7;
                    end
                end

                s7 : begin
                    if (!trn_tdst_rdy_n) begin
                        rd_addr <= rd_addr +1;
                        trn_tsrc_rdy_n <= 1'b1;
                        send_fsm <= s8;
                    end
                end

                s8 : begin
                    trn_tsrc_rdy_n <= 1'b1;
                    rd_addr <= rd_addr +1;
                    send_fsm <= s6;
                end

                s9 : begin
                    commited_rd_addr <= look_ahead_commited_rd_addr;
                    rd_addr <= look_ahead_commited_rd_addr;
                    host_mem_addr <= look_ahead_host_mem_addr;
                    huge_page_qword_counter <= look_ahead_huge_page_qword_counter;
                    tlp_number <= look_ahead_tlp_number;
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        send_fsm <= s1;
                    end
                end

                s10 : begin
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                `MEM_WR64_FMT_TYPE, //memory write request 64bit addressing
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
                    send_fsm <= s11;
                end

                s11 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        return_huge_page_to_host <= 1'b1;
                        trn_td <= current_huge_page_addr;
                        send_fsm <= s12;
                    end
                end

                s12 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td <= {huge_page_qword_counter[7:0], huge_page_qword_counter[15:8], huge_page_qword_counter[23:16], huge_page_qword_counter[31:24], 32'b0};
                        trn_teof_n <= 1'b0;
                        send_fsm <= s13;
                    end
                end

                s13 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        if (interrupts_enabled) begin
                            cfg_interrupt_n <= 1'b0;
                            send_fsm <= s28;
                        end
                        else begin
                            send_fsm <= s0;
                        end
                    end
                end

                s14 : begin
                    qwords_in_tlp <= {4'b0, qwords_to_send};

                    driving_interface <= 1'b0;                                              // we're taking the risk of starving the tx process
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;
                    if ( (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (my_turn || driving_interface) ) begin
                        if (change_huge_page || remember_to_change_huge_page) begin
                            remember_to_change_huge_page <= 1'b0;
                            change_huge_page_ack <= 1'b1;
                            driving_interface <= 1'b1;
                            send_fsm <= s24;
                        end
                        else if (send_last_tlp) begin
                            remember_to_change_huge_page <= 1'b1;
                            driving_interface <= 1'b1;
                            send_fsm <= s15;
                        end
                        else if (trigger_tlp) begin
                            driving_interface <= 1'b1;
                            trigger_tlp_ack <= 1'b1;
                            send_fsm <= s15;
                        end
                    end
                end

                s15 : begin
                    rd_addr <= rd_addr +1;
                    send_fsm <= s16;
                end

                s16 : begin
                    trn_trem_n <= 8'h0F;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                `MEM_WR32_FMT_TYPE, //memory write request 32bit addressing
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

                    look_ahead_host_mem_addr <= host_mem_addr + {qwords_in_tlp, 3'b0};
                    look_ahead_huge_page_qword_counter <= huge_page_qword_counter + qwords_in_tlp;
                    look_ahead_tlp_number <= tlp_number +1;
                    look_ahead_commited_rd_addr <= commited_rd_addr + qwords_in_tlp;

                    send_fsm <= s17;
                end

                s17 : begin
                    aux_rd_data <= rd_data[63:32];
                    tlp_qword_counter <= 9'b1;
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td[63:32] <= {host_mem_addr[31:0], rd_data[7:0], rd_data[15:8], rd_data[23:16], rd_data[31:24]};
                        rd_addr <= rd_addr +1;
                        send_fsm <= s20;
                    end
                    else begin
                        rd_addr <= rd_addr_prev2;
                        send_fsm <= s18;
                    end
                end

                s18 : begin
                    if (!trn_tdst_rdy_n) begin
                        rd_addr <= rd_addr +1;
                        trn_tsrc_rdy_n <= 1'b1;
                        trn_tsof_n <= 1'b1;
                        send_fsm <= s19;
                    end
                end

                s19 : begin
                    trn_tsrc_rdy_n <= 1'b1;
                    rd_addr <= rd_addr +1;
                    send_fsm <= s17;
                end

                s20 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b0;
                        aux_rd_data <= rd_data[63:32];
                        trn_td <= {aux_rd_data[7:0], aux_rd_data[15:8], aux_rd_data[23:16], aux_rd_data[31:24], rd_data[7:0], rd_data[15:8], rd_data[23:16], rd_data[31:24]};
                        rd_addr <= rd_addr +1;
                        tlp_qword_counter <= tlp_qword_counter +1;
                        if (tlp_qword_counter == qwords_in_tlp) begin
                            trn_teof_n <= 1'b0;
                            send_fsm <= s23;
                        end
                    end
                    else begin
                        rd_addr <= rd_addr_prev2;
                        send_fsm <= s21;
                    end
                end

                s21 : begin
                    if (!trn_tdst_rdy_n) begin
                        rd_addr <= rd_addr +1;
                        trn_tsrc_rdy_n <= 1'b1;
                        send_fsm <= s22;
                    end
                end

                s22 : begin
                    trn_tsrc_rdy_n <= 1'b1;
                    rd_addr <= rd_addr +1;
                    send_fsm <= s20;
                end

                s23 : begin
                    commited_rd_addr <= look_ahead_commited_rd_addr;
                    rd_addr <= look_ahead_commited_rd_addr;
                    host_mem_addr <= look_ahead_host_mem_addr;
                    huge_page_qword_counter <= look_ahead_huge_page_qword_counter;
                    tlp_number <= look_ahead_tlp_number;
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        send_fsm <= s14;
                    end
                end

                s24 : begin
                    trn_trem_n <= 8'h0F;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                `MEM_WR32_FMT_TYPE, //memory write request 32bit addressing
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
                    send_fsm <= s25;
                end

                s25 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        return_huge_page_to_host <= 1'b1;
                        trn_td <= {current_huge_page_addr[31:0], huge_page_qword_counter[7:0], huge_page_qword_counter[15:8], huge_page_qword_counter[23:16], huge_page_qword_counter[31:24]};
                        send_fsm <= s26;
                    end
                end

                s26 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= {32'b0};
                        trn_teof_n <= 1'b0;
                        send_fsm <= s27;
                    end
                end

                s27 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        if (interrupts_enabled) begin
                            cfg_interrupt_n <= 1'b0;
                            send_fsm <= s28;
                        end
                        else begin
                            send_fsm <= s0;
                        end
                    end
                end

                s28 : begin
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