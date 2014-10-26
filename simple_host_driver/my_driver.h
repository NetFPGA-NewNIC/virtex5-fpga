/*******************************************************************************
*
*  NetFPGA-10G http://www.netfpga.org
*
*  File:
*        my_driver.h
*
*  Project:
*
*
*  Author:
*        Marco Forconesi
*
*  Description:
*        Simple device driver
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

#ifndef MY_DRIVER_H
#define MY_DRIVER_H

#define XILINX_VENDOR_ID 0x10EE
#define MY_APPLICATION_ID 0x4245
#define MY_DEBUG 1
#define DRV_NAME "my_driver"
#define PCI_BAR0 0
#define PCI_BAR2 2

irqreturn_t mdio_access_interrupt_handler(int irq, void *dev_id);
irqreturn_t simple_rtt_test_interrupt_handler(int irq, void *dev_id);

void rx_wq_function(struct work_struct *wk);

struct my_work_t {
    struct work_struct work;
    struct my_driver_host_data *my_drv_data_ptr;
};

struct my_driver_host_data {
    
    struct workqueue_struct *rx_wq;
    struct my_work_t rx_work;

    struct net_device *my_net_device;

    struct pci_dev *pdev;
    
    u64 huge_page1_dma_addr;
    u64 huge_page2_dma_addr;

    void *huge_page_kern_address1;
    void *huge_page_kern_address2;

    u8 huge_page_index;
    u32 current_pkt_dw_index;

    #ifdef MY_DEBUG
    int total_numb_of_huge_pages_processed;
    #endif

    void *bar2;
    void *bar0;

    // Tx
    struct page *tx_completion_buff;
    struct page *tx_test_page;

    u64 tx_completion_buff_dma_addr;
    u64 tx_test_page_dma_addr;

    void *tx_completion_buff_kern_address;
    void *tx_test_page_kern_address;

    atomic_t mdio_access_rdy;

    atomic_t rtt_access_rdy;
    u64 rtt;
    u64 tstamp_b;

};

int configure_ael2005_phy_chips(struct my_driver_host_data *my_drv_data);
int simple_rtt_test(struct my_driver_host_data *my_drv_data);

#endif
