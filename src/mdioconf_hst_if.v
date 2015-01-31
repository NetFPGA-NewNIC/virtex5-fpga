/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mdioconf_hst_if.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Drives host interface.
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

module mdioconf_hst_if (

    input                    bkd_rst,

    // Host Conf Intf
    input                    host_clk,
    input                    host_reset,
    output reg   [1:0]       host_opcode,
    output reg   [9:0]       host_addr,
    output reg   [31:0]      host_wr_data,
    input        [31:0]      host_rd_data,
    output reg               host_miim_sel,
    output reg               host_req,
    input                    host_miim_rdy,

    // tlp2mdio
    input        [31:0]      acc_data,
    input                    acc_en,
    output reg               acc_en_ack,

    // irq_gen
    output reg               send_irq
    );

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
    // Local hst_if
    //-------------------------------------------------------  
    reg          [14:0]      hst_if_fsm;
    reg                      bkd_rst_reg0;
    reg                      bkd_rst_reg1;
    reg          [2:0]       wait_counter;
    reg                      acc_en_reg0;
    reg                      acc_en_reg1;
    reg          [31:0]      acc_data_reg;

    ////////////////////////////////////////////////
    // hst_if
    ////////////////////////////////////////////////
    always @(posedge host_clk) begin

        if (host_reset) begin  // rst
            send_irq <= 1'b0;
            acc_en_ack <= 1'b0;
            hst_if_fsm <= s0;
        end
        
        else begin  // not rst

            bkd_rst_reg0 <= bkd_rst;
            bkd_rst_reg1 <= bkd_rst_reg0;

            acc_en_reg0 <= acc_en;
            acc_en_reg1 <= acc_en_reg0;

            send_irq <= 1'b0;
            acc_en_ack <= 1'b0;

            case (hst_if_fsm)

                s0 : begin
                    bkd_rst_reg0 <= 1'b0;
                    bkd_rst_reg1 <= 1'b0;
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    wait_counter <= 'b0;
                    hst_if_fsm <= s1;
                end

                s1 : begin
                    if (!bkd_rst_reg1) begin
                        hst_if_fsm <= s2;
                    end
                end

                s2 : begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter == 3'b111) begin
                        hst_if_fsm <= s3;
                    end
                end

                // see ug148

                s3 : begin                                  // Receiver Configuration Word 1
                    host_opcode[1] <= 1'b0;
                    host_miim_sel <= 1'b0;
                    host_addr <= 10'h240;
                    host_wr_data[15:0] <= 'b0;              // Pause frame MAC address
                    host_wr_data[23:16] <= 'b0;             // Reserved
                    host_wr_data[24] <= 1'b0;               // Control Frame Length Check Disable
                    host_wr_data[25] <= 1'b1;               // Length/Type Error Check Disable
                    host_wr_data[26] <= 1'b1;               // Receiver Preserve Preamble Enable
                    host_wr_data[27] <= 1'b1;               // VLAN Enable
                    host_wr_data[28] <= 1'b1;               // Receiver Enable
                    host_wr_data[29] <= 1'b0;               // In-band FCS Enable
                    host_wr_data[30] <= 1'b0;               // Jumbo Frame Enable
                    host_wr_data[31] <= 1'b0;               // Receiver reset
                    hst_if_fsm <= s4;
                end

                s4 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    hst_if_fsm <= s5;
                end

                s5 : begin                                  // Transmitter Configuration
                    host_opcode[1] <= 1'b0;
                    host_miim_sel <= 1'b0;
                    host_addr <= 10'h280;
                    host_wr_data[23] <= 1'b0;               // Transmitter Preserve Preamble Enable
                    host_wr_data[24] <= 1'b1;               // Deficit Idle Count Enable
                    host_wr_data[25] <= 1'b0;               // Interframe Gap Adjust Enable
                    host_wr_data[26] <= 1'b0;               // WAN Mode Enable
                    host_wr_data[27] <= 1'b0;               // VLAN Enable
                    host_wr_data[28] <= 1'b1;               // Transmitter Enable
                    host_wr_data[29] <= 1'b0;               // In-band FCS Enable
                    host_wr_data[30] <= 1'b0;               // Jumbo Frame Enable
                    host_wr_data[31] <= 1'b0;               // Transmitter Reset
                    hst_if_fsm <= s6;
                end

                s6 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    hst_if_fsm <= s7;
                end

                s7 : begin                                  // Management Configuration Word
                    host_opcode[1] <= 1'b0;
                    host_addr <= 10'h340;
                    host_wr_data[4:0] <= 5'h09;             // Clock Divide
                    host_wr_data[5] <= 1'b1;                // MDIO Enable
                    host_miim_sel <= 1'b0;
                    hst_if_fsm <= s8;
                end

                s8 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    hst_if_fsm <= s9;
                end

                s9 : begin                                              // wait host access
                    host_miim_sel <= 1'b1;
                    acc_data_reg <= acc_data;
                    if (acc_en_reg1) begin
                        acc_en_ack <= 1'b1;
                        hst_if_fsm <= s10;
                    end
                end

                s10 : begin
                    if (host_miim_rdy) begin
                        host_opcode <= acc_data_reg[27:26];
                        host_addr <= acc_data_reg[25:16];
                        host_wr_data[15:0] <= acc_data_reg[15:0];
                        host_req <= 1'b1;
                        hst_if_fsm <= s11;
                    end
                end

                s11 : begin
                    host_req <= 1'b0;
                    hst_if_fsm <= s12;
                end

                s12 : begin
                    if (host_miim_rdy) begin
                        send_irq <= 1'b1;
                        hst_if_fsm <= s9;
                    end
                end

                default : begin
                    hst_if_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // mdioconf_hst_if

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////