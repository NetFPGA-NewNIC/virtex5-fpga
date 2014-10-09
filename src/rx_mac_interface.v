/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx_mac_interface.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Receives ethernet frames from the MAC core and writes it to the
*        rx internal buffer. If the ethernet CRC (FCS) is invalid, the module
*        will drop the frame. If the internal buffer is almost full, the module
*        will drop the current frame.
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

module rx_mac_interface (

    input    clk,
    input    reset_n,

    // MAC Rx
    input    [63:0]      rx_data,
    input    [7:0]       rx_data_valid,
    input                rx_good_frame,
    input                rx_bad_frame,

    // Internal memory driver
    output reg    [`BF:0]     wr_addr,
    output reg    [63:0]      wr_data,
    output reg                wr_en,
    
    // Internal logic
    output reg    [`BF:0]     commited_wr_address,
    input         [`BF:0]     commited_rd_address

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
    // Local ethernet frame reception and memory write
    //-------------------------------------------------------
    reg     [7:0]     rx_fsm;
    reg     [15:0]    byte_counter;
    reg     [`BF:0]   aux_wr_addr;
    reg     [`BF:0]   diff;
    (* KEEP = "TRUE" *)reg     [31:0]   dropped_frames_counter;
    
    reg     [7:0]    rx_data_valid_reg;
    reg              rx_good_frame_reg;
    reg              rx_bad_frame_reg;

    //-------------------------------------------------------
    // Local ts_sec-and-ts_nsec-generation
    //-------------------------------------------------------
    reg     [31:0]   ts_sec;
    reg     [31:0]   ts_nsec;
    reg     [27:0]   free_running;

    ////////////////////////////////////////////////
    // ts_sec-and-ts_nsec-generation
    ////////////////////////////////////////////////
    always @( posedge clk or negedge reset_n ) begin

        if (!reset_n ) begin  // reset
            ts_sec <= 32'b0;
            ts_nsec <= 32'b0;
            free_running <= 28'b0;
        end
        
        else begin  // not reset
            free_running <= free_running +1;
            ts_nsec <= ts_nsec + 6;
            if (free_running == 28'd156250000) begin
              free_running <= 28'b0;
              ts_sec <= ts_sec +1;
              ts_nsec <= 32'b0;
            end

        end     // not reset
    end  //always

    ////////////////////////////////////////////////
    // ethernet frame reception and memory write
    ////////////////////////////////////////////////
    always @( posedge clk or negedge reset_n ) begin

        if (!reset_n ) begin  // reset
            commited_wr_address <= 'b0;
            dropped_frames_counter <= 'b0;
            wr_en <= 1'b1;
            rx_fsm <= s0;
        end
        
        else begin  // not reset
            
            // commited_rd_address is the pointer at which PCIe endpoint has
            // consumed, so aux_wr_addr - commited_rd_address is the size of
            // buffer filled. All pointers are in QWORD.
            diff <= aux_wr_addr + (~commited_rd_address) +1;
            wr_en <= 1'b1;
            
            case (rx_fsm)
                // RX internal buffer structure:
                //             QWORDS
                //        +-------------+
                //        | prev packet |
                //        |-------------|<-- commited_wr_address
                //        | len  |      | == 8B metadata region
                //        |-------------|
                //        |   rx_data   |<-- aux_wr_addr (current uncommited write pointer)
                //        |             |
                s0 : begin                                  // configure mac core to present preamble and save the packet timestamp while its reception
					// [initialization]
                    byte_counter <= 'b0;

					// awx_wr_addr initialization works also as pointer rollback
					// if the packet is a bad frame (i.e., s1->s0).
					// + 1 means 8B reserved region for packet length
                    aux_wr_addr <= commited_wr_address +1;	
                    if (rx_data_valid) begin      // wait for sof (preamble)
                        rx_fsm <= s1;
                    end
                end

                s1 : begin
                    // [rx data fill] s0 or s2 -> s1 if rx_data_valid
                    // write rx_data from MAC by 8B at aux_wr_addr until good or
                    // bad or full.
                    wr_data <= rx_data;
                    wr_addr <= aux_wr_addr;
                    aux_wr_addr <= aux_wr_addr +1;

                    rx_data_valid_reg <= rx_data_valid;
                    rx_good_frame_reg <= rx_good_frame;
                    rx_bad_frame_reg <= rx_bad_frame;
                    
                    case (rx_data_valid)     // increment byte_counter accordingly
                        8'b00000000 : begin
                            byte_counter <= byte_counter;       // don't increment
                            aux_wr_addr <= aux_wr_addr;
                        end
                        8'b00000001 : begin
                            byte_counter <= byte_counter + 1;
                        end
                        8'b00000011 : begin
                            byte_counter <= byte_counter + 2;
                        end
                        8'b00000111 : begin
                            byte_counter <= byte_counter + 3;
                        end
                        8'b00001111 : begin
                            byte_counter <= byte_counter + 4;
                        end
                        8'b00011111 : begin
                            byte_counter <= byte_counter + 5;
                        end
                        8'b00111111 : begin
                            byte_counter <= byte_counter + 6;
                        end
                        8'b01111111 : begin
                            byte_counter <= byte_counter + 7;
                        end
                        8'b11111111 : begin
                            byte_counter <= byte_counter + 8;
                        end
                    endcase

                    if (diff > `MAX_DIFF) begin         // buffer is more than 90%
                        rx_fsm <= s3;
                    end
                    else if (rx_good_frame) begin        // eof (good frame)
                        rx_fsm <= s2;
                    end
                    else if (rx_bad_frame) begin
                        rx_fsm <= s0;
                    end
                end

                s2 : begin
                    // [rx packet commit] s1 -> s2 if a good packet is received
                    // before updating commited_wr_address, which is currently
                    // at the beginning of the current packet, packet length
                    // is written at the metadata region
                    wr_data <= {byte_counter, 32'b0};
                    wr_addr <= commited_wr_address;

                    commited_wr_address <= aux_wr_addr;                      // commit the packet
                    // reserve 8B metadata region and initialize byte_counter
                    aux_wr_addr <= aux_wr_addr +1;
                    byte_counter <= 32'b0;

                    if (rx_data_valid) begin        // sof (preamble)
                        rx_fsm <= s1;
                    end
                    else begin
                        rx_fsm <= s0;
                    end
                end
                
                s3 : begin                                  // drop current frame
                    // [rx buffer full]
                    if (rx_good_frame || rx_good_frame_reg || rx_bad_frame  || rx_bad_frame_reg) begin
                        dropped_frames_counter <= dropped_frames_counter +1; 
                        rx_fsm <= s0;
                    end
                end

                default : begin 
                    rx_fsm <= s0;
                end

            endcase
        end     // not reset
    end  //always
   

endmodule // rx_mac_interface

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////
