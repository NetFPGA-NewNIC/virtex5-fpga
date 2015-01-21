/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        mac2ibuf.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        eth frames 2 internal buff
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

module mac2ibuf # (
    parameter BW = 10
    ) (

    input                    clk,
    input                    rst,

    // MAC rx
    input        [63:0]      rx_data,
    input        [7:0]       rx_data_valid,
    input                    rx_good_frame,
    input                    rx_bad_frame,

    // ibuf
    output reg   [BW-1:0]    wr_addr,
    output reg   [63:0]      wr_data,

    // fwd logic
    input                    hst_rdy,
    output reg               activity,
    output reg   [BW:0]      committed_prod,
    input        [BW:0]      committed_cons,
    output reg   [15:0]      dropped_pkts
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

    localparam MAX_DIFF = (2**BW) - 10;

    //-------------------------------------------------------
    // Local mac2ibuf
    //-------------------------------------------------------
    reg          [7:0]       rx_fsm;
    reg          [15:0]      len;
    reg          [BW:0]      aux_wr_addr;
    reg          [BW:0]      diff;
    reg          [7:0]       rx_data_valid_reg;
    reg                      rx_good_frame_reg;
    reg                      rx_bad_frame_reg;
    reg                      hst_rdy_reg0;
    reg                      hst_rdy_reg1;

    ////////////////////////////////////////////////
    // Inbound ethernet frame to ibuf
    ////////////////////////////////////////////////
    always @(posedge clk) begin

        if (rst) begin  // rst
            rx_fsm <= s0;
        end
        
        else begin  // not rst
            
            diff <= aux_wr_addr + (~committed_cons) +1;
            activity <= 1'b0;

            hst_rdy_reg0 <= hst_rdy;
            hst_rdy_reg1 <= hst_rdy_reg0;

            case (rx_fsm)

                s0 : begin
                    committed_prod <= 'b0;
                    dropped_pkts <= 'b0;
                    hst_rdy_reg0 <= 1'b0;
                    hst_rdy_reg1 <= 1'b0;
                    rx_fsm <= s1;
                end

                s1 : begin
                    if (hst_rdy_reg1) begin
                        rx_fsm <= s2;
                    end
                end

                s2 : begin
                    if (!rx_data_valid) begin      // wait eof if any ongoing
                        rx_fsm <= s3;
                    end
                end

                s3 : begin                                  // configure mac core to present preamble and save the packet timestamp
                    len <= 'b0;
                    aux_wr_addr <= committed_prod +1;
                    if (rx_data_valid) begin      // wait for sof (preamble)
                        rx_fsm <= s4;
                    end
                end

                s4 : begin
                    wr_data <= rx_data;
                    wr_addr <= aux_wr_addr;
                    aux_wr_addr <= aux_wr_addr +1;
                    activity <= 1'b1;

                    rx_data_valid_reg <= rx_data_valid;
                    rx_good_frame_reg <= rx_good_frame;
                    rx_bad_frame_reg <= rx_bad_frame;
                    
                    case (rx_data_valid)
                        8'b00000000 : begin
                            len <= len;
                            aux_wr_addr <= aux_wr_addr;
                        end
                        8'b00000001 : begin
                            len <= len + 1;
                        end
                        8'b00000011 : begin
                            len <= len + 2;
                        end
                        8'b00000111 : begin
                            len <= len + 3;
                        end
                        8'b00001111 : begin
                            len <= len + 4;
                        end
                        8'b00011111 : begin
                            len <= len + 5;
                        end
                        8'b00111111 : begin
                            len <= len + 6;
                        end
                        8'b01111111 : begin
                            len <= len + 7;
                        end
                        8'b11111111 : begin
                            len <= len + 8;
                        end
                    endcase

                    if (diff > MAX_DIFF) begin           // ibufer is almost full
                        rx_fsm <= s6;
                    end
                    else if (rx_good_frame) begin        // eof (good frame)
                        rx_fsm <= s5;
                    end
                    else if (rx_bad_frame) begin
                        rx_fsm <= s3;
                    end
                end

                s5 : begin
                    wr_data <= {1'b0, 15'b0, len, 32'b0};
                    wr_addr <= committed_prod;
                    activity <= 1'b1;

                    committed_prod <= aux_wr_addr;                      // commit the packet
                    aux_wr_addr <= aux_wr_addr +1;
                    len <= 'b0;

                    if (rx_data_valid) begin        // sof (preamble)
                        rx_fsm <= s4;
                    end
                    else begin
                        rx_fsm <= s3;
                    end
                end
                
                s6 : begin                                  // drop current frame
                    if (rx_good_frame || rx_good_frame_reg || rx_bad_frame  || rx_bad_frame_reg) begin
                        dropped_pkts <= dropped_pkts +1; 
                        rx_fsm <= s3;
                    end
                end

                default : begin 
                    rx_fsm <= s0;
                end

            endcase
        end     // not rst
    end  //always

endmodule // mac2ibuf

//////////////////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////////////////////////////////////////////////////////////////