/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mem_rd.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Read host memory.
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

module mem_rd # (
    parameter DSCW = 1,
    parameter DSC_CPL_MSG = 32'hCACABEEF,
    parameter DSC_BASE_QW = 0,
    parameter GC_BASE_QW = 1,
    // RQ_TAG_BASE
    parameter RQTB = 5'b00000,
    // Outstanding request width
    parameter OSRW = 4
    ) (

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
    input        [63:0]      cpl_addr,
    input                    lbuf64b,

    // ibuf_mgmt
    input        [63:0]      hst_addr,
    input                    rd,
    input        [8:0]       rd_qw,
    output reg               rd_ack,
    output reg   [OSRW-1:0]  rd_tag,

    // dsc_mgmt
    input                    dsc_rdy,
    output reg               dsc_rdy_ack,

    // gc_mgmt
    input        [63:0]      gc_addr,
    input                    gc_updt,
    output reg               gc_updt_ack,

    // irq_gen
    output reg               hw_ptr_update,
    output reg   [63:0]      hw_ptr,

    // ep arb
    input                    my_trn,
    output reg               drv_ep,
    output reg               req_ep
    );

    `include "includes.v"
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
    // Local send_fsm
    //-------------------------------------------------------   
    reg          [14:0]      send_fsm;
    reg          [15:0]      cfg_completer_id_reg;
    reg          [63:0]      cpl_addr_reg;
    reg                      cpl_addr64b;
    // RD
    reg          [63:0]      hst_addr_reg0;
    reg          [63:0]      hst_addr_reg1;
    reg                      lbuf64b_reg;
    reg          [8:0]       rd_qw_reg;
    reg          [OSRW-1:0]  nxt_rd_tag;
    // DSC
    reg          [63:0]      dsc_base;
    reg          [63:0]      dsc_cpl_addr;
    reg          [31:0]      dsc_idx;
    reg          [31:0]      nxt_dsc_idx;
    // GC
    reg          [63:0]      gc_base;
    reg          [63:0]      gc_addr_reg;

    ////////////////////////////////////////////////
    // send_fsm
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            trn_tsof_n <= 1'b1;
            trn_teof_n <= 1'b1;
            trn_tsrc_rdy_n <= 1'b1;
            send_fsm <= s0;
        end
        
        else begin  // not rst

            rd_ack <= 1'b0;
            dsc_rdy_ack <= 1'b0;
            gc_updt_ack <= 1'b0;

            hw_ptr_update <= 1'b0;

            req_ep <= 1'b0;

            lbuf64b_reg <= lbuf64b;

            cpl_addr_reg <= cpl_addr;
            cpl_addr64b <= | cpl_addr_reg[63:32];

            dsc_base <= cpl_addr_reg + {DSC_BASE_QW, 3'b0};
            gc_base <= cpl_addr_reg + {GC_BASE_QW, 3'b0};

            nxt_dsc_idx <= dsc_idx + 1;

            cfg_completer_id_reg <= cfg_completer_id;

            case (send_fsm)

                s0 : begin
                    trn_td <= 'b0;
                    trn_trem_n <= 8'hFF;
                    drv_ep <= 1'b0;
                    dsc_idx <= 'b0;
                    rd_tag <= 'b0;
                    send_fsm <= s1;
                end

                s1 : begin
                    trn_td <= 'b0;
                    trn_trem_n <= 8'hFF;
                    drv_ep <= 1'b0;
                    // GC
                    gc_addr_reg <= gc_addr;
                    // DSC
                    dsc_cpl_addr <= dsc_base + {dsc_idx[DSCW-1:0], 2'b0};
                    // RD
                    rd_qw_reg <= rd_qw;
                    hst_addr_reg0 <= hst_addr;
                    //
                    if (gc_updt || dsc_rdy || rd) begin
                        req_ep <= 1'b1;
                    end
                    if ((my_trn) && (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (gc_updt)) begin
                        req_ep <= 1'b0;
                        drv_ep <= 1'b1;
                        gc_updt_ack <= 1'b1;
                        send_fsm <= s9;
                    end
                    else if ((my_trn) && (trn_tbuf_av[1]) && (!trn_tdst_rdy_n) && (dsc_rdy)) begin
                        req_ep <= 1'b0;
                        drv_ep <= 1'b1;
                        dsc_rdy_ack <= 1'b1;
                        send_fsm <= s5;
                    end
                    else if ((my_trn) && (trn_tbuf_av[0]) && (!trn_tdst_rdy_n) && (rd)) begin
                        req_ep <= 1'b0;
                        drv_ep <= 1'b1;
                        rd_ack <= 1'b1;
                        send_fsm <= s2;
                    end
                end

                s2 : begin
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                lbuf64b_reg ? `MEM_RD64_FMT_TYPE : `MEM_RD32_FMT_TYPE,
                                1'b0,   //reserved
                                3'b0,   //TC (traffic class)
                                4'b0,   //reserved
                                1'b0,   //TD (TLP digest present)
                                1'b0,   //EP (poisoned data)
                                2'b10,  //Relaxed ordering, No snoop in processor cache
                                2'b0,   //reserved
                                {rd_qw_reg, 1'b0}
                            };
                    trn_td[31:0] <= {
                                cfg_completer_id_reg,   //Requester ID
                                {3'b0, RQTB[4:OSRW], rd_tag },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;

                    nxt_rd_tag <= rd_tag + 1;

                    if (lbuf64b_reg) begin
                        trn_trem_n <= 8'h0;
                        hst_addr_reg1 <= hst_addr_reg0;
                    end
                    else begin
                        trn_trem_n <= 8'h0F;
                        hst_addr_reg1[63:32] <= hst_addr_reg0[31:0];
                    end
                    send_fsm <= s3;
                end

                s3 : begin
                    rd_tag <= nxt_rd_tag;
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_teof_n <= 1'b0;
                        trn_td <= hst_addr_reg1;
                        send_fsm <= s4;
                    end
                end

                s4 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b1;
                        trn_teof_n <= 1'b1;
                        drv_ep <= 1'b0;
                        send_fsm <= s1;
                    end
                end

                s5 : begin
                    dsc_idx <= nxt_dsc_idx;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                cpl_addr64b ? `MEM_WR64_FMT_TYPE : `MEM_WR32_FMT_TYPE,
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
                                cfg_completer_id_reg,   //Requester ID
                                {4'b0, 4'b0 },   //Tag
                                4'h0,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    
                    if (cpl_addr64b) begin
                        trn_trem_n <= 8'h0F;
                        send_fsm <= s6;
                    end
                    else begin
                        trn_trem_n <= 8'b0;
                        send_fsm <= s8;
                    end
                end

                s6 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td <= dsc_cpl_addr;
                        send_fsm <= s7;
                    end
                end

                s7 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= dw_endian_conv(DSC_CPL_MSG);
                        trn_teof_n <= 1'b0;
                        send_fsm <= s4;
                    end
                end

                s8 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_teof_n <= 1'b0;
                        trn_td[63:32] <= dsc_cpl_addr[31:0];
                        trn_td[31:0] <= dw_endian_conv(DSC_CPL_MSG);
                        send_fsm <= s4;
                    end
                end

                s9 : begin
                    hw_ptr <= gc_addr_reg;
                    hw_ptr_update <= 1'b1;
                    trn_td[63:32] <= {
                                1'b0,   //reserved
                                cpl_addr64b ? `MEM_WR64_FMT_TYPE : `MEM_WR32_FMT_TYPE,
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
                                cfg_completer_id_reg,   //Requester ID
                                {4'b0, 4'b0 },   //Tag
                                4'hF,   //last DW byte enable
                                4'hF    //1st DW byte enable
                            };
                    trn_tsof_n <= 1'b0;
                    trn_tsrc_rdy_n <= 1'b0;
                    
                    if (cpl_addr64b) begin
                        trn_trem_n <= 8'b0;
                        send_fsm <= s10;
                    end
                    else begin
                        trn_trem_n <= 8'h0F;
                        send_fsm <= s12;
                    end
                end

                s10 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td <= gc_base;
                        send_fsm <= s11;
                    end
                end

                s11 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td <= qw_endian_conv(gc_addr_reg);
                        trn_teof_n <= 1'b0;
                        send_fsm <= s4;
                    end
                end

                s12 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td[63:32] <= gc_base[31:0];
                        trn_td[31:0] <= dw_endian_conv(gc_addr_reg[31:0]);
                        send_fsm <= s13;
                    end
                end

                s13 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= dw_endian_conv(gc_addr_reg[63:32]);
                        trn_teof_n <= 1'b0;
                        send_fsm <= s4;
                    end
                end

                default : begin 
                    send_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // mem_rd

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////