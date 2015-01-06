/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        includes.v
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Some constants.
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
`define INSTRUMENTATION 1

`define CPL_W_DATA_FMT_TYPE 7'b10_01010
`define SC                  3'b000
`define MEM_WR64_FMT_TYPE   7'b11_00000
`define MEM_WR32_FMT_TYPE   7'b10_00000
`define MEM_RD64_FMT_TYPE   7'b01_00000
`define MEM_RD32_FMT_TYPE   7'b00_00000

function [31:0] dw_endian_conv (
    input        [31:0]      dw
    );
begin
    dw_endian_conv[7:0]   = dw[31:24];
    dw_endian_conv[15:8]  = dw[23:16];
    dw_endian_conv[23:16] = dw[15:8];
    dw_endian_conv[31:24] = dw[7:0];
end
endfunction

function [63:0] qw_endian_conv (
    input        [63:0]      qw
    );
begin
    qw_endian_conv[7:0]   = qw[63:56];
    qw_endian_conv[15:8]  = qw[55:48];
    qw_endian_conv[23:16] = qw[47:40];
    qw_endian_conv[31:24] = qw[39:32];
    qw_endian_conv[39:32] = qw[31:24];
    qw_endian_conv[47:40] = qw[23:16];
    qw_endian_conv[55:48] = qw[15:8];
    qw_endian_conv[63:56] = qw[7:0];
end
endfunction