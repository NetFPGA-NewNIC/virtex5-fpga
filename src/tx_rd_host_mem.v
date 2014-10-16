/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        tx_rd_host_mem.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Sends TLPs with memory read request to the host. Ethernet boundaries
*        are not taken in consideration. Sends notification to the host when
*        it finishes reading (huge) pages.
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

module tx_rd_host_mem (

    input                  trn_clk,
    input                  reset,

    //Rx
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

    // Internal logic

    input       [63:0]     completed_buffer_address,

    input       [63:0]     huge_page_addr,
    input                  read_chunk,
    output reg  [3:0]      tlp_tag,
    input       [8:0]      qwords_to_rd,
    output reg             read_chunk_ack,
    input                  send_rd_completed,
    output reg             send_rd_completed_ack,

    input                  notify,
    input       [63:0]     notification_message,
    output reg             notify_ack,

    input                  send_interrupt,
    output reg             send_interrupt_ack,

    // Arbitrations hanshake

    input                  my_turn,
    output reg             driving_interface

    );
    parameter NUMB_HP = 2;      // = 2^something
    
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
    // Local send_tlps_machine
    //-------------------------------------------------------   
    reg     [14:0]  rd_host_fsm;
    reg     [63:0]  host_mem_addr;
    reg     [63:0]  next_completed_buffer_address;
    reg     [63:0]  last_completed_buffer_address;
    reg     [31:0]  huge_page_index;
    reg     [31:0]  next_huge_page_index;
    reg     [63:0]  notification_message_reg;
    reg     [3:0]   next_tlp_tag;
    reg             aux0_high_mem;
    reg             aux1_high_mem;

    ////////////////////////////////////////////////
    // read request TLP generation to huge_page
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            trn_td <= 64'b0;
            trn_trem_n <= 8'hFF;
            trn_tsof_n <= 1'b1;
            trn_teof_n <= 1'b1;
            trn_tsrc_rdy_n <= 1'b1;
            cfg_interrupt_n <= 1'b1;

            read_chunk_ack <= 1'b0;
            send_rd_completed_ack <= 1'b0;
            huge_page_index <= 'b0;
            send_interrupt_ack <= 1'b0;
            notify_ack <= 1'b0;
            tlp_tag <= 'b0;

            driving_interface <= 1'b0;
            rd_host_fsm <= s0;
        end
        
        else begin  // not reset

            read_chunk_ack <= 1'b0;
            send_rd_completed_ack <= 1'b0;
            send_interrupt_ack <= 1'b0;
            notify_ack <= 1'b0;
            next_huge_page_index <= (huge_page_index + 1) & (~NUMB_HP);

            case (rd_host_fsm)

                s0 : begin
                    next_completed_buffer_address <= completed_buffer_address + {huge_page_index, 2'b00};
                    last_completed_buffer_address <= completed_buffer_address + 4'b1000;
                    driving_interface <= 1'b0;
                    host_mem_addr <= huge_page_addr;
                    aux0_high_mem <= | huge_page_addr[63:32];
                    aux1_high_mem <= | completed_buffer_address[63:32];
                    notification_message_reg <= notification_message;
                    next_tlp_tag <= tlp_tag +1;
                    if (my_turn) begin
                        if ( (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) ) begin
                            if (notify) begin
                                driving_interface <= 1'b1;
                                notify_ack <= 1'b1;
                                rd_host_fsm <= s10;
                            end
                            else if (send_rd_completed) begin
                                driving_interface <= 1'b1;
                                send_rd_completed_ack <= 1'b1;
                                rd_host_fsm <= s5;
                            end
                            else if (send_interrupt) begin
                                cfg_interrupt_n <= 1'b0;
                                driving_interface <= 1'b1;
                                send_interrupt_ack <= 1'b1;
                                rd_host_fsm <= s9;
                            end
                        end
                        else if ( (trn_tbuf_av[0]) && (!trn_tdst_rdy_n) ) begin
                            if (read_chunk) begin
                                driving_interface <= 1'b1;
                                read_chunk_ack <= 1'b1;
                                rd_host_fsm <= s1;
                            end
                        end
                    end
                end

                s1 : begin
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                aux0_high_mem ? `MEM_RD64_FMT_TYPE : `MEM_RD32_FMT_TYPE, //memory read request 64bit or 32bit addressing
                                1'b0,   //reserved
                                3'b0,   //TC (traffic class)
                                4'b0,   //reserved
                                1'b0,   //TD (TLP digest present)
                                1'b0,   //EP (poisoned data)
                                2'b10,  //Relaxed ordering, No snoop in processor cache
                                2'b0,   //reserved
                                {qwords_to_rd, 1'b0}
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id,   //Requester ID
                                {4'b0, tlp_tag },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    tlp_tag <= next_tlp_tag;

                    if (aux0_high_mem) begin
                        rd_host_fsm <= s2;
                    end
                    else begin
                        trn_trem_n <= 8'h0F;
                        rd_host_fsm <= s3;
                    end
                end

                s2 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_teof_n <= 1'b0;
                        trn_td <= host_mem_addr;
                        rd_host_fsm <= s4;
                    end
                end

                s3 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_teof_n <= 1'b0;
                        trn_td[63:32] <= host_mem_addr[31:0];
                        rd_host_fsm <= s4;
                    end
                end

                s4 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b1;
                        trn_teof_n <= 1'b1;
                        trn_trem_n <= 8'hFF;
                        trn_td <= 64'b0;
                        driving_interface <= 1'b0;
                        rd_host_fsm <= s0;
                    end
                end

                s5 : begin
                    huge_page_index <= next_huge_page_index;
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                aux1_high_mem ? `MEM_WR64_FMT_TYPE : `MEM_WR32_FMT_TYPE, //memory write request 64bit or 32bit addressing
                                1'b0,   //reserved
                                3'b0,   //TC (traffic class)
                                4'b0,   //reserved
                                1'b0,   //TD (TLP digest present)
                                1'b0,   //EP (poisoned data)
                                2'b00,  //Relaxed ordering, No spoon in processor cache
                                2'b0,   //reserved
                                10'h01  //lenght equal 1 DW 
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id,   //Requester ID
                                {4'b0, 4'b0 },   //Tag
                                4'h0,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    
                    if (aux1_high_mem) begin
                        trn_trem_n <= 8'h0F;
                        rd_host_fsm <= s6;
                    end
                    else begin
                        rd_host_fsm <= s8;
                    end
                end

                s6 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td <= next_completed_buffer_address;
                        rd_host_fsm <= s7;
                    end
                end

                s7 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= 32'hEFBECACA;
                        trn_teof_n <= 1'b0;
                        rd_host_fsm <= s4;
                    end
                end

                s8 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_teof_n <= 1'b0;
                        trn_td <= {next_completed_buffer_address[31:0], 32'hEFBECACA};
                        rd_host_fsm <= s4;
                    end
                end

                s9 : begin
                    if (!cfg_interrupt_rdy_n) begin
                        cfg_interrupt_n <= 1'b1;
                        driving_interface <= 1'b0;
                        rd_host_fsm <= s0;
                    end
                end

                s10 : begin
                    trn_trem_n <= 8'b0;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                aux1_high_mem ? `MEM_WR64_FMT_TYPE : `MEM_WR32_FMT_TYPE, //memory write request 64bit or 32bit addressing
                                1'b0,   //reserved
                                3'b0,   //TC (traffic class)
                                4'b0,   //reserved
                                1'b0,   //TD (TLP digest present)
                                1'b0,   //EP (poisoned data)
                                2'b00,  //Relaxed ordering, No spoon in processor cache
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
                    
                    if (aux1_high_mem) begin
                        rd_host_fsm <= s11;
                    end
                    else begin
                        trn_trem_n <= 8'h0F;
                        rd_host_fsm <= s13;
                    end
                end

                s11 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td <= last_completed_buffer_address;
                        rd_host_fsm <= s12;
                    end
                end

                s12 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td <= {notification_message_reg[7:0], notification_message_reg[15:8], notification_message_reg[23:16], notification_message_reg[31:24], notification_message_reg[39:32], notification_message_reg[47:40], notification_message_reg[55:48], notification_message_reg[63:56]};
                        trn_teof_n <= 1'b0;
                        rd_host_fsm <= s4;
                    end
                end

                s13 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td <= {last_completed_buffer_address[31:0], notification_message_reg[7:0], notification_message_reg[15:8], notification_message_reg[23:16], notification_message_reg[31:24]};
                        rd_host_fsm <= s14;
                    end
                end

                s14 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= {notification_message_reg[39:32], notification_message_reg[47:40], notification_message_reg[55:48], notification_message_reg[63:56]};
                        trn_teof_n <= 1'b0;
                        rd_host_fsm <= s4;
                    end
                end

                default : begin 
                    rd_host_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // tx_rd_host_mem

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////