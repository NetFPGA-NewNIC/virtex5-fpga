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




// Internal buffer address width. s; 

//Set to 8 to specify 9-bit width (4KB)
`define BF 8 
`define MAX_DIFF 9'h1E0
//set to 9 for 10-bit width (8KB)
//`define BF 9 
//`define MAX_DIFF 11'h3E8
