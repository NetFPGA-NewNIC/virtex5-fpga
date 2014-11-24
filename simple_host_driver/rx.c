/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        rx.c
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        
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

#include <linux/module.h>       /* Needed by all modules */
#include <linux/kernel.h>       /* Needed for KERN_INFO */
#include <linux/init.h>         /* Needed for the macros */
#include <linux/types.h>        /* Needed for the macros */
#include <linux/pci.h>
#include <linux/interrupt.h>
#include "my_driver.h"

int rx_init(struct my_driver_host_data *my_drv_data)
{
    int i, j;
    for (i = 0; i < RX_HUGE_PAGE_COUNT; i++)
    {
        my_drv_data->rx.huge_page_kern_addr[i] = pci_alloc_consistent(my_drv_data->pdev, HUGE_PAGE_SIZE, &my_drv_data->rx.huge_page_dma_addr[i]);
        if (my_drv_data->rx.huge_page_kern_addr[i] == NULL)
        {
            printk(KERN_ERR "Myd: alloc huge page\n");
            goto err_01;
        }
    }
    
    // Rx. Hwanju says that pci_alloc_consistent zeros the memory. This is not mandatory
    for (i = 0; i < RX_HUGE_PAGE_COUNT; i++)
        memset(my_drv_data->rx.huge_page_kern_addr[i], 0, HUGE_PAGE_SIZE);

    my_drv_data->rx.current_pkt_dw_index = RX_HUGE_PAGE_DW_HEADER_OFFSET;

    for (i = 0; i < RX_HUGE_PAGE_COUNT; i++)
        rx_send_addr(my_drv_data, my_drv_data->rx.huge_page_dma_addr[i], i);
    
    return 0;

err_01:
    for (j = 0; j < i; j++)
        pci_free_consistent(my_drv_data->pdev, HUGE_PAGE_SIZE, my_drv_data->rx.huge_page_kern_addr[j], my_drv_data->rx.huge_page_dma_addr[j]);
    return -1;
}

void rx_release(struct my_driver_host_data *my_drv_data)
{
    int j;
    for (j = 0; j < RX_HUGE_PAGE_COUNT; j++)
        pci_free_consistent(my_drv_data->pdev, HUGE_PAGE_SIZE, my_drv_data->rx.huge_page_kern_addr[j], my_drv_data->rx.huge_page_dma_addr[j]);
}

inline void rx_send_addr(struct my_driver_host_data *my_drv_data, u64 huge_page_dma_addr, u32 target_huge_page)
{
    writeq(huge_page_dma_addr, my_drv_data->bar2+RX_BAR2_HUGE_PAGE_ADDR_OFFSET+target_huge_page*QW_WIDTH);
}

inline void rx_send_desc(struct my_driver_host_data *my_drv_data, u32 size, u32 target_huge_page)
{
    /* TODO: for now the size of the huge page is fixed to 2MB. expand this to any number like tx */
    writel(0xcacabeef, my_drv_data->bar2+RX_BAR2_HUGE_PAGE_BUFFER_READY_OFFSET+target_huge_page*DW_WIDTH);
}

inline void rx_set_interrupt_period(struct my_driver_host_data *my_drv_data, u64 interrupt_period)
{
    if ((interrupt_period >> 32) & 0xffffffff)
        printk(KERN_INFO "Myd: warning interrupt period is too large\n");

    writel((u32)interrupt_period, my_drv_data->bar2+RX_BAR2_SET_INTERRUPT_PERIOD_OFFSET);
}

inline void rx_interrupt_ctrl(struct my_driver_host_data *my_drv_data, bool set)
{
    if (set)
        writel(0xcacabeef, my_drv_data->bar2+BAR2_ENABLE_INTERRUPTS);
    else
        writel(0xcacabeef, my_drv_data->bar2+BAR2_DISABLE_INTERRUPTS);
}

inline void rx_synch_hw_sw(struct my_driver_host_data *my_drv_data, u64 huge_page_dma_addr)
{
    writeq(huge_page_dma_addr, my_drv_data->bar2+RX_BAR2_HW_SW_SYNCH);
}