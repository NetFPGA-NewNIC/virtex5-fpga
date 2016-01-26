/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        regif2tlp.v
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

module regif2tlp (

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

    // tlp2regif
    input        [63:0]      cpl_addr,

    // regif2tlp
    input                    snd_resp,
    output reg               snd_resp_ack,
    input        [63:0]      resp,

    // EP ARB
    input                    my_trn,
    output reg               drv_ep,
    output reg               req_ep
    );

    `include "includes.v"
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
    // Local send_fsm
    //-------------------------------------------------------   
    reg          [7:0]       send_fsm;
    reg          [15:0]      cfg_completer_id_reg;
    reg          [63:0]      cpl_addr_reg;
    reg                      cpl_addr64b;
    reg                      dn;
    reg                      snd_resp_reg0;
    reg                      snd_resp_reg1;
    reg          [63:0]      resp_reg;
    reg          [2:0]       wait_cnt;

    //-------------------------------------------------------
    // Local Output driver
    //-------------------------------------------------------
    reg          [7:0]       odr_fsm;

    ////////////////////////////////////////////////
    // Output driver. Keep high for 5 (250MHz) ticks (1 50MHz tick)
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            snd_resp_ack <= 1'b0;
            odr_fsm <= s0;
        end
        
        else begin  // not rst

            case (odr_fsm)

                s0 : begin
                    snd_resp_ack <= 1'b0;
                    odr_fsm <= s1;
                end

                s1 : begin
                    if (dn) begin
                        snd_resp_ack <= 1'b1;
                        odr_fsm <= s2;
                    end
                end

                s2 : odr_fsm <= s3;
                s3 : odr_fsm <= s4;
                s4 : odr_fsm <= s5;
                s5 : odr_fsm <= s0;

                default : begin
                    odr_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

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

            dn <= 1'b0;

            cpl_addr_reg <= cpl_addr;
            cpl_addr64b <= | cpl_addr_reg[63:32];

            cfg_completer_id_reg <= cfg_completer_id;

            snd_resp_reg0 <= snd_resp;
            snd_resp_reg1 <= snd_resp_reg0;

            case (send_fsm)

                s0 : begin
                    trn_td <= 'b0;
                    trn_trem_n <= 8'hFF;
                    drv_ep <= 1'b0;
                    req_ep <= 1'b0;
                    snd_resp_reg0 <= 1'b0;
                    snd_resp_reg1 <= 1'b0;
                    wait_cnt <= wait_cnt + 1;
                    if (wait_cnt == 3'h7) begin
                        send_fsm <= s1;
                    end
                end

                s1 : begin
                    resp_reg <= resp;
                    if (snd_resp_reg1) begin
                        req_ep <= 1'b1;
                        dn <= 1'b1;
                        send_fsm <= s2;
                    end
                end

                s2 : begin
                    if ((my_trn) && (trn_tbuf_av[1]) && (!trn_tdst_rdy_n)) begin
                        req_ep <= 1'b0;
                        drv_ep <= 1'b1;
                        send_fsm <= s3;
                    end
                end

                s3 : begin
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
                        send_fsm <= s4;
                    end
                    else begin
                        trn_trem_n <= 8'h0F;
                        send_fsm <= s6;
                    end
                end

                s4 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td <= cpl_addr_reg;
                        send_fsm <= s5;
                    end
                end

                s5 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td <= qw_endian_conv(resp_reg);
                        trn_teof_n <= 1'b0;
                        send_fsm <= s8;
                    end
                end

                s6 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_tsof_n <= 1'b1;
                        trn_td[63:32] <= cpl_addr_reg[31:0];
                        trn_td[31:0] <= dw_endian_conv(resp_reg[31:0]);
                        send_fsm <= s7;
                    end
                end

                s7 : begin
                    if (!trn_tdst_rdy_n) begin
                        trn_td[63:32] <= dw_endian_conv(resp_reg[63:32]);
                        trn_teof_n <= 1'b0;
                        send_fsm <= s8;
                    end
                end

                s8 : begin
                    wait_cnt <= 'b0;
                    if (!trn_tdst_rdy_n) begin
                        trn_tsrc_rdy_n <= 1'b1;
                        trn_teof_n <= 1'b1;
                        drv_ep <= 1'b0;
                        send_fsm <= s0;
                    end
                end

                default : begin 
                    send_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // regif2tlp

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////