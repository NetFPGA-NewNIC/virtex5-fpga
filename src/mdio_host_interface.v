/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mdio_host_interface.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives PHY (AEL2005) configuration sequence from the host. Drives
*        MDIO engine embedded on the Xilinx 10GMAC core. See ug148
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

module mdio_host_interface (

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

    output reg              cfg_interrupt_n,
    input                   cfg_interrupt_rdy_n,

    // 50 MHz domain
    input                   host_clk,
    input                   host_reset,
    input                   reset156_25,
    output reg  [1:0]       host_opcode,
    output reg  [9:0]       host_addr,
    output reg  [31:0]      host_wr_data,
    input       [31:0]      host_rd_data,
    output reg              host_miim_sel,
    output reg              host_req,
    input                   host_miim_rdy

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
    // Local host_conf_driver
    //-------------------------------------------------------
    reg     [14:0]  host_int_fsm;
    reg             mdio_access_reg0;
    reg             mdio_access_reg1;
    reg     [31:0]  host_data_in_reg;
    reg             generate_interrupt_50mhz;
    reg             reset156_25_reg0;
    reg             reset156_25_reg1;
    reg     [3:0]   wait_counter;

    //-------------------------------------------------------
    // Local generate_interrupt
    //-------------------------------------------------------
    reg     [14:0]  interrupt_fsm;
    reg             generate_interrupt_50mhz_reg;

    //-------------------------------------------------------
    // Local mdio_access from pcie
    //-------------------------------------------------------
    reg     [14:0]  tlp_rx_fsm;
    reg             mdio_access;
    reg     [31:0]  host_data_in;
    reg     [3:0]   mdio_access_counter;

    ////////////////////////////////////////////////
    // host_conf_driver
    ////////////////////////////////////////////////
    always @(posedge host_clk) begin

        if (host_reset) begin  // reset
            generate_interrupt_50mhz <= 1'b0;
            reset156_25_reg0 <= 1'b0;
            reset156_25_reg1 <= 1'b0;
            host_int_fsm <= s0;
        end
        
        else begin  // not reset
            
            mdio_access_reg0 <= mdio_access;
            mdio_access_reg1 <= mdio_access_reg0;

            reset156_25_reg0 <= reset156_25;
            reset156_25_reg1 <= reset156_25_reg0;

            case (host_int_fsm)

                s0 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    wait_counter <= 'b0;
                    if (!reset156_25_reg1) begin
                        host_int_fsm <= s11;
                    end
                end

                s11 : begin
                    wait_counter <= wait_counter + 1;
                    if (wait_counter == 3'b111) begin
                        host_int_fsm <= s1;
                    end
                end

                // see ug148

                s1 : begin                                  // Receiver Configuration Word 1
                    host_opcode[1] <= 1'b0;
                    host_miim_sel <= 1'b0;
                    host_addr <= 10'h240;
                    host_wr_data[15:0] <= 16'b0;            // Pause frame MAC address
                    host_wr_data[25:24] <= 1'b0;            // Length/Type Error Check Disable & Control Frame Length Check Disable
                    host_wr_data[26] <= 1'b1;               // Receiver Preserve Preamble Enable
                    host_wr_data[27] <= 1'b1;               // VLAN Enable
                    host_wr_data[28] <= 1'b1;               // Receiver Enable
                    host_wr_data[29] <= 1'b0;               // In-band FCS Enable
                    host_wr_data[30] <= 1'b0;               // Jumbo Frame Enable
                    host_wr_data[31] <= 1'b0;               // Receiver reset
                    host_int_fsm <= s2;
                end

                s2 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    host_int_fsm <= s3;
                end

                s3 : begin                                  // Transmitter Configuration
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
                    host_int_fsm <= s4;
                end

                s4 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    host_int_fsm <= s5;
                end

                s5 : begin                                  // Management Configuration Word
                    host_opcode[1] <= 2'b0x;
                    host_addr <= 10'h340;
                    host_wr_data[4:0] <= 5'h09;             // Clock Divide
                    host_wr_data[5] <= 1'b1;                // MDIO Enable
                    host_miim_sel <= 1'b0;
                    host_int_fsm <= s6;
                end

                s6 : begin
                    host_opcode <= 2'b11;
                    host_addr <= 10'b0;
                    host_wr_data <= 32'b0;
                    host_miim_sel <= 1'b0;
                    host_req <= 1'b0;
                    host_int_fsm <= s7;
                end

                s7 : begin                                              // wait host configuration
                    host_miim_sel <= 1'b1;
                    generate_interrupt_50mhz <= 1'b0;
                    host_data_in_reg <= host_data_in;
                    if (mdio_access_reg1) begin
                        host_int_fsm <= s8;
                    end
                end

                s8 : begin
                    if (host_miim_rdy) begin
                        host_opcode <= host_data_in_reg[27:26];
                        host_addr <= host_data_in_reg[25:16];
                        host_wr_data[15:0] <= host_data_in_reg[15:0];
                        host_req <= 1'b1;
                        host_int_fsm <= s9;
                    end
                end

                s9 : begin
                    host_req <= 1'b0;
                    host_int_fsm <= s10;
                end

                s10 : begin
                    if (host_miim_rdy) begin
                        generate_interrupt_50mhz <= 1'b1;
                        host_int_fsm <= s7;
                    end
                end

                default : begin
                    host_int_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always

    
    ////////////////////////////////////////////////
    // generate_interrupt
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            cfg_interrupt_n <= 1'b1;
            generate_interrupt_50mhz_reg <= 1'b0;
            interrupt_fsm <= s0;
        end
        
        else begin  // not reset

            generate_interrupt_50mhz_reg <= generate_interrupt_50mhz;           // one pulse of this signal will last for 5 250MHz ticks. avoid re-trigger

            case (interrupt_fsm)

                s0 : begin
                    if (generate_interrupt_50mhz_reg) begin
                        cfg_interrupt_n <= 1'b0;
                        interrupt_fsm <= s1;
                    end
                end

                s1 : begin
                    if (!cfg_interrupt_rdy_n) begin                                     // write tlp pkt was sent for the interrupt
                        cfg_interrupt_n <= 1'b1;
                        interrupt_fsm <= s2;
                    end
                end

                s2 : begin
                    if (!generate_interrupt_50mhz_reg) begin                            // safe to avoid re-trigger
                        interrupt_fsm <= s0;
                    end
                end

                default : begin 
                    interrupt_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always


    ////////////////////////////////////////////////
    // mdio_access from pcie
    ////////////////////////////////////////////////
    always @(posedge trn_clk) begin

        if (reset) begin  // reset
            mdio_access <= 1'b0;
            tlp_rx_fsm <= s0;
        end
        
        else begin  // not reset
            
            case (tlp_rx_fsm)

                s0 : begin
                    mdio_access_counter <= 4'b0;
                    if ( (!trn_rsrc_rdy_n) && (!trn_rsof_n) && (!trn_rdst_rdy_n) && (!trn_rbar_hit_n[0])) begin
                        if (trn_rd[62:56] == `MEM_WR32_FMT_TYPE) begin
                            tlp_rx_fsm <= s1;
                        end
                        else if (trn_rd[62:56] == `MEM_WR64_FMT_TYPE) begin
                            tlp_rx_fsm <= s2;
                        end
                    end
                end

                s1 : begin
                    host_data_in[7:0] <= trn_rd[31:24];
                    host_data_in[15:8] <= trn_rd[23:16];
                    host_data_in[23:16] <= trn_rd[15:8];
                    host_data_in[31:24] <= trn_rd[7:0];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[37:34])
                            4'b0100 : begin
                                tlp_rx_fsm <= s4;
                            end
            
                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s2 : begin
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        case (trn_rd[5:2])
                            4'b0100 : begin
                                tlp_rx_fsm <= s3;
                            end
            
                            default : begin //other addresses
                                tlp_rx_fsm <= s0;
                            end
                        endcase
                    end
                end

                s3 : begin
                    host_data_in[7:0] <= trn_rd[63:56];
                    host_data_in[15:8] <= trn_rd[55:48];
                    host_data_in[23:16] <= trn_rd[47:40];
                    host_data_in[31:24] <= trn_rd[39:32];
                    if ( (!trn_rsrc_rdy_n) && (!trn_rdst_rdy_n)) begin
                        tlp_rx_fsm <= s4;
                    end
                end

                s4 : begin
                    mdio_access <= 1'b1;  // this up for 5 250Mhz ticks (1 50MHz tick)
                    mdio_access_counter <= mdio_access_counter +1;
                    if (mdio_access_counter == 4'h6) begin
                        mdio_access <= 1'b0;
                        tlp_rx_fsm <= s0;
                    end
                end

                default : begin //other TLPs
                    tlp_rx_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // mdio_host_interface

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////