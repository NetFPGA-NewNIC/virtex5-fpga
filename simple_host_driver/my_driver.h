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
#define QW_WIDTH 8                                          // bytes
#define DW_WIDTH 4                                          // bytes
#define HUGE_PAGE_SIZE 2*1024*1024                          // bytes
#define HUGE_PAGE_SIZE_DW 2*1024*1024/4                     // dwords
#define MAX_ETH_SIZE 1514
#define QW_ALIGNED 0x8

// Interrupt ctrl
#define BAR2_ENABLE_INTERRUPTS 32
#define BAR2_DISABLE_INTERRUPTS 36
#define ENABLE_INTERRUPT true
#define DISABLE_INTERRUPT false

//RX
#define RX_HW_TIMEOUT 256                                     // ns
#define RX_BAR2_HUGE_PAGE_ADDR_OFFSET 64
#define RX_BAR2_HUGE_PAGE_BUFFER_READY_OFFSET 96
#define RX_HUGE_PAGE_COUNT 2
#define RX_BAR2_SET_INTERRUPT_PERIOD_OFFSET 40
#define RX_HUGE_PAGE_DW_HEADER_OFFSET 32                      // dwords of huge page header
#define RX_HUGE_PAGE_STATUS_QW_SIZE 8                         // byte
#define RX_FRAME_DW_HEADER 2
#define RX_HUGE_PAGE_CLOSED_BIT_POS 32
//#define RX_TIMESTAMP_TEST 1
#define RX_BAR2_HW_SW_SYNCH 120

//Simple RTT
#define RTT_BAR2_SEND_TEST_OFFSET 44

irqreturn_t mdio_access_interrupt_handler(int irq, void *dev_id);
irqreturn_t simple_rtt_test_interrupt_handler(int irq, void *dev_id);

void rx_wq_function(struct work_struct *wk);

struct rx {
    u64 huge_page_dma_addr[RX_HUGE_PAGE_COUNT];
    void *huge_page_kern_addr[RX_HUGE_PAGE_COUNT];
    u8 huge_page_index;
    u32 current_pkt_dw_index;
    u64 interrupt_period_index;
};

struct my_work_t {
    struct work_struct work;
    struct my_driver_host_data *my_drv_data_ptr;
};

struct my_driver_host_data {
    struct workqueue_struct *rx_wq;
    struct my_work_t rx_work;
    struct net_device *my_net_device;
    struct pci_dev *pdev;
    void *bar2;
    void *bar0;

    struct rx rx;

    // MDIO simple_conf
    atomic_t mdio_access_rdy;

    // RTT simple_test
    atomic_t rtt_access_rdy;
    u64 rtt;
    ktime_t tstamp_b;
};

int configure_ael2005_phy_chips(struct my_driver_host_data *my_drv_data);
int simple_rtt_test(struct my_driver_host_data *my_drv_data);
int rx_init(struct my_driver_host_data *my_drv_data);
void rx_release(struct my_driver_host_data *my_drv_data);
inline void rx_set_interrupt_period(struct my_driver_host_data *my_drv_data, u64 interrupt_period);
inline void rx_send_addr(struct my_driver_host_data *my_drv_data, u64 huge_page_dma_addr, u32 target_huge_page);
inline void rx_send_desc(struct my_driver_host_data *my_drv_data, u32 size, u32 target_huge_page);
inline void rx_interrupt_ctrl(struct my_driver_host_data *my_drv_data, bool set);
inline void rx_synch_hw_sw(struct my_driver_host_data *my_drv_data, u64 huge_page_dma_addr);

#endif
