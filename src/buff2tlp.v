/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        buff2tlp.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Sends TLP when a trigger is received. TLPs with maximum payload size
*        are normally sent. Ethernet frames boundaries are not taken into
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

module buff2tlp (

    input                    clk,
    input                    rst,

    // TRN tx
    output reg   [63:0]      trn_td,
    output reg   [7:0]       trn_trem_n,
    output reg               trn_tsof_n,
    output reg               trn_teof_n,
    output reg               trn_tsrc_rdy_n,
    input                    trn_tdst_rdy_n,
    input        [3:0]       trn_tbuf_av,

    // CFG
    input        [15:0]      cfg_completer_id,

    // lbuf_mgmt
    input        [63:0]      lbuf_addr,
    input                    lbuf_en,
    input                    lbuf64b,
    output reg               lbuf_dn,

    // eth2tlp_ctrl
    input                    trig_tlp,
    output reg               trig_tlp_ack,
    input                    chng_lbuf,
    output reg               chng_lbuf_ack,
    input                    send_qws,
    output reg               send_qws_ack,
    input        [5:0]       qw_cnt,

    // mac2buff
    output reg   [`BF:0]     committed_cons,

    // buff
    output reg   [`BF:0]     rd_addr,
    input        [63:0]      rd_data,

    // irq_gen
    output       [63:0]      hw_ptr,

    // ep arb
    input                    my_trn,
    output reg               drv_ep,

    // stats
    input        [15:0]      dropped_pkts
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
    // Local send_tlps_machine
    //-------------------------------------------------------   
    reg          [27:0]      send_fsm;
    reg                      lbuf_dn;
    reg          [8:0]       tlp_qw_cnt;
    reg          [4:0]       tlp_nmb;
    reg          [4:0]       look_ahead_tlp_nmb;
    reg          [8:0]       qw_in_tlp;
    reg          [63:0]      host_mem_addr;
    reg          [63:0]      look_ahead_host_mem_addr;
    reg          [63:0]      aux1_host_mem_addr;
    reg          [31:0]      lbuf_qw_cnt;
    reg          [31:0]      aux_qw_cnt;
    reg          [31:0]      next_qw_cnt;
    reg          [31:0]      look_ahead_lbuf_qw_cnt;
    reg          [`BF:0]     rd_addr_prev1;
    reg          [`BF:0]     rd_addr_prev2;
    reg          [`BF:0]     look_ahead_committed_cons;
    reg          [31:0]      aux_rd_data;
    reg                      close_lbuf;
    reg          [15:0]      dropped_pkts_reg;
    
    assign hw_ptr = host_mem_addr;

    ////////////////////////////////////////////////
    // write request TLP generation to huge_page
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            trn_tsof_n <= 1'b1;
            trn_teof_n <= 1'b1;
            trn_tsrc_rdy_n <= 1'b1;

            lbuf_dn <= 1'b0;
            drv_ep <= 1'b0;

            trig_tlp_ack <= 1'b0;
            chng_lbuf_ack <= 1'b0;
            send_qws_ack <= 1'b0;

            committed_cons <= 'b0;
            rd_addr <= 'b0;

            tlp_nmb <= 'b0;

            send_fsm <= s0;
        end
        
        else begin  // not rst

            trig_tlp_ack <= 1'b0;
            chng_lbuf_ack <= 1'b0;
            send_qws_ack <= 1'b0;
            lbuf_dn <= 1'b0;

            rd_addr_prev1 <= rd_addr;
            rd_addr_prev2 <= rd_addr_prev1;

            dropped_pkts_reg <= dropped_pkts;

            case (send_fsm)

                s0 : begin
                    drv_ep <= 1'b0;
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;

                    host_mem_addr <= lbuf_addr + 'h80;
                    lbuf_qw_cnt <= 'b0;
                    if (lbuf_en) begin
                        if (lbuf64b) begin
                            send_fsm <= s1;
                        end
                        else begin
                            send_fsm <= s14;
                        end
                    end
                end

                s1 : begin
                    qw_in_tlp <= {3'b0, qw_cnt};

                    drv_ep <= 1'b0;                                              // we're taking the risk of starving the tx process
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;
                    if ((trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (my_trn || drv_ep) ) begin
                        if (chng_lbuf) begin
                            close_lbuf <= 1'b1;
                            chng_lbuf_ack <= 1'b1;
                            drv_ep <= 1'b1;
                            send_fsm <= s10;
                        end
                        else if (trig_tlp) begin
                            drv_ep <= 1'b1;
                            trig_tlp_ack <= 1'b1;
                            send_fsm <= s2;
                        end
                        else if (send_qws) begin
                            close_lbuf <= 1'b0;
                            send_qws_ack <= 1'b1;
                            drv_ep <= 1'b1;
                            send_fsm <= s10;
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
                                {qw_in_tlp, 1'b0}  //lenght in DWs. 10-bit field    // QWs x2 equals DWs
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id,   //Requester ID
                                {3'b0, tlp_nmb },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    rd_addr <= rd_addr +1;

                    look_ahead_host_mem_addr <= host_mem_addr + {qw_in_tlp, 3'b0};
                    look_ahead_lbuf_qw_cnt <= lbuf_qw_cnt + qw_in_tlp;
                    look_ahead_tlp_nmb <= tlp_nmb +1;
                    look_ahead_committed_cons <= committed_cons + qw_in_tlp;

                    send_fsm <= s3;
                end

                s3 : begin
                    tlp_qw_cnt <= 9'b1;
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= host_mem_addr;
                        rd_addr <= rd_addr +1;
                        send_fsm <= s6;
                    end
                    else begin
                        rd_addr <= rd_addr_prev1;
                        send_fsm <= s4;
                    end
                end

                s4 : begin
                    if (!trn_tdst_rdy_n) begin
                        rd_addr <= rd_addr +1;
                        trn_tsrc_rdy_n <= 1'b1;
                        trn_tsof_n <= 1'b1;
                        send_fsm <= s3;
                    end
                end

                s6 : begin
                    aux1_host_mem_addr <= look_ahead_host_mem_addr + 'h7F;  // align 128
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= {
                                rd_data[7:0],
                                rd_data[15:8],
                                rd_data[23:16],
                                rd_data[31:24],
                                rd_data[39:32],
                                rd_data[47:40],
                                rd_data[55:48],
                                rd_data[63:56]
                            };

                        rd_addr <= rd_addr +1;

                        tlp_qw_cnt <= tlp_qw_cnt +1;
                        if (tlp_qw_cnt == qw_in_tlp) begin
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
                    committed_cons <= look_ahead_committed_cons;
                    rd_addr <= look_ahead_committed_cons;
                    host_mem_addr <= {aux1_host_mem_addr[63:7], 7'b0};
                    lbuf_qw_cnt <= look_ahead_lbuf_qw_cnt;
                    tlp_nmb <= look_ahead_tlp_nmb;
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
                    aux_qw_cnt <= lbuf_qw_cnt;
                    next_qw_cnt <= lbuf_qw_cnt + 'hF;
                    send_fsm <= s11;
                end

                s11 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        lbuf_dn <= close_lbuf;
                        trn_td <= lbuf_addr;
                        send_fsm <= s12;
                    end
                end

                s12 : begin
                    lbuf_qw_cnt <= {next_qw_cnt[31:4], 4'b0};
                    if (!trn_tdst_rdy_n) begin
                        trn_td <= {
                                aux_qw_cnt[7:0],
                                aux_qw_cnt[15:8],
                                aux_qw_cnt[23:16],
                                aux_qw_cnt[31:24],
                                {7'b0, close_lbuf},
                                dropped_pkts_reg[7:0],
                                dropped_pkts_reg[15:8],
                                8'b0
                            };
                        trn_teof_n <= 1'b0;
                        send_fsm <= s13;
                    end
                end

                s13 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        if (close_lbuf) begin
                            send_fsm <= s0;
                        end
                        else begin
                            send_fsm <= s1;
                        end
                    end
                end

                s14 : begin
                    qw_in_tlp <= {3'b0, qw_cnt};

                    drv_ep <= 1'b0;                                              // we're taking the risk of starving the tx process
                    trn_td <= 64'b0;
                    trn_trem_n <= 8'hFF;
                    if ( (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (my_trn || drv_ep) ) begin
                        if (chng_lbuf) begin
                            close_lbuf <= 1'b1;
                            chng_lbuf_ack <= 1'b1;
                            drv_ep <= 1'b1;
                            send_fsm <= s24;
                        end
                        else if (trig_tlp) begin
                            drv_ep <= 1'b1;
                            trig_tlp_ack <= 1'b1;
                            send_fsm <= s15;
                        end
                        else if (send_qws) begin
                            close_lbuf <= 1'b0;
                            send_qws_ack <= 1'b1;
                            drv_ep <= 1'b1;
                            send_fsm <= s24;
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
                                {qw_in_tlp, 1'b0}  //lenght in DWs. 10-bit field    // QWs x2 equals DWs
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id,   //Requester ID
                                {3'b0, tlp_nmb },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    rd_addr <= rd_addr +1;

                    look_ahead_host_mem_addr <= host_mem_addr + {qw_in_tlp, 3'b0};
                    look_ahead_lbuf_qw_cnt <= lbuf_qw_cnt + qw_in_tlp;
                    look_ahead_tlp_nmb <= tlp_nmb +1;
                    look_ahead_committed_cons <= committed_cons + qw_in_tlp;

                    send_fsm <= s17;
                end

                s17 : begin
                    aux_rd_data <= rd_data[63:32];
                    tlp_qw_cnt <= 9'b1;
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b0;
                        trn_td <= {
                                host_mem_addr[31:0],
                                rd_data[7:0],
                                rd_data[15:8],
                                rd_data[23:16],
                                rd_data[31:24]
                            };
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
                    aux1_host_mem_addr <= look_ahead_host_mem_addr + 'h7F;  // align 128
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b0;
                        aux_rd_data <= rd_data[63:32];
                        trn_td <= {
                                aux_rd_data[7:0],
                                aux_rd_data[15:8],
                                aux_rd_data[23:16],
                                aux_rd_data[31:24],
                                rd_data[7:0],
                                rd_data[15:8],
                                rd_data[23:16],
                                rd_data[31:24]
                            };
                        rd_addr <= rd_addr +1;
                        tlp_qw_cnt <= tlp_qw_cnt +1;
                        if (tlp_qw_cnt == qw_in_tlp) begin
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
                    committed_cons <= look_ahead_committed_cons;
                    rd_addr <= look_ahead_committed_cons;
                    host_mem_addr <= {aux1_host_mem_addr[63:7], 7'b0};
                    lbuf_qw_cnt <= look_ahead_lbuf_qw_cnt;
                    tlp_nmb <= look_ahead_tlp_nmb;
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
                    aux_qw_cnt <= lbuf_qw_cnt;
                    next_qw_cnt <= lbuf_qw_cnt + 'hF;
                    send_fsm <= s25;
                end

                s25 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        lbuf_dn <= close_lbuf;
                        trn_td <= {
                                lbuf_addr[31:0],
                                aux_qw_cnt[7:0],
                                aux_qw_cnt[15:8],
                                aux_qw_cnt[23:16],
                                aux_qw_cnt[31:24]
                            };
                        send_fsm <= s26;
                    end
                end

                s26 : begin
                    lbuf_qw_cnt <= {next_qw_cnt[31:4], 4'b0};
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= {
                                {7'b0, close_lbuf},
                                dropped_pkts_reg[7:0],
                                dropped_pkts_reg[15:8],
                                8'b0
                            };
                        trn_teof_n <= 1'b0;
                        send_fsm <= s27;
                    end
                end

                s27 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_teof_n <= 1'b1;
                        trn_tsrc_rdy_n <= 1'b1;
                        if (close_lbuf) begin
                            send_fsm <= s0;
                        end
                        else begin
                            send_fsm <= s14;
                        end
                    end
                end

                default : begin 
                    send_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // buff2tlp

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////