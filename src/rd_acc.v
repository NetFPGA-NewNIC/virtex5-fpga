/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rd_acc.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Drives register interface.
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

module rd_acc # (
    parameter ACK_CODE = 32'h1,
    parameter NACK_CODE = 32'h2
    ) (

    input                    clk,
    input                    rst_n,

    // tlp2regif
    input        [31:0]      acc_addr,
    input        [31:0]      acc_data,
    input                    acc_en,
    output reg               acc_en_ack,

    // REGIF
    output reg               IP2Bus_MstRd_Req,
    output reg   [31:0]      IP2Bus_Mst_Addr,
    input                    Bus2IP_Mst_CmdAck,
    input                    Bus2IP_Mst_Cmplt,
    input                    Bus2IP_Mst_Error,
    input        [31:0]      Bus2IP_MstRd_d,
    input                    Bus2IP_MstRd_src_rdy_n,

    // regif2tlp
    output reg               snd_resp,
    input                    snd_resp_ack,
    output reg   [63:0]      resp,

    // REGIF ARB
    input                    my_regif,
    output reg               drv_regif
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

    //-------------------------------------------------------
    // Local acc
    //-------------------------------------------------------  
    reg          [7:0]       acc_fsm;
    reg                      acc_en_reg0;
    reg                      acc_en_reg1;
    reg          [31:0]      acc_addr_reg;
    reg          [31:0]      acc_data_reg;
    reg                      snd_resp_ack_reg0;
    reg                      snd_resp_ack_reg1;
    reg                      acc_nack;

    ////////////////////////////////////////////////
    // acc
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (!rst_n) begin  // rst
            IP2Bus_MstRd_Req <= 1'b0;
            acc_en_ack <= 1'b0;
            snd_resp <= 1'b0;
            acc_fsm <= s0;
        end
        
        else begin  // not rst

            acc_en_ack <= 1'b0;

            acc_en_reg0 <= acc_en;
            acc_en_reg1 <= acc_en_reg0;

            snd_resp_ack_reg0 <= snd_resp_ack;
            snd_resp_ack_reg1 <= snd_resp_ack_reg0;

            case (acc_fsm)

                s0 : begin
                    IP2Bus_Mst_Addr <= 'b0;
                    acc_en_reg0 <= 1'b0;
                    acc_en_reg1 <= 1'b0;
                    drv_regif <= 1'b0;
                    acc_fsm <= s1;
                end

                s1 : begin                                              // wait host access
                    acc_addr_reg <= acc_addr;
                    if (acc_en_reg1) begin
                        acc_en_ack <= 1'b1;
                        acc_fsm <= s2;
                    end
                end

                s2 : begin
                    if (my_regif) begin
                        drv_regif <= 1'b1;
                        acc_fsm <= s3;
                    end
                end

                s3 : begin
                    IP2Bus_MstRd_Req <= 1'b1;
                    IP2Bus_Mst_Addr <= acc_addr_reg;
                    acc_fsm <= s4;
                end

                s4 : begin
                    snd_resp_ack_reg0 <= 1'b0;
                    snd_resp_ack_reg1 <= 1'b0;
                    acc_data_reg <= Bus2IP_MstRd_d;
                    if (Bus2IP_Mst_CmdAck) begin
                        IP2Bus_MstRd_Req <= 1'b0;
                    end
                    if (Bus2IP_Mst_Cmplt) begin
                        if (Bus2IP_Mst_Error) begin
                            acc_nack <= 1'b1;
                        end
                        else begin
                            acc_nack <= 1'b0;
                        end
                    end
                    if (!Bus2IP_MstRd_src_rdy_n) begin
                        acc_fsm <= s5;
                    end
                end

                s5 : begin
                    resp[31:0] <= acc_data_reg;
                    resp[63:32] <= acc_nack ? NACK_CODE : ACK_CODE;
                    acc_fsm <= s6;
                end

                s6 : begin
                    snd_resp <= 1'b1;
                    acc_fsm <= s7;
                end

                s7 : begin
                    if (snd_resp_ack_reg1) begin
                        snd_resp <= 1'b0;
                        acc_fsm <= s0;
                    end
                end

                default : begin
                    acc_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // rd_acc

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////